WoWTools.prr.RegisterSource(function(...)
-- gathering.lua -- the casts of skinning, mining and herbalism and the loot
-- they open: services/gather_recorder.lua counts it.

local ADDON, ns = ...

local GatherRecorder = ns.Services.GatherRecorder

ns.Events.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if not ns.db or unit ~= "player" then return end
    GatherRecorder.OnCast(spellID)
end)

-- LOOT_READY comes first (before auto loot takes the items), LOOT_OPENED after it:
-- the loot window is counted at whichever comes, once
local function OnLoot()
    if not ns.db then return end
    GatherRecorder.OnLootOpened()
end
ns.Events.On("LOOT_READY", OnLoot)
ns.Events.On("LOOT_OPENED", OnLoot)

ns.Events.On("LOOT_CLOSED", function()
    GatherRecorder.OnLootClosed()
end)
end)
