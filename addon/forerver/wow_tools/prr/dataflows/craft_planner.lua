WoWTools.prr.RegisterSource(function(...)
-- craft_planner.lua -- the numbers of the craft planner: what a recipe costs
-- in reagents at auction prices, what its result sells for, the profit.
--
--   cost   = sum of reagent count x price (missing -- reagents with no price)
--   sale   = result price x items created
--   profit = sale - the auction house cut - cost, only when every price is known

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local AuctionPrices = ns.Dataflows.AuctionPrices
local RecipeIndex = ns.Dataflows.RecipeIndex

local CraftPlanner = {}
ns.Dataflows.CraftPlanner = CraftPlanner

-- A recipe of the planner: it has reagents, its profession is not left out
-- (Config.PLANNER_HIDDEN_PROFESSIONS).
local function IsPlanned(recipe)
    local hasReagents = recipe.reagents ~= nil and #recipe.reagents > 0
    return hasReagents and recipe.profession ~= nil
        and not ns.Config.PLANNER_HIDDEN_PROFESSIONS[recipe.profession]
end

-- Skill lines with recipes that have reagents, by name (not the ones left out).
function CraftPlanner.Professions()
    local seen = {}
    local professions = {}
    for _, recipe in ipairs(RecipeIndex.AllRecipes()) do
        local isNew = IsPlanned(recipe) and not seen[recipe.profession]
        if isNew then
            seen[recipe.profession] = true
            table.insert(professions, recipe.profession)
        end
    end
    local names = {}
    for _, profession in ipairs(professions) do
        names[profession] = ns.GameData.ProfessionName(profession)
    end
    table.sort(professions, function(a, b)
        return names[a] < names[b]
    end)
    return professions
end

-- The recipes of a profession that have reagents.
function CraftPlanner.Recipes(profession)
    local list = {}
    for _, recipe in ipairs(RecipeIndex.AllRecipes()) do
        if recipe.profession == profession and IsPlanned(recipe) then
            table.insert(list, recipe)
        end
    end
    return list
end

-- The recipes with reagents of a profession, of every profession when it is nil.
local function RecipesOf(profession)
    if profession then
        return CraftPlanner.Recipes(profession)
    end
    local list = {}
    for _, recipe in ipairs(RecipeIndex.AllRecipes()) do
        if IsPlanned(recipe) then
            table.insert(list, recipe)
        end
    end
    return list
end

-- Sorts recipes by the skill to learn them (the orange level), the ones with
-- the skill not known ([?], [???]) at the end; then by yellow, by spell id.
function CraftPlanner.SortBySkill(recipes)
    table.sort(recipes, ns.SkillRange.IsLearnedBefore)
    return recipes
end

-- Every item to look up on the auction house for a profession (nil -- for
-- every profession: the scan reads the whole house anyway): the reagents
-- and the results of its recipes, each once. onlyMissing -- just the items
-- the auction house has not answered for yet (never scanned, or no answer);
-- an item seen with none on sale is not missing, a full scan looks again.
function CraftPlanner.ItemsToScan(profession, onlyMissing)
    local seen = {}
    local items = {}
    local function Add(itemID)
        local isWanted = itemID and not seen[itemID]
            and not (onlyMissing and AuctionPrices.SeenAt(itemID))
        if isWanted then
            seen[itemID] = true
            table.insert(items, itemID)
        end
    end
    for _, recipe in ipairs(RecipesOf(profession)) do
        for _, reagent in ipairs(recipe.reagents) do
            Add(reagent[1])
        end
        Add(recipe.item)
        -- the pattern / plans: the plan buys the ones not learned, and marks those not on sale
        Add(recipe.recipeItem)
    end
    table.sort(items)
    return items
end

-- When the prices of a profession (nil -- of all) were last read: the latest
-- scan of its items, or nil -- never.
function CraftPlanner.LastScanTime(profession)
    local latest = nil
    for _, itemID in ipairs(CraftPlanner.ItemsToScan(profession)) do
        local seenAt = AuctionPrices.SeenAt(itemID)
        if seenAt and (not latest or seenAt > latest) then
            latest = seenAt
        end
    end
    return latest
end

-- How complete the prices of a profession (nil -- of all) are: { total -- items to look up,
-- checked -- the auction house answered for, priced -- of them with a price }.
function CraftPlanner.Coverage(profession)
    local coverage = { total = 0, checked = 0, priced = 0 }
    for _, itemID in ipairs(CraftPlanner.ItemsToScan(profession)) do
        coverage.total = coverage.total + 1
        if AuctionPrices.SeenAt(itemID) then
            coverage.checked = coverage.checked + 1
        end
        if AuctionPrices.Get(itemID) then
            coverage.priced = coverage.priced + 1
        end
    end
    return coverage
end

-- The oldest scan among the items of a recipe (its reagents and result),
-- nil -- none of them was scanned: how fresh its numbers are.
local function OldestScan(recipe)
    local oldest = nil
    local function Check(itemID)
        local seenAt = itemID and AuctionPrices.SeenAt(itemID)
        if seenAt and (not oldest or seenAt < oldest) then
            oldest = seenAt
        end
    end
    for _, reagent in ipairs(recipe.reagents) do
        Check(reagent[1])
    end
    Check(recipe.item)
    return oldest
end

-- { recipe, cost, missing, sale, cut, profit, scannedAt } of one recipe;
-- numbers in copper, sale, cut and profit nil when not known; cut -- what the
-- auction house keeps of the sale (settings.planner.auctionCut percent).
function CraftPlanner.Evaluate(recipe)
    local cost = 0
    local missing = 0
    for _, reagent in ipairs(recipe.reagents) do
        local price = AuctionPrices.Get(reagent[1])
        if price then
            cost = cost + price * reagent[2]
        else
            missing = missing + 1
        end
    end

    local resultPrice = recipe.item and AuctionPrices.Get(recipe.item)
    local sale = resultPrice and resultPrice * recipe.count or nil
    local cut = nil
    local profit = nil
    if sale then
        cut = math.floor(sale * ns.db.settings.planner.auctionCut / 100 + 0.5)
    end
    if sale and missing == 0 then
        profit = sale - cut - cost
    end
    return {
        recipe = recipe,
        cost = cost,
        missing = missing,
        sale = sale,
        cut = cut,
        profit = profit,
        scannedAt = OldestScan(recipe),
    }
end

-- The recipes of a profession evaluated: the best profit first, then those
-- without a profit (a price missing) by their cost.
function CraftPlanner.Rows(profession)
    local rows = {}
    for _, recipe in ipairs(CraftPlanner.Recipes(profession)) do
        table.insert(rows, CraftPlanner.Evaluate(recipe))
    end
    table.sort(rows, function(a, b)
        local hasProfitA = a.profit ~= nil
        local hasProfitB = b.profit ~= nil
        if hasProfitA ~= hasProfitB then
            return hasProfitA
        end
        if hasProfitA and a.profit ~= b.profit then
            return a.profit > b.profit
        end
        if a.missing ~= b.missing then
            return a.missing < b.missing
        end
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.recipe.spellID < b.recipe.spellID
    end)
    return rows
end

-- Does the search text match the recipe: its name or the name of the item it
-- creates, any case (Cyrillic too)? "[Light Leather]" -- the whole name
-- exactly (a Shift+click on an item puts it so), any other text -- a part of
-- the name. An empty text matches everything.
function CraftPlanner.Matches(evaluation, lowerText)
    if lowerText == "" then
        return true
    end
    local Lower = ns.Utilities.Lower
    local ItemNames = ns.Dataflows.ItemNames
    local exactName = lowerText:match("^%[(.+)%]$")
    local recipe = evaluation.recipe
    local names = { ItemNames.RecipeName(recipe) }
    if recipe.item then
        table.insert(names, ItemNames.ItemName(recipe.item))
    end
    for _, name in ipairs(names) do
        local lowerName = Lower(name)
        if exactName and lowerName == exactName then
            return true
        end
        if not exactName and lowerName:find(lowerText, 1, true) then
            return true
        end
    end
    return false
end

-- The value of a column of the prices table: key -- "name", "cost", "sale",
-- "profit", "scanned"; nil -- not known (a cost with a reagent missing too).
local function SortValue(evaluation, key)
    if key == "name" then
        return ns.Utilities.Lower(ns.Dataflows.ItemNames.RecipeName(evaluation.recipe) or "")
    end
    if key == "cost" then
        return evaluation.missing == 0 and evaluation.cost or nil
    end
    if key == "scanned" then
        return evaluation.scannedAt
    end
    return evaluation[key]
end

-- Sorts the rows in place by a column; unknown values go last either way.
function CraftPlanner.Sort(rows, key, isAscending)
    local values = {}
    for _, evaluation in ipairs(rows) do
        values[evaluation] = SortValue(evaluation, key)
    end
    table.sort(rows, function(a, b)
        local valueA = values[a]
        local valueB = values[b]
        if valueA == nil or valueB == nil or valueA == valueB then
            if (valueA == nil) ~= (valueB == nil) then
                return valueA ~= nil
            end
            return a.recipe.spellID < b.recipe.spellID
        end
        if isAscending then
            return valueA < valueB
        end
        return valueA > valueB
    end)
end
end)
