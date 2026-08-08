---@type data.ShortcutPrototype
local shortcut = {
    type = "shortcut",
    name = "sw-research-planner-shortcut",
    action = "lua",
    icon = "__sw-research-planner__/graphics/technology-white.png",
    small_icon = "__sw-research-planner__/graphics/technology-white.png",
    icon_size = 64,
    small_icon_size = 64,
}

---@type data.CustomInputPrototype
local custom_input = {
    type = "custom-input",
    name = "sw-research-planner-configure",
    action = "lua",
    key_sequence = "CONTROL + SHIFT + T"
}

data:extend({ shortcut, custom_input })
