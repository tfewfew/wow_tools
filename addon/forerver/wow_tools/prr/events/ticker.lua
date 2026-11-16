WoWTools.prr.RegisterSource(function(...)
-- ticker.lua -- periodic work: the scans (recipes, auction prices) and the name
-- warm-up do a portion per tick.

local ADDON, ns = ...

local RecipeScan = ns.Services.RecipeScan
local ItemNameWarmup = ns.Services.ItemNameWarmup
local AuctionScan = ns.Services.AuctionScan

C_Timer.NewTicker(ns.Config.SCAN_TICK_SECONDS, function()
    if RecipeScan.IsRunning() then
        RecipeScan.Step()
    end
    if ItemNameWarmup.IsRunning() then
        ItemNameWarmup.Step()
    end
    if AuctionScan.IsRunning() then
        AuctionScan.Step()
    end
end)
end)
