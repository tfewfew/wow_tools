WoWTools.prr.RegisterSource(function(...)
-- item_row.lua -- one reagent found by the search of the item window:
--
--   [icon]  Linen Cloth                                  recipes: 12
--
-- Hover -- the item's tooltip; a click -- the item into the window (its
-- recipes), Shift+click -- its link into the open chat.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local Favorites = ns.Dataflows.Favorites
local ItemNames = ns.Dataflows.ItemNames
local RecipeIndex = ns.Dataflows.RecipeIndex
local Text = ns.Localization.Text

local ItemRow = {}
ns.Components.ItemRow = ItemRow

local LOADING_NAME = "..."
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local ROW_HIGHLIGHT_ALPHA = 0.35
local STAR_SIZE = 10

local function OpenItem(row)
    if row.itemID and row.onOpenItem then
        row.onOpenItem(row.itemID)
    end
end

-- onOpenItem(itemID) -- a click on the row or its icon.
function ItemRow.Create(parent, onOpenItem)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Config.ITEM_ROW_HEIGHT)
    row.onOpenItem = onOpenItem

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(ROW_HIGHLIGHT)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(ROW_HIGHLIGHT_ALPHA)

    row.icon = ns.UI.IconButton(row, {
        size = Config.ITEM_ROW_ICON_SIZE,
        onClick = function()
            OpenItem(row)
        end,
    })
    row.icon:SetPoint("LEFT", Config.RECIPE_ROW_PADDING, 0)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -Config.RECIPE_ROW_PADDING, 0)
    row.count:SetJustifyH("RIGHT")

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("LEFT", row.icon, "RIGHT", Config.RECIPE_ROW_GAP, 0)
    row.title:SetPoint("RIGHT", row.count, "LEFT", -Config.RECIPE_ROW_GAP, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        if ns.Utilities.InsertChatLink("item", self.itemID) then return end
        OpenItem(self)
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
        ns.Wowhead.SetHovered("item", self.itemID)
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ns.Wowhead.SetHovered(nil)
    end)

    return row
end

function ItemRow.Fill(row, itemID)
    row.itemID = itemID
    row.icon:SetItem(itemID, 1)
    ns.UI.SetFavoriteStar(row.icon, Favorites.IsFavorite(itemID), STAR_SIZE)
    row.title:SetText(ItemNames.ItemName(itemID) or LOADING_NAME)
    row.count:SetText(Text("window.reagent_recipes", RecipeIndex.ReagentRecipeCount(itemID)))
end
end)
