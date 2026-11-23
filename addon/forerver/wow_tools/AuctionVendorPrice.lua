local pending

local function IsAuctionOwner(owner)
    while owner do
        if owner == AuctionHouseFrame then return true end
        owner = owner:GetParent()
    end
    return false
end

local function HasVendorPrice(tooltip)
    for index = 1, tooltip:NumLines() do
        local line = tooltip:GetLeftLine(index)
        local value = line and line:GetText()
        if not (issecretvalue and issecretvalue(value)) and type(value) == "string"
            and (value:find(SELL_PRICE, 1, true) or value:find("卖店", 1, true) or value:find("賣店", 1, true)) then
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
        Item:CreateFromItemID(request.itemID):ContinueOnItemLoad(function() AddVendorPrice(request) end)
    elseif price and price > 0 and not HasVendorPrice(tooltip) then
        tooltip:AddDoubleLine(SELL_PRICE, C_CurrencyInfo.GetCoinTextureString(price))
        tooltip:Show()
    end
end

GameTooltip:HookScript("OnTooltipCleared", function() pending = nil end)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() or not AuctionHouseFrame then return end
    local owner = tooltip:GetOwner()
    if not IsAuctionOwner(owner) or data ~= tooltip:GetPrimaryTooltipData() then return end

    local itemID = data.id
    if (issecretvalue and issecretvalue(itemID)) or type(itemID) ~= "number" or itemID <= 0 then return end
    local link = data.hyperlink
    if issecretvalue and issecretvalue(link) then link = nil end
    local request = { owner = owner, item = link or itemID, itemID = itemID }
    pending = request
    -- Wait for the native tooltip and other addons to finish adding price lines.
    C_Timer.After(0, function() AddVendorPrice(request, true) end)
end)
