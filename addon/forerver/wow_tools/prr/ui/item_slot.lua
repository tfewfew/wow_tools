WoWTools.prr.RegisterSource(function(...)
-- item_slot.lua -- a bag-like slot that takes an item: drag one onto it, or
-- pick one up and click the slot. The item goes back to the bag right away:
-- the slot only remembers which item it was. Right click -- clear the slot.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local EMPTY_SLOT_TEXTURE = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

-- The item id the cursor holds, or nil. The item is put back where it was taken from.
function ns.UI.TakeCursorItem()
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or not itemID then
        return nil
    end
    ClearCursor()
    return itemID
end

-- options: size, emptyTooltip -- hint over the empty slot (a text or a function giving it),
-- clearTooltip -- a line under the item's tooltip (how to clear the slot),
-- onItem(itemID) -- an item was put in, onClear() -- right click
function ns.UI.ItemSlot(parent, options)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(options.size, options.size)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local background = slot:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture(EMPTY_SLOT_TEXTURE)

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    slot:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")

    local function AcceptCursorItem()
        local itemID = ns.UI.TakeCursorItem()
        if itemID then
            options.onItem(itemID)
        end
    end

    slot:SetScript("OnReceiveDrag", AcceptCursorItem)
    slot:SetScript("OnClick", function(self, mouseButton)
        if not GetCursorInfo() and ns.Utilities.InsertChatLink("item", self.itemID) then
            return
        end
        if mouseButton == "RightButton" then
            options.onClear()
            return
        end
        AcceptCursorItem()
    end)

    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetItemByID(self.itemID)
            if options.clearTooltip then
                GameTooltip:AddLine(options.clearTooltip, 0.5, 0.5, 0.5)
            end
            ns.Wowhead.SetHovered("item", self.itemID)
        else
            local hint = options.emptyTooltip
            if type(hint) == "function" then
                hint = hint()
            end
            GameTooltip:SetText(hint, 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ns.Wowhead.SetHovered(nil)
    end)

    -- itemID -- the item to show, nil -- empty
    function slot:SetItem(itemID)
        self.itemID = itemID
        if itemID then
            icon:SetTexture(C_Item.GetItemIconByID(itemID))
            icon:Show()
        else
            icon:Hide()
        end
    end

    slot:SetItem(nil)
    return slot
end
end)
