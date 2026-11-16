WoWTools.prr.RegisterSource(function(...)
-- auction_scan_service.lua -- reads the lowest buyout of a list of items from
-- the open auction house and keeps it in AuctionPrices.
--
-- Two ways, the fast one first:
--   browse -- the way of Auctionator: one empty browse query lists the whole
--     auction house, AUCTION_HOUSE_BROWSE_RESULTS_ADDED brings it in batches
--     with the lowest price of every item; RequestMoreBrowseResults asks for
--     the next batch until HasFullBrowseResults. Every item seen is kept (the
--     tooltips show them all); an item of the list missing from the auction
--     house is kept as none on sale. Dozens of requests instead of one per item.
--   items -- one search per item: COMMODITY_SEARCH_RESULTS_UPDATED (stackable
--     goods, sorted by unit price) or ITEM_SEARCH_RESULTS_UPDATED. The next
--     search waits for the answer and for the throttle of the server; with no
--     answer in AUCTION_SEARCH_TIMEOUT_SECONDS the item is skipped, its old
--     price stays. For short lists (Scan missing) and when browse is silent.
-- A client with the old auction house uses QueryAuctionItems by name instead.
-- events/auction_house.lua passes the events, events/ticker.lua calls Step.

local ADDON, ns = ...
ns.Services = ns.Services or {}

local AuctionPrices = ns.Dataflows.AuctionPrices
local Config = ns.Config

local AuctionScan = {}
ns.Services.AuctionScan = AuctionScan

local PRICE_SORT_ORDER = 0   -- Enum.AuctionHouseSortOrder.Price
local LEGACY_LIST = "list"
local BROWSE_QUERY = { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} }

local isAuctionHouseOpen = false
local mode = nil         -- "browse" / "items" while a scan runs, nil -- none
local total = 0
local done = 0
local found = 0
local currentItemID = nil   -- the item looked up (or found) last, for the progress bar
local sentAt = 0
local onProgress = nil   -- onProgress(done, total, found, isFinished)

-- items mode
local queue = nil        -- item ids still to look up
local waitingItemID = nil

-- browse mode
local wanted = nil       -- [item id] = true: the items of the list
local lowest = nil       -- [item id] = the lowest price per item seen in this scan
local isBrowseWaiting = false   -- a request is out, its batch not here yet
local isBrowseSent = false      -- the first query went out
local listed = nil       -- [item id] = true: the items of the auction house read so far
local listedCount = 0

local function HasModernApi()
    return C_AuctionHouse ~= nil and C_AuctionHouse.SendSearchQuery ~= nil
        and C_AuctionHouse.MakeItemKey ~= nil
end

local function HasBrowseApi()
    return C_AuctionHouse ~= nil and C_AuctionHouse.SendBrowseQuery ~= nil
        and C_AuctionHouse.RequestMoreBrowseResults ~= nil
        and C_AuctionHouse.HasFullBrowseResults ~= nil
end

local function HasLegacyApi()
    return QueryAuctionItems ~= nil and GetAuctionItemInfo ~= nil
end

function AuctionScan.IsAvailable()
    return HasModernApi() or HasLegacyApi()
end

function AuctionScan.SetAuctionHouseOpen(isOpen)
    isAuctionHouseOpen = isOpen
    if not isOpen then
        AuctionScan.Stop()
    end
end

function AuctionScan.IsAuctionHouseOpen()
    return isAuctionHouseOpen
end

function AuctionScan.IsRunning()
    return mode ~= nil
end

-- The item looked up now (or last), nil before the first one.
function AuctionScan.CurrentItem()
    return currentItemID
end

local function Report(isFinished)
    if onProgress then
        onProgress(done, total, found, isFinished)
    end
end

-- The scan is over (done or stopped). The state is cleared before the report:
-- the window asks IsRunning while it redraws its buttons.
local function Finish()
    if not mode then return end
    mode = nil
    queue = nil
    waitingItemID = nil
    wanted = nil
    lowest = nil
    listed = nil
    isBrowseWaiting = false
    Report(true)
end

local function StartItems(itemIDs)
    mode = "items"
    queue = {}
    for _, itemID in ipairs(itemIDs) do
        table.insert(queue, itemID)
    end
    waitingItemID = nil
end

local function StartBrowse(itemIDs)
    mode = "browse"
    wanted = {}
    for _, itemID in ipairs(itemIDs) do
        wanted[itemID] = true
    end
    lowest = {}
    isBrowseWaiting = false
    isBrowseSent = false
    listed = {}
    listedCount = 0
end

-- itemIDs -- the items to look up; progress(done, total, found, isFinished).
function AuctionScan.Start(itemIDs, progress)
    if not (isAuctionHouseOpen and AuctionScan.IsAvailable()) then return false end
    total = #itemIDs
    done = 0
    found = 0
    currentItemID = nil
    onProgress = progress
    if HasBrowseApi() and total >= Config.AUCTION_BROWSE_MIN_ITEMS then
        StartBrowse(itemIDs)
    else
        StartItems(itemIDs)
    end
    Report(false)
    if total == 0 then
        Finish()
    end
    return true
end

function AuctionScan.Stop()
    Finish()
end

local function IsReadyToSend()
    if HasModernApi() then
        local isThrottleKnown = C_AuctionHouse.IsThrottledMessageSystemReady ~= nil
        return not isThrottleKnown or C_AuctionHouse.IsThrottledMessageSystemReady()
    end
    return CanSendAuctionQuery == nil or CanSendAuctionQuery()
end

-- browse ---------------------------------------------------------------------

-- Browse is silent (the client does not answer it): the items of the list
-- not seen yet are looked up one by one.
local function FallBackToItems()
    local rest = {}
    for itemID in pairs(wanted) do
        if not lowest[itemID] then
            table.insert(rest, itemID)
        end
    end
    table.sort(rest)
    wanted = nil
    lowest = nil
    listed = nil
    isBrowseWaiting = false
    -- the found ones are done; the rest count on from there
    StartItems(rest)
    Report(false)
    if #rest == 0 then
        Finish()
    end
end

local function StepBrowse()
    if isBrowseWaiting then
        if GetTime() - sentAt > Config.AUCTION_SEARCH_TIMEOUT_SECONDS then
            FallBackToItems()
        end
        return
    end
    if not IsReadyToSend() then return end
    if isBrowseSent then
        C_AuctionHouse.RequestMoreBrowseResults()
    else
        C_AuctionHouse.SendBrowseQuery(BROWSE_QUERY)
        isBrowseSent = true
    end
    isBrowseWaiting = true
    sentAt = GetTime()
end

-- The whole auction house is listed: the items of the list not on it have
-- none on sale.
local function FinishBrowse()
    for itemID in pairs(wanted) do
        if not lowest[itemID] then
            AuctionPrices.Set(itemID, nil)
        end
    end
    done = total
    ns.db.auctionBrowseSize = listedCount
    Finish()
end

-- How far the browse is: the items of the auction house read so far and how
-- many the last full browse had (0 -- none yet); nil -- no browse going.
-- The items of the list with none on sale are known only at the end, so the
-- bar follows the auction house, not the list.
function AuctionScan.BrowseProgress()
    if mode ~= "browse" then return nil end
    return listedCount, ns.db.auctionBrowseSize or 0
end

-- A batch of browse results (AuctionBrowseResultInfo): itemKey, minPrice --
-- per unit for stackable goods, totalQuantity.
local function AddBrowseResults(results)
    if mode ~= "browse" or not isBrowseWaiting then return end
    isBrowseWaiting = false
    for _, info in ipairs(results or {}) do
        local itemKey = info.itemKey
        local itemID = itemKey and itemKey.itemID
        local isPet = itemKey and (itemKey.battlePetSpeciesID or 0) > 0
        local price = info.minPrice
        local isOffer = itemID and not isPet and price and price > 0 and (info.totalQuantity or 0) > 0
        if itemID and not listed[itemID] then
            listed[itemID] = true
            listedCount = listedCount + 1
        end
        if isOffer and (not lowest[itemID] or price < lowest[itemID]) then
            if wanted[itemID] then
                if not lowest[itemID] then
                    done = done + 1
                    found = found + 1
                end
                currentItemID = itemID
            end
            lowest[itemID] = price
            AuctionPrices.Set(itemID, price)
        end
    end
    if C_AuctionHouse.HasFullBrowseResults() then
        FinishBrowse()
        return
    end
    Report(false)
end

-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED: all the results so far (the first batch).
function AuctionScan.OnBrowseUpdated()
    if mode ~= "browse" then return end
    AddBrowseResults(C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults() or {})
end

-- AUCTION_HOUSE_BROWSE_RESULTS_ADDED: the next batch.
function AuctionScan.OnBrowseAdded(results)
    AddBrowseResults(results)
end

-- items ----------------------------------------------------------------------

-- The answer for the item being looked up: price -- the lowest buyout per item,
-- nil -- none on sale.
local function Answer(price)
    if price then
        found = found + 1
    end
    AuctionPrices.Set(waitingItemID, price)
    waitingItemID = nil
    done = done + 1
    Report(false)
    if #queue == 0 then
        Finish()
    end
end

local function Send(itemID)
    if HasModernApi() then
        local itemKey = C_AuctionHouse.MakeItemKey(itemID)
        local sorts = { { sortOrder = PRICE_SORT_ORDER, reverseSort = false } }
        C_AuctionHouse.SendSearchQuery(itemKey, sorts, false)
        return true
    end
    -- the old auction house searches by name: an item without a name is skipped
    local name = ns.Dataflows.ItemNames.ItemName(itemID)
    if not name then return false end
    QueryAuctionItems(name, nil, nil, 0, false, nil, false, true)
    return true
end

local function StepItems()
    if waitingItemID then
        local isSilent = GetTime() - sentAt > Config.AUCTION_SEARCH_TIMEOUT_SECONDS
        if isSilent then
            waitingItemID = nil
            done = done + 1
            Report(false)
            if #queue == 0 then
                Finish()
            end
        end
        return
    end
    if #queue == 0 or not IsReadyToSend() then return end
    local itemID = table.remove(queue, 1)
    currentItemID = itemID
    if Send(itemID) then
        waitingItemID = itemID
        sentAt = GetTime()
        Report(false)   -- the progress bar shows the item looked up
        return
    end
    done = done + 1
    Report(false)
    if #queue == 0 then
        Finish()
    end
end

-- One tick: give up on a silent request, send the next one when the server lets.
function AuctionScan.Step()
    if mode == "browse" then
        StepBrowse()
    elseif mode == "items" then
        StepItems()
    end
end

-- COMMODITY_SEARCH_RESULTS_UPDATED: the first result is the cheapest per unit.
function AuctionScan.OnCommodityResults(itemID)
    if not waitingItemID or itemID ~= waitingItemID then return end
    local count = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    local info = count > 0 and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    Answer(info and info.unitPrice or nil)
end

-- ITEM_SEARCH_RESULTS_UPDATED: the lowest buyout among the results.
function AuctionScan.OnItemResults(itemKey)
    local itemID = type(itemKey) == "table" and itemKey.itemID
    if not waitingItemID or itemID ~= waitingItemID then return end
    local best = nil
    local count = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
    for i = 1, count do
        local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        local buyout = info and info.buyoutAmount
        if buyout and buyout > 0 and (not best or buyout < best) then
            best = buyout
        end
    end
    Answer(best)
end

-- AUCTION_ITEM_LIST_UPDATE of the old auction house: the lowest buyout per
-- item among the stacks of the item on the page.
function AuctionScan.OnLegacyList()
    if not waitingItemID or HasModernApi() then return end
    local best = nil
    local count = GetNumAuctionItems(LEGACY_LIST) or 0
    for i = 1, count do
        local _, _, stackSize, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo(LEGACY_LIST, i)
        local isOffer = itemID == waitingItemID and buyout and buyout > 0 and stackSize and stackSize > 0
        if isOffer then
            local unitPrice = math.floor(buyout / stackSize)
            if not best or unitPrice < best then
                best = unitPrice
            end
        end
    end
    Answer(best)
end
end)
