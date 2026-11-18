local hover = {}
WoWTools.chatItemHover = hover

local active

local function IsReadableString(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "string"
end

function hover.IsEnabled()
    return type(wowDetectorDB) == "table" and wowDetectorDB.chatItemHover == true
end

local function ClearHover(owner)
    if not active or active.owner ~= owner then return end
    local shown = active.shown
    active = nil
    if shown and not GameTooltip:IsForbidden() and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function HasLine(label, alternate)
    for index = 1, GameTooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. index]
        local value = line and line:GetText()
        if IsReadableString(value) and (value:find(label, 1, true) or alternate and value:find(alternate, 1, true)) then
            return true
        end
    end
    return false
end

local function AddDetails(link, itemID)
    local name, _, _, _, _, _, _, stackSize, equipSlot, _, sellPrice = C_Item.GetItemInfo(link)
    if not HasLine("物品ID", "物品 ID") and not HasLine("Item:") then
        GameTooltip:AddDoubleLine("物品 ID", tostring(itemID))
    end
    if not name then return end
    if equipSlot and equipSlot ~= "" then
        local itemLevel = C_Item.GetDetailedItemLevelInfo(link)
        local levelLabel = (ITEM_LEVEL or "物品等级"):match("^([^%%]+)")
        levelLabel = levelLabel and levelLabel:match("^%s*(.-)%s*$")
        if itemLevel and levelLabel and levelLabel ~= "" and not HasLine(levelLabel) then
            GameTooltip:AddDoubleLine(levelLabel, tostring(itemLevel))
        end
    end
    if stackSize and stackSize > 1 and not HasLine("堆叠", "叠加") then
        GameTooltip:AddDoubleLine("堆叠上限", tostring(stackSize))
    end
    if sellPrice and sellPrice > 0 and not HasLine(SELL_PRICE, "卖店") then
        GameTooltip:AddDoubleLine(SELL_PRICE, C_CurrencyInfo.GetCoinTextureString(sellPrice))
    end
end

local function ShowHover(hovered)
    if active ~= hovered or not hovered.owner:IsVisible() or GameTooltip:IsForbidden() then return end
    GameTooltip:SetOwner(hovered.owner, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:SetHyperlink(hovered.link)
    hovered.shown = true
    AddDetails(hovered.link, hovered.itemID)
    if IsModifiedClick("COMPAREITEMS") or GetCVarBool("alwaysCompareItems") then
        GameTooltip_ShowCompareItem(GameTooltip)
    end
    GameTooltip:Show()
end

local function OnEnter(_, owner, link)
    if not hover.IsEnabled() or not IsReadableString(link) then return end
    local itemID = tonumber(link:match("^item:(%d+):") or link:match("^item:(%d+)$"))
    if not itemID or itemID == 0 then return end
    local hovered = { owner = owner, link = link, itemID = itemID }
    active = hovered
    C_Timer.After(0, function() ShowHover(hovered) end)
end

function hover.SetEnabled(enabled)
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    wowDetectorDB.chatItemHover = enabled == true
    if not enabled and active then ClearHover(active.owner) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(self, event, itemID, success)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent(event)
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", OnEnter, hover)
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function(_, owner) ClearHover(owner) end, hover)
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", function(_, owner) ClearHover(owner) end, hover)
    elseif success and active and active.shown and itemID == active.itemID then
        local hovered = active
        C_Timer.After(0, function()
            if active == hovered and not GameTooltip:IsForbidden() and GameTooltip:IsOwned(hovered.owner) then
                ShowHover(hovered)
            end
        end)
    end
end)
