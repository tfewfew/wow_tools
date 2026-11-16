WoWTools.prr.RegisterSource(function(...)
-- auction_house.lua -- the auction house for the craft planner: open / closed,
-- and the answers to the searches of the price scan.

local ADDON, ns = ...

local AuctionScan = ns.Services.AuctionScan
local PlannerWindow = ns.Components.PlannerWindow

local function SetOpen(isOpen)
    AuctionScan.SetAuctionHouseOpen(isOpen)
    PlannerWindow.OnAuctionHouseChanged()
end

ns.Events.On("AUCTION_HOUSE_SHOW", function()
    SetOpen(true)
end)
ns.Events.On("AUCTION_HOUSE_CLOSED", function()
    SetOpen(false)
end)

-- the modern auction house: the browse of the whole house, the searches of one item
ns.Events.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", AuctionScan.OnBrowseUpdated)
ns.Events.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", AuctionScan.OnBrowseAdded)
ns.Events.On("COMMODITY_SEARCH_RESULTS_UPDATED", AuctionScan.OnCommodityResults)
ns.Events.On("ITEM_SEARCH_RESULTS_UPDATED", AuctionScan.OnItemResults)
-- the old one
ns.Events.On("AUCTION_ITEM_LIST_UPDATE", AuctionScan.OnLegacyList)
end)
