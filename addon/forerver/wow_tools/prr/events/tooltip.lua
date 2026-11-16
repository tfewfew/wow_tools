WoWTools.prr.RegisterSource(function(...)
-- tooltip.lua -- adds the recipe lines to item tooltips.
-- Modern clients (Forever among them) build tooltips from TooltipDataProcessor;
-- older ones fire OnTooltipSetItem.

local ADDON, ns = ...

local ItemTooltip = ns.Components.ItemTooltip

-- only the main tooltips: not comparison ones and not forbidden ones
local function IsOwnTooltip(tooltip)
    if tooltip:IsForbidden() then
        return false
    end
    return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

local function OnItem(tooltip, data)
    if not ns.db then return end
    if not IsOwnTooltip(tooltip) then return end

    local itemID = data and data.id
    if not itemID then
        local _, link = tooltip:GetItem()
        itemID = link and tonumber(link:match("item:(%d+)"))
    end
    if itemID then
        ItemTooltip.Fill(tooltip, itemID)
    end
end

if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
else
    GameTooltip:HookScript("OnTooltipSetItem", OnItem)
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnItem)
end

-- Shift shows the full lists: redraw the tooltip when it is pressed or released.
ns.Events.On("MODIFIER_STATE_CHANGED", function(key)
    local isShift = key == "LSHIFT" or key == "RSHIFT"
    if not isShift then return end
    local canRefresh = GameTooltip:IsShown() and GameTooltip.RefreshData and GameTooltip:GetItem()
    if canRefresh then
        GameTooltip:RefreshData()
    end
end)
end)
