WoWTools.prr.RegisterSource(function(...)
-- recipe_row.lua -- one recipe in the item window:
--
--   [result icon]  [75] Handstitched Leather Boots        [pattern icon]
--                  [reagent] [reagent] [reagent]
--
-- Hover: the result icon -- the created item, a reagent -- that reagent, the
-- rest of the row -- the recipe spell. A click on an icon opens that item in
-- the window. The window's own item and the reagents the search found are
-- underlined.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local Favorites = ns.Dataflows.Favorites
local ItemNames = ns.Dataflows.ItemNames
local Text = ns.Localization.Text

local RecipeRow = {}
ns.Components.RecipeRow = RecipeRow

local LOADING_NAME = "..."
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local ROW_HIGHLIGHT_ALPHA = 0.35
local MARK_HEIGHT = 2
local REAGENT_STAR_SIZE = 10   -- the favorite star of the small icons
local MARK_COLOR = { 0.25, 1, 0.25, 1 }

-- Match Better Vendor UI's learned-recipe icon treatment.
local function UpdateKnownRecipeMarker(button, known)
    local marker = button.prrKnownRecipe
    if known then
        if not marker then
            marker = {
                gray = button:CreateTexture(nil, "OVERLAY", nil, 1),
                check = button:CreateTexture(nil, "OVERLAY", nil, 2),
            }
            marker.gray:SetAllPoints(button.icon)
            marker.gray:SetDesaturated(true)
            marker.check:SetTexture(136814)
            marker.check:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
            marker.check:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
            button.prrKnownRecipe = marker
        end
        marker.gray:SetTexture(button.icon:GetTexture())
        marker.gray:SetTexCoord(button.icon:GetTexCoord())
        marker.gray:SetVertexColor(button.icon:GetVertexColor())
        marker.gray:SetAlpha(button.icon:GetAlpha())
    end
    if marker then
        marker.gray:SetShown(known == true)
        marker.check:SetShown(known == true)
    end
end

local function OpenClickedItem(button)
    if button.itemID and button.row.onOpenItem then
        button.row.onOpenItem(button.itemID)
    end
end

local function CreateReagentButton(row)
    local button = ns.UI.IconButton(row, {
        size = Config.REAGENT_ICON_SIZE,
        onClick = OpenClickedItem,
    })
    button.row = row
    -- the window's item: a green line under the icon
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetHeight(MARK_HEIGHT)
    button.mark:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
    button.mark:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -1)
    button.mark:SetColorTexture(MARK_COLOR[1], MARK_COLOR[2], MARK_COLOR[3], MARK_COLOR[4])
    return button
end

-- onOpenItem(itemID) -- a click on an icon.
function RecipeRow.Create(parent, onOpenItem)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Config.RECIPE_ROW_HEIGHT)
    row.onOpenItem = onOpenItem

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(ROW_HIGHLIGHT)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(ROW_HIGHLIGHT_ALPHA)

    row.result = ns.UI.IconButton(row, {
        size = Config.RECIPE_ICON_SIZE,
        onClick = OpenClickedItem,
    })
    row.result.row = row
    row.result:SetPoint("TOPLEFT", Config.RECIPE_ROW_PADDING, -4)

    -- the item that teaches the recipe; a click opens it like any other icon
    row.recipeItem = ns.UI.IconButton(row, {
        size = Config.RECIPE_ITEM_ICON_SIZE,
        onClick = OpenClickedItem,
    })
    row.recipeItem.row = row
    row.recipeItem:SetPoint("TOPRIGHT", -Config.RECIPE_ROW_PADDING, -4)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.result, "TOPRIGHT", Config.RECIPE_ROW_GAP, -1)
    row.title:SetPoint("RIGHT", row.recipeItem, "LEFT", -Config.RECIPE_ROW_GAP, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.hint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.hint:SetPoint("BOTTOMLEFT", row.result, "BOTTOMRIGHT", Config.RECIPE_ROW_GAP, 2)
    row.hint:SetText(Text("tooltip.reagents_unknown"))

    row.trainers = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.trainers:SetPoint("TOPLEFT", row.result, "BOTTOMLEFT", 0, -4)
    row.trainers:SetPoint("RIGHT", row, "RIGHT", -Config.RECIPE_ROW_PADDING, 0)
    row.trainers:SetJustifyH("LEFT")
    row.trainers:SetWordWrap(false)

    row.reagentButtons = {}

    -- Shift+click -- the recipe's link into the open chat;
    -- developer mode: a right click opens the fix menu
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
        -- the recipe into the chat; Auctionator Shopping searches for items: the result
        local recipe = self.recipe
        local isForShopping = recipe.item and ns.Utilities.IsAuctionatorShoppingShown()
        if isForShopping and ns.Utilities.InsertChatLink("item", recipe.item) then return end
        if ns.Utilities.InsertChatLink("spell", recipe.spellID) then return end
        local isFixClick = mouseButton == "RightButton" and ns.db.settings.developer
        if isFixClick then
            ns.Components.RecipeFixMenu.Show(self, self.recipe)
        end
    end)

    -- the recipe itself
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.recipe.spellID)
        local levels = ns.SkillRange.Text(self.recipe)
        if levels then GameTooltip:AddLine(levels, 1, 1, 1) end
        ns.RecipeSources.AddTooltip(GameTooltip, self.recipe)
        GameTooltip:Show()
        ns.Wowhead.SetHovered("spell", self.recipe.spellID)
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ns.Wowhead.SetHovered(nil)
    end)

    return row
end

local function TitleText(recipe)
    local name = ItemNames.RecipeName(recipe) or LOADING_NAME
    if recipe.count > 1 then
        name = name .. Config.COLOR_TEXT .. " " .. Text("tooltip.created_count", recipe.count) .. "|r"
    end
    -- [learn][yellow][green][gray]; recipes found only by the scan have none
    local levels = ns.SkillRange.Text(recipe)
    if levels then
        name = levels .. " " .. name
    end
    if ns.db.settings.developer then
        name = name .. Config.COLOR_HINT .. "  #" .. recipe.spellID .. "|r"
    end
    if recipe.ignored then
        name = Config.COLOR_IGNORED .. Text("dev.ignored_mark") .. "|r " .. name
    end
    return name
end

-- itemID -- the window's item, markedItems -- a set of item ids (the reagents the
-- search found): both are marked among the reagents.
function RecipeRow.Fill(row, recipe, itemID, markedItems)
    row.recipe = recipe
    if recipe.item then
        row.result:SetItem(recipe.item, recipe.count)
    else
        row.result:SetSpell(recipe.spellID)
    end
    local known = ns.GameData.IsRecipeKnown(recipe.spellID)
    UpdateKnownRecipeMarker(row.result, known)
    ns.UI.SetFavoriteStar(row.result, Favorites.IsFavorite(recipe.item))
    row.title:SetText(TitleText(recipe))
    local trainers = ns.RecipeSources.Summary(recipe)
    row.trainers:SetText(trainers or "")
    row.trainers:SetShown(trainers ~= nil)
    if recipe.ignored then
        row:SetAlpha(Config.IGNORED_ROW_ALPHA)
    else
        row:SetAlpha(1)
    end
    if recipe.recipeItem then
        row.recipeItem:SetItem(recipe.recipeItem, 1)
        UpdateKnownRecipeMarker(row.recipeItem, known)
        ns.UI.SetFavoriteStar(row.recipeItem, Favorites.IsFavorite(recipe.recipeItem), REAGENT_STAR_SIZE)
        row.recipeItem:Show()
    else
        UpdateKnownRecipeMarker(row.recipeItem, false)
        row.recipeItem:Hide()
    end

    local reagents = recipe.reagents or {}
    row.hint:SetShown(recipe.reagents == nil)
    for i, reagent in ipairs(reagents) do
        local button = row.reagentButtons[i]
        if not button then
            button = CreateReagentButton(row)
            if i == 1 then
                button:SetPoint("BOTTOMLEFT", row.result, "BOTTOMRIGHT", Config.RECIPE_ROW_GAP, 0)
            else
                button:SetPoint("LEFT", row.reagentButtons[i - 1], "RIGHT", Config.REAGENT_ICON_GAP, 0)
            end
            row.reagentButtons[i] = button
        end
        button:SetItem(reagent[1], reagent[2])
        ns.UI.SetFavoriteStar(button, Favorites.IsFavorite(reagent[1]), REAGENT_STAR_SIZE)
        local isMarked = reagent[1] == itemID or (markedItems ~= nil and markedItems[reagent[1]] == true)
        button.mark:SetShown(isMarked)
        button:Show()
    end
    for i = #reagents + 1, #row.reagentButtons do
        row.reagentButtons[i]:Hide()
    end
end
end)
