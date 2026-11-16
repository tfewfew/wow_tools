WoWTools.prr.RegisterSource(function(...)
-- window.lua -- the item window, the planner and the minimap button:
--   /prr, /prr show  -- show/hide the item window
--   /prr planner     -- show/hide the craft planner
--   /prr options     -- the addon page in the game settings
--   /prr minimap     -- show/hide the minimap button

local ADDON, ns = ...


ns.Commands.Add("show", {
    run = function()
        ns.Components.ItemWindow.Toggle()
    end,
    helpKey = "commands.show.help",
})

ns.Commands.Add("planner", {
    run = function()
        ns.Components.PlannerWindow.Toggle()
    end,
    helpKey = "commands.planner.help",
})

ns.Commands.Add("options", {
    run = function()
        ns.Components.OptionsPanel.Open()
    end,
    helpKey = "commands.options.help",
})

ns.Commands.Add("minimap", {
    run = function()
        local isHidden = not ns.db.settings.minimap.hide
        ns.Components.MinimapButton.SetHidden(isHidden)
    end,
    helpKey = "commands.minimap.help",
})
end)
