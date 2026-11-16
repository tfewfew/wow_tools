WoWTools.prr.RegisterSource(function(...)
-- auction_prices.lua -- the lowest buyout per item seen on the auction house
-- (services/auction_scan_service.lua writes, the planner reads), kept between
-- sessions in PRRDB.auctionPrices:
--   [item id] = { price = copper per item (nil -- none on sale), time = when it was seen }

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local AuctionPrices = {}
ns.Dataflows.AuctionPrices = AuctionPrices

-- Copper per item, or nil: never seen or none on sale at the last scan.
function AuctionPrices.Get(itemID)
    local entry = itemID and ns.db.auctionPrices[itemID]
    return entry and entry.price or nil
end

-- price -- the lowest buyout per item, nil -- the auction house has none.
function AuctionPrices.Set(itemID, price)
    ns.db.auctionPrices[itemID] = { price = price, time = time() }
end

-- When an item was last looked up, or nil.
function AuctionPrices.SeenAt(itemID)
    local entry = ns.db.auctionPrices[itemID]
    return entry and entry.time or nil
end
end)
