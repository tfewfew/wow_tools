local addon = WoWTools.prr
local cachedItems, cachedRevision = {}, nil

-- Reuse the existing index, including scanned recipes and user corrections.
function addon.GetItemRecipes(itemID)
    if type(issecretvalue) == "function" and issecretvalue(itemID) then return nil end
    if not addon.ready or type(itemID) ~= "number" or itemID <= 0
        or itemID == math.huge or itemID ~= math.floor(itemID) then return nil end
    local index = addon.Dataflows.RecipeIndex
    if cachedRevision ~= index.revision then
        cachedItems, cachedRevision = {}, index.revision
    end
    if cachedItems[itemID] then return cachedItems[itemID] end
    local entries = {}
    local function AddRecipes(recipes, kind)
        local seen = {}
        for _, recipe in ipairs(recipes or {}) do
            if not seen[recipe.spellID] then
                seen[recipe.spellID] = true
                local quantity = kind == "crafted" and recipe.count or nil
                if kind == "reagent" then
                    quantity = 0
                    for _, reagent in ipairs(recipe.reagents or {}) do
                        if reagent[1] == itemID then quantity = quantity + reagent[2] end
                    end
                end
                entries[#entries + 1] = { recipe = recipe, kind = kind, quantity = quantity }
            end
        end
    end
    AddRecipes(index.ReagentFor(itemID), "reagent")
    AddRecipes(index.CraftedBy(itemID), "crafted")
    AddRecipes(index.TaughtBy(itemID), "taught")
    table.sort(entries, function(left, right)
        if left.kind ~= right.kind then return left.kind < right.kind end
        local leftProfession, rightProfession = left.recipe.profession or 0, right.recipe.profession or 0
        if leftProfession ~= rightProfession then return leftProfession < rightProfession end
        return left.recipe.spellID < right.recipe.spellID
    end)
    cachedItems[itemID] = entries
    return entries
end
