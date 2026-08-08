local glib = require("__glib__.glib")
local glib_frame = require("__glib__.examples.default_frame")

---@alias ResearchState table<string, { tech: LuaTechnology, researched: boolean, progress: number }>
---@alias ResearchCount table<string, number>

do
    ---@class ResearchMilestone
    ---@field technologies string[]

    ---@class PerPlayerStorage
    ---@field milestones ResearchMilestone[]
end

---@param player_index integer
---@return PerPlayerStorage
local function get_storage(player_index)
    local players = storage.players --[[@as table<integer, PerPlayerStorage>]]
    if (not players) then
        players = {}
        storage.players = players
    end

    local result = players[player_index]
    if (not result) then
        result = { milestones = {} }
        players[player_index] = result
    end

    return result
end

local handler = {}

---@param element LuaGuiElement
---@param tag_name string
---@return AnyBasic?
local function find_tag(element, tag_name)
    while (element) do
        local tag = element.tags[tag_name]
        if (tag ~= nil) then
            return tag
        end
        element = element.parent
    end
end

---@param force LuaForce
---@return ResearchState
local function get_current_state(force)
    local result = {} ---@type ResearchState
    for name, tech in pairs(force.technologies) do
        result[name] = { tech = tech, researched = tech.researched, progress = tech.saved_progress }
    end

    return result
end

---@param state ResearchState
---@param research ResearchCount
---@param target LuaTechnologyPrototype
local function accumulate_research(state, research, target)
    if (type(target) == "string") then
        target = prototypes.technology[target]
    end
    local current = state[target.name]
    if (current.researched) then
        return
    end

    local count = target.research_unit_count
    for _, ingredient in ipairs(target.research_unit_ingredients) do
        local icount = research[ingredient.name] or 0
        icount = icount + count * ingredient.amount
        research[ingredient.name] = icount
    end

    for _, prerequisite in pairs(target.prerequisites) do
        accumulate_research(state, research, prerequisite)
    end

    current.researched = true
end

---@param technologies string[]
---@return GuiElemDef
local function build_row_of_technologies(technologies, milestone_idx)
    ---@type GuiElemDef[]
    local children = {}

    if (milestone_idx > 1 and #technologies > 0) then
        children[#children + 1] = {
            args = {
                type = "sprite-button",
                sprite = "utility.speed_up"
            },
            _click = handler.on_milestone_move_up
        }
    end

    for i, name in ipairs(technologies) do
        children[#children + 1] = {
            args = {
                type = "sprite-button",
                sprite = "technology." .. name,
                elem_tooltip = { type = "technology", name = name },
                tags = {
                    technology_idx = i
                }
            },
            _click = handler.on_remove_technology
        }
    end

    children[#children + 1] = {
        args = {
            type = "choose-elem-button",
            elem_type = "technology"
        },
        _elem_changed = handler.on_add_technology
    }

    ---@type GuiElemDef
    return {
        args = {
            type = "flow",
            direction = "horizontal",
            tags = {
                milestone_idx = milestone_idx
            }
        },
        children = children
    }
end

---@param force LuaForce
---@param milestones ResearchMilestone[]
---@return GuiElemDef
local function build_gui(force, milestones)
    local state = get_current_state(force)
    ---@type GuiElemDef[]
    local rows = {}
    for i, milestone in ipairs(milestones) do
        local research = {} ---@type ResearchCount
        for _, name in ipairs(milestone.technologies) do
            accumulate_research(state, research, prototypes.technology[name])
        end

        rows[#rows + 1] = build_row_of_technologies(milestone.technologies, i)

        for science_pack, amount in pairs(research) do
            rows[#rows + 1] = {
                args = { type = "flow", direction = "horizontal" },
                children = {
                    { args = { type = "label", caption = amount .. " [item=" .. science_pack .. "]" } }
                }
            }
        end
    end

    rows[#rows + 1] = build_row_of_technologies({}, #milestones + 1)

    local result = { args = { type = "flow", direction = "vertical" }, children = rows }
    return result
end

local function open_gui(player_index)
    local player = game.players[player_index]
    local force = player.force --[[@as LuaForce]]

    local old_wnd = player.gui.screen["sw-research-planner-mainwnd"]
    if (old_wnd) then
        old_wnd.destroy()
    end

    local frame = glib_frame("sw-research-planner-mainwnd", "Research Planner")
    local wnd, refs = glib.add(player.gui.screen, frame)
    wnd.auto_center = true
    player.opened = wnd

    local storage = get_storage(player_index)
    local gui = build_gui(force, storage.milestones)
    glib.add(wnd, gui)
end

---@param event EventData.on_gui_click
function handler.on_milestone_move_up(event)
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local storage = get_storage(event.player_index)
    local milestones = storage.milestones
    milestones[milestone_idx], milestones[milestone_idx - 1] = milestones[milestone_idx - 1], milestones[milestone_idx]
    open_gui(event.player_index)
end

---@param event EventData.on_gui_elem_changed
function handler.on_add_technology(event)
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local storage = get_storage(event.player_index)
    local milestone = storage.milestones[milestone_idx]
    if (not milestone) then
        milestone = { technologies = {} }
        storage.milestones[milestone_idx] = milestone
    end

    local technologies = milestone.technologies
    technologies[#technologies + 1] = event.element.elem_value --[[@as string]]
    open_gui(event.player_index)
end

---@param event EventData.on_gui_click
function handler.on_remove_technology(event)
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local technology_idx = find_tag(event.element, "technology_idx") --[[@as integer]]
    local storage = get_storage(event.player_index)
    local milestone = storage.milestones[milestone_idx]
    local technologies = milestone.technologies
    table.remove(technologies, technology_idx)
    if (#technologies == 0) then
        table.remove(storage.milestones, milestone_idx)
    end
    open_gui(event.player_index)
end

script.on_event(defines.events.on_lua_shortcut, function(event)
    if (event.prototype_name == "sw-research-planner-shortcut") then
        open_gui(event.player_index)
    end
end)

script.on_event("sw-research-planner-configure", function(event)
    open_gui(event.player_index --[[@as integer]])
end)

glib.register_handlers(handler)
