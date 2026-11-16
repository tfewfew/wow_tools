WoWTools.prr.RegisterSource(function(...)
-- item_tooltip.lua -- the lines this addon adds to an item tooltip:
--
--   Crafted by Leatherworking [75][105][125][145]
--     2 x Light Leather, 1 x Coarse Thread
--   Reagent for:
--     Leatherworking: Light Armor Kit, Handstitched Leather Boots and 9 more
--
--   Auction(PRR)[12.10 14:30]          4s 00c
--
-- Lists are cut to Config limits; with Shift held -- everything.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local GameData = ns.GameData
local ItemNames = ns.Dataflows.ItemNames
local RecipeIndex = ns.Dataflows.RecipeIndex
local Text = ns.Localization.Text

local ItemTooltip = {}
ns.Components.ItemTooltip = ItemTooltip

local LOADING_NAME = "..."
local INDENT = "  "

-- The profession with the skill levels of the recipe: [learn][yellow][green][gray].
local function ProfessionTitle(recipe)
    local title = Config.COLOR_PROFESSION .. GameData.ProfessionName(recipe.profession) .. "|r"
    local levels = ns.SkillRange.Text(recipe)
    if levels then
        title = title .. " " .. levels
    end
    return title
end

local function ReagentsText(recipe)
    if not recipe.reagents then
        return Config.COLOR_HINT .. Text("tooltip.reagents_unknown") .. "|r"
    end
    local parts = {}
    for _, reagent in ipairs(recipe.reagents) do
        local name = ItemNames.ItemName(reagent[1]) or LOADING_NAME
        table.insert(parts, Text("tooltip.reagent", reagent[2], name))
    end
    return Config.COLOR_TEXT .. table.concat(parts, ", ") .. "|r"
end

-- A pattern / plans / formula: what it teaches, with the reagents.
local function AddTeaches(tooltip, recipes)
    for _, recipe in ipairs(recipes) do
        local name = ItemNames.RecipeName(recipe) or LOADING_NAME
        tooltip:AddLine(Config.COLOR_HEADER .. Text("tooltip.teaches") .. "|r "
            .. ProfessionTitle(recipe) .. " " .. name)
        tooltip:AddLine(INDENT .. ReagentsText(recipe), 1, 1, 1, true)
    end
end

local function AddCraftedBy(tooltip, recipes, showAll)
    local shown = #recipes
    if not showAll then
        shown = math.min(shown, Config.TOOLTIP_CRAFTED_RECIPES)
    end
    for i = 1, shown do
        local recipe = recipes[i]
        local title = Config.COLOR_HEADER .. Text("tooltip.crafted_by") .. "|r "
            .. ProfessionTitle(recipe)
        if recipe.count > 1 then
            title = title .. Config.COLOR_TEXT .. " " .. Text("tooltip.created_count", recipe.count) .. "|r"
        end
        tooltip:AddLine(title)
        tooltip:AddLine(INDENT .. ReagentsText(recipe), 1, 1, 1, true)
    end
    if shown < #recipes then
        tooltip:AddLine(INDENT .. Config.COLOR_HINT .. Text("tooltip.more_shift", #recipes - shown) .. "|r")
    end
end

local function AddReagentFor(tooltip, recipes, showAll)
    tooltip:AddLine(Config.COLOR_HEADER .. Text("tooltip.reagent_for") .. "|r")
    for _, group in ipairs(RecipeIndex.GroupByProfession(recipes)) do
        local shown = #group.recipes
        if not showAll then
            shown = math.min(shown, Config.TOOLTIP_RECIPES_PER_PROFESSION)
        end

        local names = {}
        for i = 1, shown do
            table.insert(names, ItemNames.RecipeName(group.recipes[i]) or LOADING_NAME)
        end
        local line = INDENT .. Config.COLOR_PROFESSION .. group.name .. "|r"
            .. Config.COLOR_TEXT .. ": " .. table.concat(names, ", ") .. "|r"
        if shown < #group.recipes then
            line = line .. Config.COLOR_HINT .. " " .. Text("tooltip.more_shift", #group.recipes - shown) .. "|r"
        end
        tooltip:AddLine(line, 1, 1, 1, true)
    end
end

-- an empty gap at the end of the price: the price stands 2 pixels left, even
-- with the prices of the other addons (Vendor, Auction) above it -- a 2x1
-- corner of the copper coin, empty (the coin is round)
local PRICE_END_GAP = "|TInterface\\MoneyFrame\\UI-CopperIcon:1:2:0:0:16:16:0:1:0:1|t"

-- "Auction(PRR)[12.10 14:30]   4s 00c" -- the lowest buyout per item seen by
-- the planner's scan (dataflows/auction_prices.lua), with every coin down to
-- copper; nothing for an item never seen on sale.
local function AddAuctionPrice(tooltip, itemID)
    local price = ns.Dataflows.AuctionPrices.Get(itemID)
    if not price then return false end
    local seenAt = ns.Dataflows.AuctionPrices.SeenAt(itemID)
    local title = Config.COLOR_HEADER .. Text("tooltip.auction_price") .. "|r"
    if seenAt then
        title = title .. Config.COLOR_HINT .. "[" .. date(Config.PLANNER_DATE_FORMAT, seenAt) .. "]|r"
    end
    -- the right side is yellow by default: the price in white
    tooltip:AddDoubleLine(title, ns.Utilities.Money(price) .. PRICE_END_GAP, 1, 1, 1, 1, 1, 1)
    return true
end

-- The recipes of the professions turned on in the settings; nil when none is left.
local function ShownRecipes(recipes)
    if not recipes then return nil end
    local hidden = ns.db.settings.tooltipHiddenProfessions
    if not next(hidden) then return recipes end
    local shown = {}
    for _, recipe in ipairs(recipes) do
        if not hidden[recipe.profession] then
            table.insert(shown, recipe)
        end
    end
    if #shown == 0 then return nil end
    return shown
end

function ItemTooltip.Fill(tooltip, itemID)
    local settings = ns.db.settings
    if not settings.showTooltip then return end
    local hasPrice = settings.showAuctionPrice and AddAuctionPrice(tooltip, itemID)
    local craftedBy = settings.showCraftedBy and ShownRecipes(RecipeIndex.CraftedBy(itemID))
    local reagentFor = settings.showReagentFor and ShownRecipes(RecipeIndex.ReagentFor(itemID))
    local teaches = settings.showCraftedBy and ShownRecipes(RecipeIndex.TaughtBy(itemID))
    if not craftedBy and not reagentFor and not teaches then
        if hasPrice then
            tooltip:Show()
        end
        return
    end

    local showAll = IsShiftKeyDown()
    tooltip:AddLine(" ")
    if teaches then
        AddTeaches(tooltip, teaches)
    end
    if craftedBy then
        AddCraftedBy(tooltip, craftedBy, showAll)
    end
    if reagentFor then
        AddReagentFor(tooltip, reagentFor, showAll)
    end
    tooltip:Show()
end
end)
