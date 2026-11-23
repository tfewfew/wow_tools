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

local function AddVendorPrice(request, mayWait)
    local tooltip = GameTooltip
    if request ~= pending or tooltip:IsForbidden() or not tooltip:IsShown() or not tooltip:IsOwned(request.owner) then return end

    local price = select(11, C_Item.GetItemInfo(request.item))
    if price == nil and mayWait then
        local itemID = C_Item.GetItemInfoInstant(request.item)
        if itemID and itemID > 0 then
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() AddVendorPrice(request) end)
        end
    elseif price and price > 0 and not HasVendorPrice(tooltip) then
        tooltip:AddDoubleLine(SELL_PRICE, C_CurrencyInfo.GetCoinTextureString(price))
        tooltip:Show()
    end
end

local function QueueVendorPrice(owner, item)
    local request = { owner = owner, item = item }
    pending = request
    -- Wait for the native tooltip and other addons to finish adding price lines.
    C_Timer.After(0, function() AddVendorPrice(request, true) end)
end

GameTooltip:HookScript("OnTooltipCleared", function() pending = nil end)
GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    if tooltip:IsForbidden() or not (AuctionFrame or AuctionHouseFrame) then return end
    local owner = tooltip:GetOwner()
    if not IsAuctionOwner(owner) then return end
    local _, link = tooltip:GetItem()
    if link then QueueVendorPrice(owner, link) end
end)

if GameTooltip.SetItemKey then
    hooksecurefunc(GameTooltip, "SetItemKey", function(tooltip, itemID)
        if tooltip:IsForbidden() or not AuctionHouseFrame or itemID <= 0 then return end
        local owner = tooltip:GetOwner()
        if not IsAuctionOwner(owner) then return end
        local _, link = tooltip:GetItem()
        QueueVendorPrice(owner, link or itemID)
    end)
end
