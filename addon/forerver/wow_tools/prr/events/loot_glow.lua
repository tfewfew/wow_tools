WoWTools.prr.RegisterSource(function(...)
-- loot_glow.lua -- rows of the loot window getting their item: mark the
-- favorite ones (components/loot_glow.lua).
--
-- * the list of this client: every row it initializes (rows are reused);
-- * the old window: LootFrame_Update;
-- * and once more after the loot opened or changed, when the rows are drawn.

local ADDON, ns = ...

local LootGlow = ns.Components.LootGlow

local function RefreshSoon()
    C_Timer.After(0, LootGlow.RefreshAll)
end

ns.Events.On("PLAYER_LOGIN", function()
    local scrollBox = LootFrame and rawget(LootFrame, "ScrollBox")
    if scrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row)
            LootGlow.Decorate(row)
        end, LootGlow, false)
    end
    if LootFrame_Update then
        hooksecurefunc("LootFrame_Update", LootGlow.RefreshAll)
    end
end)

ns.Events.On("LOOT_OPENED", RefreshSoon)
ns.Events.On("LOOT_SLOT_CHANGED", RefreshSoon)
ns.Events.On("LOOT_SLOT_CLEARED", RefreshSoon)
end)
