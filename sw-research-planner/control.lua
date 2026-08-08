local glib = require("__glib__.glib")
local glib_frame = require("__glib__.examples.default_frame")

---@alias ResearchState table<string, { tech: LuaTechnology, researched: boolean, progress: number }>
---@alias ResearchCount table<string, number>

do
    ---@class ResearchMilestone
    ---@field technologies string[]
    ---@field production table<string, number>

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

    if (force.current_research) then
        result[force.current_research.name].progress = force.research_progress
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
        icount = icount + count * ingredient.amount * (1 - current.progress)
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
                tags = { technology_idx = i }
            },
            _click = handler.on_remove_technology
        }
    end

    children[#children + 1] = {
        args = {
            type = "choose-elem-button",
            elem_type = "technology",
            tooltip = #technologies > 0 and "add technology" or "add milestone"
        },
        _elem_changed = handler.on_add_technology
    }

    ---@type GuiElemDef
    return {
        args = {
            type = "flow",
            direction = "horizontal"
        },
        children = children
    }
end

local function format_int(number)
    local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')
    int = int:reverse():gsub("(%d%d%d)", "%1,")
    return minus .. int:reverse():gsub("^,", "") .. fraction
end

local second = 60
local minute = 60 * second
local hour = 60 * minute

---@param ticks number
---@return string
local function format_time(ticks)
    ticks = math.floor(ticks)
    local hours = math.floor(ticks / hour)
    ticks = ticks - (hours * hour)
    local minutes = math.floor(ticks / minute)
    ticks = ticks - (minutes * minute)
    local seconds = math.floor(ticks / second)
    ticks = ticks - (seconds * second)

    if (hours > 0) then
        return string.format("%02d:%02d:%02d", hours, minutes, seconds)
    else
        return string.format("%02d:%02d", minutes, seconds)
    end
end

---@param force LuaForce
---@param milestones ResearchMilestone[]
---@return GuiElemDef
local function build_gui(force, milestones)
    local state = get_current_state(force)
    local tick = game.tick
    ---@type GuiElemDef[]
    local all_rows = {}
    for i, milestone in ipairs(milestones) do
        ---@type GuiElemDef[]
        local rows = {}
        local research = {} ---@type ResearchCount
        for _, name in ipairs(milestone.technologies) do
            accumulate_research(state, research, prototypes.technology[name])
        end

        rows[#rows + 1] = build_row_of_technologies(milestone.technologies, i)
        local time = 0
        for science_pack, amount in pairs(research) do
            local spm = milestone.production[science_pack] or 0
            if (spm > 0) then
                local t = amount / spm
                if (t > time) then
                    time = t
                end
            end
        end

        for science_pack, amount in pairs(research) do
            local spm = milestone.production[science_pack] or 0
            rows[#rows + 1] = {
                args = {
                    type = "flow",
                    direction = "horizontal",
                    tags = { item = science_pack }
                },
                children = {
                    {
                        args = {
                            type = "label",
                            caption = "[item=" .. science_pack .. "] " .. format_int(math.ceil(amount))
                        },
                        style_mods = {
                            width = 150,
                            top_margin = 4
                        }
                    },
                    {
                        args = {
                            type = "textfield",
                            text = tostring(spm),
                            numeric = true,
                            allow_decimal = true
                        },
                        style_mods = {
                            width = 80,
                            right_margin = 4
                        },
                        _confirmed = handler.on_spm_confirmed
                    }
                }
            }
            if (spm > 0) then
                local t = amount / spm
                local children = rows[#rows].children
                children[#children + 1] = {
                    args = {
                        type = "label",
                        caption = format_time(t * minute)
                    },
                    style_mods = {
                        top_margin = 4,
                        font_color = t == time and { 1, 0, 0 } or { 1, 1, 1 }
                    }
                }
            end
        end

        if (time > 0) then
            rows[#rows + 1] = {
                args = {
                    type = "label",
                    caption = "Research finished: " .. format_time(time * minute + tick)
                }
            }
            tick = tick + time * minute
        end

        all_rows[#all_rows + 1] = {
            args = {
                type = "flow",
                direction = "vertical",
                tags = { milestone_idx = i }
            },
            children = rows
        }
    end

    local add_milestone_button = build_row_of_technologies({}, #milestones + 1)
    add_milestone_button.args.tags = { milestone_idx = #milestones + 1 }
    all_rows[#all_rows + 1] = add_milestone_button

    ---@type GuiElemDef
    return {
        args = {
            type = "flow",
            direction = "vertical"
        },
        children = all_rows
    }
end

local function open_gui(player_index)
    local player = game.players[player_index]
    local force = player.force --[[@as LuaForce]]

    local old_wnd = player.gui.screen["sw-research-planner-mainwnd"]
    local location
    if (old_wnd) then
        location = old_wnd.location
        old_wnd.destroy()
    end

    local frame = glib_frame("sw-research-planner-mainwnd", "Research Planner")
    local wnd, refs = glib.add(player.gui.screen, frame)
    if (location) then
        wnd.location = location
    else
        wnd.auto_center = true
    end
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
        milestone = { technologies = {}, production = {} }
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

---@param event EventData.on_gui_confirmed
function handler.on_spm_confirmed(event)
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local item = find_tag(event.element, "item") --[[@as string]]
    local storage = get_storage(event.player_index)
    local milestone = storage.milestones[milestone_idx]
    local production = milestone.production
    production[item] = tonumber(event.element.text)
    open_gui(event.player_index)
    local wnd = game.players[event.player_index].gui.screen["sw-research-planner-mainwnd"]
    local gui_milestone = wnd.children[2].children[milestone_idx]
    for i, child in ipairs(gui_milestone.children) do
        if (child.tags["item"] == item) then
            local textbox = child.children[2]
            textbox.focus()
            textbox.select(1, 0)
        end
    end
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
