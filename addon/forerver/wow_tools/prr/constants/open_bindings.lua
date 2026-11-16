WoWTools.prr.RegisterSource(function(...)
-- open_bindings.lua -- the clicks on an item that open the item window with it
-- (settings.openBinding, chosen in the settings; events/bag_click.lua).
-- Modifiers must match exactly: Alt+click does not fire on Ctrl+Alt+click.

local ADDON, ns = ...
ns.Constants = ns.Constants or {}

ns.Constants.OPEN_BINDINGS = {
    { id = "NONE" },
    { id = "ALT_CLICK", alt = true, button = "LeftButton" },
    { id = "ALT_RIGHT_CLICK", alt = true, button = "RightButton" },
    { id = "SHIFT_CLICK", shift = true, button = "LeftButton" },
    { id = "SHIFT_RIGHT_CLICK", shift = true, button = "RightButton" },
    { id = "CTRL_CLICK", ctrl = true, button = "LeftButton" },
    { id = "CTRL_RIGHT_CLICK", ctrl = true, button = "RightButton" },
    { id = "CTRL_ALT_CLICK", ctrl = true, alt = true, button = "LeftButton" },
    { id = "CTRL_ALT_RIGHT_CLICK", ctrl = true, alt = true, button = "RightButton" },
}

ns.Constants.OPEN_BINDINGS_BY_ID = {}
for _, binding in ipairs(ns.Constants.OPEN_BINDINGS) do
    ns.Constants.OPEN_BINDINGS_BY_ID[binding.id] = binding
end
end)
