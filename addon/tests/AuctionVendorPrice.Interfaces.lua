local flavor = assert(TEST_FLAVOR)
local forever = flavor == "forerver"
local folder = TEST_ROOT .. "/addon/" .. flavor .. "/wow_tools/"
local itemID, itemLink = 15237, "|Hitem:15237:0:0:0:0:0:123|h[Item]|h"
local hooks, setters, lines = {}, {}, {}
local itemCallback, onEvent, loadCallback
local owner, link, data, price, requestedItem, shown, rendered

SELL_PRICE = "售价"
AuctionHouseFrame = {}
AuctionFrame = not forever and {} or nil
local row = { GetParent = function() return AuctionFrame or AuctionHouseFrame end }
local cell = { GetParent = function() return row end }
local outside = { GetParent = function() return nil end }

C_Item = {
    GetItemInfo = function(item)
        requestedItem = item
        assert(item == itemLink or item == itemID)
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, price
    end,
    GetItemInfoInstant = function(item)
        assert(item == itemLink or item == itemID)
        return itemID
    end,
}
Item = { CreateFromItemID = function(self, id)
    assert(self == Item and id == itemID)
    return { ContinueOnItemLoad = function(_, callback) loadCallback = callback end }
end }
C_CurrencyInfo = { GetCoinTextureString = function(copper)
    assert(copper == 10101)
    return "gold, silver, copper"
end }

local function SetLine(label)
    local line = { GetText = function() return label end }
    table.insert(lines, line)
    _G["GameTooltipTextLeft" .. #lines] = line
end

GameTooltip = {
    HookScript = function(self, script, callback)
        assert(self == GameTooltip and script == "OnTooltipCleared")
        hooks[script] = callback
    end,
    IsForbidden = function() return false end,
    IsShown = function() return shown end,
    GetOwner = function() return owner end,
    IsOwned = function(_, frame) return owner == frame end,
    NumLines = function() return #lines end,
    AddDoubleLine = function(_, label, value)
        assert(label == SELL_PRICE and value == "gold, silver, copper")
        SetLine(label)
    end,
    Show = function() assert(shown); rendered = true end,
}
if forever then
    Enum = { TooltipDataType = { Item = 0 } }
    TooltipDataProcessor = { AddTooltipPostCall = function(dataType, callback)
        assert(dataType == Enum.TooltipDataType.Item)
        itemCallback = callback
    end }
    function GameTooltip:GetPrimaryTooltipData() return data end
    function GameTooltip:GetLeftLine(index) return lines[index] end
else
    function CreateFrame(kind)
        assert(kind == "Frame")
        return {
            RegisterEvent = function(_, event) assert(event == "PLAYER_LOGIN") end,
            UnregisterEvent = function(_, event) assert(event == "PLAYER_LOGIN") end,
            SetScript = function(_, script, callback) assert(script == "OnEvent"); onEvent = callback end,
        }
    end
    function GameTooltip:GetItem() return "Item", link end
    local auctionSetters = {
        SetAuctionItem = true, SetAuctionSellItem = true, SetBagItem = true,
        SetHyperlink = true, SetItemByID = true, SetItemKey = true,
    }
    for method in pairs(auctionSetters) do GameTooltip[method] = function() end end
    function hooksecurefunc(tooltip, method, callback)
        assert(tooltip == GameTooltip and auctionSetters[method])
        setters[method] = callback
    end
end

assert(loadfile(folder .. "AuctionVendorPrice.lua"))()
if not forever then onEvent(CreateFrame("Frame"), "PLAYER_LOGIN") end

local function SetItem(frame, item, copper, existingLine)
    hooks.OnTooltipCleared(GameTooltip)
    owner, link, price = frame, item, copper
    shown, rendered, loadCallback, requestedItem = not forever, nil, nil, nil
    lines = {}
    if existingLine then SetLine(existingLine) end
    if forever then
        data = { id = itemID, hyperlink = item }
        itemCallback(GameTooltip, data)
        assert(not rendered, "The native data handler owns tooltip presentation during its post-call")
        shown = true
    elseif item then
        setters.SetAuctionItem(GameTooltip, "list", 1)
    else
        setters.SetItemKey(GameTooltip, itemID)
    end
end

for _ = 1, 2 do
    SetItem(cell, itemLink, 10101)
    assert(requestedItem == itemLink and #lines == 1 and not loadCallback,
        "Cached vendor prices must appear within each native tooltip build")
end
local modernRow = { GetParent = function() return AuctionHouseFrame end }
SetItem(modernRow, nil, 10101)
assert(requestedItem == itemID and #lines == 1, "Auction item keys must supply the vendor price")

SetItem(cell, itemLink, 10101, "卖店价格:")
assert(#lines == 1 and not rendered, "Preserve an existing vendor price line")
SetItem(outside, itemLink, 10101)
assert(not requestedItem and #lines == 0, "Only auction-owned tooltips may add prices")
SetItem(cell, itemLink, 0)
assert(#lines == 0 and not loadCallback, "Items with no vendor price have no currency line")

SetItem(cell, itemLink, nil)
price = 10101
loadCallback()
assert(rendered and #lines == 1, "A completed item load must supply the vendor price")
SetItem(cell, itemLink, nil)
hooks.OnTooltipCleared(GameTooltip)
price = 10101
loadCallback()
assert(not rendered and #lines == 0, "An item load must not write to a cleared tooltip")
print("PASS: " .. flavor .. " auction tooltip, item and vendor currency interfaces.")
