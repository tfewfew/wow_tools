WoWTools.prr.RegisterSource(function(...)
-- icon_button.lua -- an item or spell icon like the game's item buttons: a
-- quality border, a count in the corner and the item's (or spell's) tooltip
-- on hover, Shift+click -- its link into the open chat; while hovered it is the target of Ctrl+C (utilities/wowhead.lua).

local ADDON, ns = ...
ns.UI = ns.UI or {}

-- the square quality frame of bag slots (SetItemButtonQuality in
-- Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua), tinted by quality
local QUALITY_BORDER_TEXTURE = "Interface\\Common\\WhiteIconFrame"
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"
local QUESTION_MARK_ICON = 134400
local COUNT_OFFSET = -2
local LOWEST_COLORED_QUALITY = 2   -- uncommon and better get a colored border, like in bags

-- options: size, onClick(button, mouseButton) -- button.itemID / button.spellID tell what it shows
function ns.UI.IconButton(parent, options)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(options.size, options.size)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetAllPoints()
    button.border:SetTexture(QUALITY_BORDER_TEXTURE)
    button.border:Hide()

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", COUNT_OFFSET, -COUNT_OFFSET)
    button.count:SetJustifyH("RIGHT")

    button:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetItemByID(self.itemID)
            ns.Wowhead.SetHovered("item", self.itemID)
        elseif self.spellID then
            GameTooltip:SetSpellByID(self.spellID)
            ns.Wowhead.SetHovered("spell", self.spellID)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ns.Wowhead.SetHovered(nil)
    end)
    -- Shift+click with the chat open -- the link into the chat, else onClick
    button:SetScript("OnClick", function(self, mouseButton)
        local isLinked = ns.Utilities.InsertChatLink("item", self.itemID)
            or (not self.itemID and ns.Utilities.InsertChatLink("spell", self.spellID))
        if not isLinked and options.onClick then
            options.onClick(self, mouseButton)
        end
    end)

    local function SetCount(count)
        if count and count > 1 then
            button.count:SetText(count)
            button.count:Show()
        else
            button.count:Hide()
        end
    end

    -- An item with a count in the corner (1 -- no number).
    function button:SetItem(itemID, count)
        self.itemID = itemID
        self.spellID = nil
        self.icon:SetTexture(C_Item.GetItemIconByID(itemID) or QUESTION_MARK_ICON)
        SetCount(count)

        local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        local isColored = color and quality >= LOWEST_COLORED_QUALITY
        if isColored then
            self.border:SetVertexColor(color.r, color.g, color.b)
            self.border:Show()
        else
            self.border:Hide()
        end
    end

    -- A spell (a recipe that creates no item, enchants).
    function button:SetSpell(spellID)
        self.itemID = nil
        self.spellID = spellID
        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
        self.icon:SetTexture(texture or QUESTION_MARK_ICON)
        SetCount(nil)
        self.border:Hide()
    end

    return button
end
end)
