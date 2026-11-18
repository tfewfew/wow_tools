local flavor = assert(TEST_FLAVOR)
local folder = TEST_ROOT .. "/addon/" .. flavor .. "/wow_tools/"
local itemLink = "item:123:456:0:0:0:0:789"
local owner, callbacks, lines = {}, {}, {}
local hyperlink, comparison, onEvent, scheduled

WoWTools = {}
wowDetectorDB = {chatItemHover = true}
ITEM_LEVEL = "物品等级 %d"
SELL_PRICE = "卖价"
function owner:IsVisible() return true end
function CreateFrame(kind)
    assert(kind == "Frame")
    return {
        RegisterEvent = function(_, event)
            assert(event == "PLAYER_LOGIN" or event == "GET_ITEM_INFO_RECEIVED")
        end,
        UnregisterEvent = function(_, event) assert(event == "PLAYER_LOGIN") end,
        SetScript = function(_, script, callback) assert(script == "OnEvent"); onEvent = callback end,
    }
end
EventRegistry = { RegisterCallback = function(self, event, callback, recipient)
    assert(self == EventRegistry and recipient == WoWTools.chatItemHover and not callbacks[event])
    callbacks[event] = callback
end }
C_Timer = { After = function(delay, callback)
    assert(delay == 0 and type(callback) == "function")
    scheduled = callback
end }
C_Item = {
    GetItemInfo = function(link)
        assert(link == itemLink)
        return "Item", nil, nil, 41, nil, nil, nil, 20, "INVTYPE_WEAPON", nil, 101
    end,
    GetDetailedItemLevelInfo = function(link)
        assert(link == itemLink)
        return 42
    end,
}
C_CurrencyInfo = { GetCoinTextureString = function(copper)
    assert(copper == 101)
    return "coins"
end }
local nativeLine = {GetText = function() return "原生物品属性" end}
GameTooltip = {
    IsForbidden = function() return false end,
    SetOwner = function(self, frame, anchor)
        assert(self == GameTooltip and frame == owner and anchor == "ANCHOR_CURSOR")
    end,
    ClearLines = function(self) assert(self == GameTooltip) end,
    SetHyperlink = function(self, link)
        assert(self == GameTooltip and link == itemLink)
        hyperlink = link
    end,
    NumLines = function(self) assert(self == GameTooltip); return 1 end,
    AddDoubleLine = function(self, label, value)
        assert(self == GameTooltip and type(label) == "string" and type(value) == "string")
        lines[label] = value
    end,
    Show = function(self) assert(self == GameTooltip) end,
}
function GameTooltip_ShowCompareItem(tooltip)
    assert(tooltip == GameTooltip)
    comparison = true
end
if flavor == "forerver" then
    function GameTooltip:GetLeftLine(index) assert(index == 1); return nativeLine end
    function GameTooltip:RefreshData() end
    function hooksecurefunc(target, method, callback)
        assert(target == GameTooltip and method == "RefreshData" and type(target[method]) == "function")
        assert(type(callback) == "function")
    end
    TooltipUtil = { ShouldDoItemComparison = function(tooltip) return tooltip == GameTooltip end }
else
    GameTooltipTextLeft1 = nativeLine
    function IsModifiedClick(action) assert(action == "COMPAREITEMS"); return false end
    function GetCVarBool(name) assert(name == "alwaysCompareItems"); return true end
end
assert(loadfile(folder .. "ChatItemHover.lua"))()
local hover = WoWTools.chatItemHover
onEvent(CreateFrame("Frame"), "PLAYER_LOGIN")
assert(callbacks["ChatFrame.OnHyperlinkLeave"] and callbacks["ChatFrame.OnHyperlinkClick"])
callbacks["ChatFrame.OnHyperlinkEnter"](hover, owner, itemLink, "|H" .. itemLink .. "|h[Item]|h")
assert(type(scheduled) == "function")
scheduled()
assert(hyperlink == itemLink and comparison, "Hover must pass the full link and bind native comparison")
assert(lines["物品 ID"] == "123" and lines["物品等级"] == "42" and lines["堆叠上限"] == "20"
    and lines[SELL_PRICE] == "coins", "Detail lines must bind to the native item and currency return values")
print("PASS: " .. flavor .. " chat hover registry, full item link, detail and comparison interfaces.")
