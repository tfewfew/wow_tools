WoWTools.prr.RegisterSource(function(...)
-- recipe_index.lua -- the recipe base joined with in-game scans, and two indexes:
-- created item -> recipes, reagent -> recipes.
--
-- A recipe here: { spellID, item, profession, skill, count, reagents = { { itemID, count }, ... },
-- yellow, gray -- the skill-up range, name, recipeItem -- the item that teaches it, skillUnknown -- "???", ignored --
-- hidden from players; the last two are set by hand fixes };
-- reagents == nil -- not known yet.
-- The indexes are built on the first tooltip and dropped by Invalidate after a scan.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local RecipeIndex = {}
ns.Dataflows.RecipeIndex = RecipeIndex

local recipes = nil        -- [spell id] = recipe
local byCreatedItem = nil  -- [item id] = { recipe, ... }
local byReagent = nil      -- [item id] = { recipe, ... }
local byRecipeItem = nil   -- [item id of a pattern / plans / formula] = { recipe, ... }

-- "2318:2,2320:1" -> { { 2318, 2 }, { 2320, 1 } }
local function ParseReagentText(text)
    local reagents = {}
    for itemID, count in text:gmatch("(%d+):(%d+)") do
        table.insert(reagents, { tonumber(itemID), tonumber(count) })
    end
    return reagents
end

-- { 2318, 2, 2320, 1 } (as the scan saves) -> { { 2318, 2 }, { 2320, 1 } }
local function ParseReagentList(list)
    local reagents = {}
    for i = 1, #list - 1, 2 do
        table.insert(reagents, { list[i], list[i + 1] })
    end
    return reagents
end

local function AddToIndex(index, itemID, recipe)
    if not index[itemID] then
        index[itemID] = {}
    end
    table.insert(index[itemID], recipe)
end

local function AddRecipeToIndexes(recipe)
    if recipe.recipeItem then
        AddToIndex(byRecipeItem, recipe.recipeItem, recipe)
    end
    if recipe.item then
        AddToIndex(byCreatedItem, recipe.item, recipe)
    end
    for _, reagent in ipairs(recipe.reagents or {}) do
        AddToIndex(byReagent, reagent[1], recipe)
    end
end

local function Build()
    recipes = {}
    byCreatedItem = {}
    byReagent = {}
    byRecipeItem = {}

    for spellID, row in pairs(ns.Database.Recipes) do
        local recipe = {
            spellID = spellID,
            item = row.item,
            profession = row.profession,
            skill = row.skill,
            yellow = row.yellow,
            gray = row.gray,
            count = row.count or 1,
            name = row.name,
            recipeItem = row.recipeItem,
            recipeItemBound = row.recipeItemBound,   -- binds when picked up: not on the auction house
        }
        if row.reagents then
            recipe.reagents = ParseReagentText(row.reagents)
        end
        recipes[spellID] = recipe
    end

    -- the client's own data wins over the base
    local scanned = ns.db and ns.db.scanned or {}
    for spellID, scan in pairs(scanned) do
        local recipe = recipes[spellID]
        if not recipe then
            recipe = { spellID = spellID, count = 1 }
            recipes[spellID] = recipe
        end
        recipe.item = scan.item or recipe.item
        recipe.profession = scan.profession or recipe.profession
        recipe.count = scan.count or recipe.count
        recipe.reagents = ParseReagentList(scan.reagents or {})
    end

    -- hand fixes (services/recipe_fix_service.lua): the built ones, the in-game ones on top
    for spellID, recipe in pairs(recipes) do
        local fix = RecipeIndex.FixOf(spellID)
        if fix and fix.skillUnknown then
            recipe.skill = nil
            recipe.skillUnknown = true
        elseif fix and fix.skill then
            recipe.skill = fix.skill
        end
        if fix and fix.ignored then
            recipe.ignored = true
        end
        recipe.details = ns.Database.RecipeDetails[spellID]
        if recipe.details and not recipe.skill and not recipe.skillUnknown then
            recipe.skill = recipe.details.skill
            recipe.skillReference = recipe.details.skillReference
        end
    end

    for _, recipe in pairs(recipes) do
        if RecipeIndex.IsListed(recipe) then
            AddRecipeToIndexes(recipe)
        end
    end
end

-- An ignored recipe is not listed anywhere for players; in developer mode it
-- is, marked, so it can be brought back. Recipes of a hidden skill line
-- (Constants.HIDDEN_PROFESSIONS) are listed nowhere.
function RecipeIndex.IsListed(recipe)
    if ns.Constants.HIDDEN_PROFESSIONS[recipe.profession] then
        return false
    end
    if not recipe.ignored then
        return true
    end
    return ns.db ~= nil and ns.db.settings.developer
end

-- The fix in force for a recipe: the in-game one, else the built one; nil -- none
-- (a cleared in-game fix drops the built one too).
function RecipeIndex.FixOf(spellID)
    local saved = ns.db and ns.db.fixes and ns.db.fixes[spellID]
    local fix = saved or ns.Database.Fixes[spellID]
    if fix and fix.cleared then
        return nil
    end
    return fix
end

function RecipeIndex.Invalidate()
    recipes = nil
    byCreatedItem = nil
    byReagent = nil
    byRecipeItem = nil
end

local function EnsureBuilt()
    if not recipes then
        Build()
    end
end

-- The indexed recipe, including scans, supplements and the current hand fix.
function RecipeIndex.Get(spellID)
    EnsureBuilt()
    local recipe = recipes[spellID]
    if recipe and RecipeIndex.IsListed(recipe) then return recipe end
end

-- Recipes that create the item, or nil.
function RecipeIndex.CraftedBy(itemID)
    EnsureBuilt()
    return byCreatedItem[itemID]
end

-- Recipes the item is a reagent of, or nil.
function RecipeIndex.ReagentFor(itemID)
    EnsureBuilt()
    return byReagent[itemID]
end

-- Recipes the item teaches (it is a pattern, plans, a formula...), or nil.
function RecipeIndex.TaughtBy(itemID)
    EnsureBuilt()
    return byRecipeItem[itemID]
end

-- All recipe spell ids, and how many of them have reagents.
function RecipeIndex.All()
    EnsureBuilt()
    local spellIDs = {}
    local withReagents = 0
    for spellID, recipe in pairs(recipes) do
        table.insert(spellIDs, spellID)
        if recipe.reagents and #recipe.reagents > 0 then
            withReagents = withReagents + 1
        end
    end
    table.sort(spellIDs)
    return spellIDs, withReagents
end

-- Recipe spell ids without reagents that the scan has not read yet.
function RecipeIndex.MissingReagents()
    EnsureBuilt()
    local spellIDs = {}
    local scanned = ns.db.scanned
    for spellID, recipe in pairs(recipes) do
        local isMissing = not recipe.reagents and not scanned[spellID]
        if isMissing then
            table.insert(spellIDs, spellID)
        end
    end
    table.sort(spellIDs)
    return spellIDs
end

-- Every recipe of the base, as a list (without ignored ones, see IsListed).
function RecipeIndex.AllRecipes()
    EnsureBuilt()
    local list = {}
    for _, recipe in pairs(recipes) do
        if RecipeIndex.IsListed(recipe) then
            table.insert(list, recipe)
        end
    end
    return list
end

-- The skill lines of all listed recipes, sorted by profession name.
function RecipeIndex.Professions()
    local seen = {}
    local professions = {}
    local names = {}
    for _, recipe in ipairs(RecipeIndex.AllRecipes()) do
        local profession = recipe.profession
        if profession and not seen[profession] then
            seen[profession] = true
            table.insert(professions, profession)
            names[profession] = ns.GameData.ProfessionName(profession)
        end
    end
    table.sort(professions, function(a, b)
        return names[a] < names[b]
    end)
    return professions
end

-- Recipes whose name contains the text, any case (Cyrillic too). Names of
-- items the client has not loaded yet are requested: they match on a later call.
function RecipeIndex.FilterByName(list, text)
    local needle = ns.Utilities.Lower(text)
    local found = {}
    for _, recipe in ipairs(list) do
        local name = ns.Dataflows.ItemNames.RecipePlainName(recipe)
        local isMatch = name and ns.Utilities.Lower(name):find(needle, 1, true)
        if isMatch then
            table.insert(found, recipe)
        end
    end
    return found
end

-- { { profession = id, name = "...", recipes = { ... } }, ... } sorted by profession
-- name; recipes of a group -- named first, then by required skill, "?" and "???" last.
function RecipeIndex.GroupByProfession(recipes)
    local groups = {}
    local byProfession = {}
    for _, recipe in ipairs(recipes) do
        local profession = recipe.profession or 0
        local group = byProfession[profession]
        if not group then
            group = {
                profession = profession,
                name = ns.GameData.ProfessionName(profession),
                recipes = {},
            }
            byProfession[profession] = group
            table.insert(groups, group)
        end
        table.insert(group.recipes, recipe)
    end

    table.sort(groups, function(a, b)
        return a.name < b.name
    end)

    -- recipes whose item the client could not give a name for go to the end
    local isNamed = {}
    for _, recipe in ipairs(recipes) do
        isNamed[recipe] = ns.Dataflows.ItemNames.RecipePlainName(recipe) ~= nil
    end

    for _, group in ipairs(groups) do
        table.sort(group.recipes, function(a, b)
            if isNamed[a] ~= isNamed[b] then
                return isNamed[a]
            end
            return ns.SkillRange.IsLearnedBefore(a, b)
        end)
    end
    return groups
end
end)
