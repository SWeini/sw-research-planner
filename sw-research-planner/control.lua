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
    ---@field timescale_ticks integer
end

local second = 60
local minute = 60 * second
local hour = 60 * minute

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
        result = { milestones = {}, timescale_ticks = minute }
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
        icount = icount + math.ceil(count * ingredient.amount * (1 - current.progress))
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
            tooltip = #technologies > 0 and { "gui.sw-research-planner-tooltip-add-technology" } or
                { "gui.sw-research-planner-tooltip-add-milestone" }
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

---@param wnd LuaGuiElement
---@param force LuaForce
---@param data PerPlayerStorage
local function adjust_gui(wnd, force, data)
    local milestones = data.milestones
    local state = get_current_state(force)
    local tick = game.tick
    local timescale_ticks = data.timescale_ticks
    local children = wnd.children[2].children[2].children[1].children
    for _, child in ipairs(children) do
        local idx = child.tags["milestone_idx"]
        if (idx) then
            local milestone = milestones[idx]
            if (milestone) then
                local research = {} ---@type ResearchCount
                for _, name in ipairs(milestone.technologies) do
                    accumulate_research(state, research, prototypes.technology[name])
                end
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

                for _, ch in ipairs(child.children) do
                    local science_pack = ch.tags["item"]
                    if (science_pack) then
                        local amount = research[science_pack]
                        local ui_label = ch.children[1]
                        local ui_time = ch.children[3]
                        if (amount) then
                            ui_label.caption = "[item=" .. science_pack .. "] " .. format_int(amount)
                            local spm = milestone.production[science_pack] or 0
                            if (spm > 0) then
                                local t = amount / spm
                                ui_time.caption = format_time(t * timescale_ticks)
                                ui_time.style.font_color = t == time and { 1, 0, 0 } or { 1, 1, 1 }
                            else
                                ui_time.caption = ""
                            end
                        else
                            ch.destroy()
                        end
                    end

                    if (ch.name == "research_finished") then
                        tick = tick + time * timescale_ticks
                        ch.caption = { "gui.sw-research-planner-research-finished", format_time(tick) }
                    end
                end
            end
        end
    end
end

---@param player LuaPlayer
---@param force LuaForce
---@param data PerPlayerStorage
---@return GuiElemDef
local function build_gui(player, force, data)
    local milestones = data.milestones
    local state = get_current_state(force)
    ---@type GuiElemDef[]
    local all_rows = {}

    local ticks = data.timescale_ticks
    local timescale_index
    if (ticks == second) then
        timescale_index = 1
    elseif (ticks == minute) then
        timescale_index = 2
    elseif (ticks == hour) then
        timescale_index = 3
    end
    local toolbar = {
        args = {
            type = "frame",
            style = "subheader_frame",
        },
        style_mods = {
            horizontally_stretchable = true,
        },
        children = {
            {
                args = { type = "empty-widget" },
                style_mods = { horizontally_stretchable = true },
            },
            {
                args = {
                    type = "drop-down",
                    items = { { "gui.sw-research-planner-per-second" }, { "gui.sw-research-planner-per-minute" }, { "gui.sw-research-planner-per-hour" } },
                    selected_index = timescale_index,
                },
                _selection_state_changed = handler.on_timescale_changed
            },
        }
    }
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
                        _text_changed = handler.on_spm_changed
                    },
                    {
                        args = {
                            type = "label"
                        },
                        style_mods = {
                            top_margin = 4
                        }
                    }
                }
            }
        end

        rows[#rows + 1] = {
            args = {
                type = "label",
                name = "research_finished",
                caption = { "gui.sw-research-planner-research-finished", "???" }
            }
        }

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

    local screen_size = player.display_resolution.height / player.display_scale

    ---@type GuiElemDef
    return {
        args = {
            type = "frame",
            direction = "vertical",
            style = "inside_shallow_frame",
        },
        children = {
            toolbar,
            {
                args = {
                    type = "scroll-pane",
                    style = "entity_frame_scroll_pane",
                    horizontal_scroll_policy = "never",
                    vertical_scroll_policy = "auto-and-reserve-space"
                },
                style_mods = {
                    maximal_height = screen_size * 0.8,
                    padding = { 8, 12, 8, 12 }
                },
                children = {
                    {
                        args = {
                            type = "flow",
                            direction = "vertical"
                        },
                        children = all_rows
                    }
                }
            }
        }
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

    local frame = glib_frame("sw-research-planner-mainwnd", { "gui.sw-research-planner-title" })
    local wnd, refs = glib.add(player.gui.screen, frame)
    if (location) then
        wnd.location = location
    else
        wnd.auto_center = true
    end
    player.opened = wnd

    local data = get_storage(player_index)
    local gui = build_gui(player, force, data)
    glib.add(wnd, gui)
    adjust_gui(wnd, force, data)
end

---@param event EventData.on_gui_click
function handler.on_milestone_move_up(event)
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local data = get_storage(event.player_index)
    local milestones = data.milestones
    milestones[milestone_idx], milestones[milestone_idx - 1] = milestones[milestone_idx - 1], milestones[milestone_idx]
    open_gui(event.player_index)
end

---@param event EventData.on_gui_elem_changed
function handler.on_add_technology(event)
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local data = get_storage(event.player_index)
    local milestone = data.milestones[milestone_idx]
    if (not milestone) then
        milestone = { technologies = {}, production = {} }
        data.milestones[milestone_idx] = milestone
    end

    local technologies = milestone.technologies
    technologies[#technologies + 1] = event.element.elem_value --[[@as string]]
    open_gui(event.player_index)
end

---@param event EventData.on_gui_click
function handler.on_remove_technology(event)
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local technology_idx = find_tag(event.element, "technology_idx") --[[@as integer]]
    local data = get_storage(event.player_index)
    local milestone = data.milestones[milestone_idx]
    local technologies = milestone.technologies
    table.remove(technologies, technology_idx)
    if (#technologies == 0) then
        table.remove(data.milestones, milestone_idx)
    end
    open_gui(event.player_index)
end

---@param event EventData.on_gui_text_changed
function handler.on_spm_changed(event)
    if (event.text == "") then
        local element = event.element
        element.text = "0"
        element.select_all()
    end
    local milestone_idx = find_tag(event.element, "milestone_idx") --[[@as integer]]
    local item = find_tag(event.element, "item") --[[@as string]]
    local data = get_storage(event.player_index)
    local milestone = data.milestones[milestone_idx]
    local production = milestone.production
    production[item] = tonumber(event.element.text)
    local wnd = game.players[event.player_index].gui.screen["sw-research-planner-mainwnd"]
    local force = game.players[event.player_index].force --[[@as LuaForce]]
    adjust_gui(wnd, force, data)
end

---@param event EventData.on_gui_selection_state_changed
function handler.on_timescale_changed(event)
    local data = get_storage(event.player_index)
    local selected_index = event.element.selected_index
    if (selected_index == 1) then
        data.timescale_ticks = second
    elseif (selected_index == 2) then
        data.timescale_ticks = minute
    elseif (selected_index == 3) then
        data.timescale_ticks = hour
    end
    local wnd = game.players[event.player_index].gui.screen["sw-research-planner-mainwnd"]
    local force = game.players[event.player_index].force --[[@as LuaForce]]
    adjust_gui(wnd, force, data)
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

---@param player LuaPlayer
---@return LocalisedString
local function first_milestone_sensor(player)
    local data = get_storage(player.index)
    local milestones = data.milestones
    if (#milestones == 0) then
        return nil
    end

    local force = player.force --[[@as LuaForce]]
    local state = get_current_state(force)
    local tick = game.tick
    local timescale_ticks = data.timescale_ticks
    local milestone = milestones[1]
    local research = {} ---@type ResearchCount
    for _, name in ipairs(milestone.technologies) do
        accumulate_research(state, research, prototypes.technology[name])
    end
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

    if (time == 0) then
        return nil
    end

    local finished = format_time(tick + time * timescale_ticks)
    local num = #milestone.technologies
    local num_text = num == 1 and "" or " (+" .. (num - 1) .. ")"

    local result = { "" } ---@type LocalisedString[]
    for _, name in ipairs(milestone.technologies) do
        result[#result + 1] = "[technology=" .. name .. "]"
    end

    result[#result + 1] = " researched: "
    result[#result + 1] = finished
    return result
end

local function register_sensor()
    if script.active_mods["StatsGui"] and remote.call("StatsGui", "version") == 1 then
        remote.call("StatsGui", "add_sensor", "sw-research-planner", "stats_gui_sensor")
    end
end

script.on_init(function()
    register_sensor()
end)

script.on_load(function()
    register_sensor()
end)

remote.add_interface("sw-research-planner", {
    stats_gui_sensor = first_milestone_sensor
})
