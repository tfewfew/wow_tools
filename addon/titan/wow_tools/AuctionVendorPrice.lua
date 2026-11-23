local pending

local function IsAuctionOwner(owner)
    while owner do
        if owner == AuctionFrame or owner == AuctionHouseFrame then return true end
        owner = owner:GetParent()
    end
    return false
end

local function HasVendorPrice(tooltip)
    local locales = Auctionator and Auctionator.Locales
    local vendorLabel = locales and locales.Apply and locales.Apply("VENDOR")
    for index = 1, tooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. index]
        local value = line and line:GetText()
        if not (issecretvalue and issecretvalue(value)) and type(value) == "string"
            and (value:find(SELL_PRICE, 1, true) or value:find("卖店", 1, true) or value:find("賣店", 1, true)
                or vendorLabel and value:find(vendorLabel, 1, true) == 1) then
            return true
        end
    end
    return false
end

local function AddVendorPrice(tooltip, price)
    if price and price > 0 and not HasVendorPrice(tooltip) then
        tooltip:AddDoubleLine(SELL_PRICE, C_CurrencyInfo.GetCoinTextureString(price))
        if tooltip:IsShown() then tooltip:Show() end
    end
end

local function UpdateVendorPrice(tooltip, fallbackItemID)
    if tooltip:IsForbidden() or not (AuctionFrame or AuctionHouseFrame) then return end
    local owner = tooltip:GetOwner()
    if not IsAuctionOwner(owner) then return end
    pending = nil
    local _, link = tooltip:GetItem()
    local item = link or fallbackItemID
    if not item then return end
    local price = select(11, C_Item.GetItemInfo(item))
    if price ~= nil then
        AddVendorPrice(tooltip, price)
        return
    end

    local itemID = C_Item.GetItemInfoInstant(item)
    if not itemID or itemID <= 0 then return end
    local request = {}
    pending = request
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        if request ~= pending or tooltip:IsForbidden() or not tooltip:IsShown() or not tooltip:IsOwned(owner) then return end
        AddVendorPrice(tooltip, select(11, C_Item.GetItemInfo(item)))
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    GameTooltip:HookScript("OnTooltipCleared", function() pending = nil end)
    -- Run after native setters and hooks registered by other addons during loading.
    for _, method in ipairs({ "SetAuctionItem", "SetAuctionSellItem", "SetHyperlink", "SetBagItem" }) do
        if GameTooltip[method] then
            hooksecurefunc(GameTooltip, method, function(tooltip) UpdateVendorPrice(tooltip) end)
        end
    end
    for _, method in ipairs({ "SetItemByID", "SetItemKey" }) do
        if GameTooltip[method] then hooksecurefunc(GameTooltip, method, UpdateVendorPrice) end
    end
end)
