WoWTools.prr.RegisterSource(function(...)
-- addon_loaded.lua -- addon start.

local ADDON, ns = ...



ns.Events.On("PLAYER_LOGIN", function()
    ns.Components.MinimapButton.Setup()
    ns.Services.ItemNameWarmup.Start()
    ns.Core.ScanMissingReagents()
end)
end)
