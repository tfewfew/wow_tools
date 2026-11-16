WoWTools.prr.RegisterSource(function(...)
-- game_data.lua -- names from the client: recipe spells, professions.
-- Item names -- dataflows/item_names.lua (they are saved between sessions).

local ADDON, ns = ...

local GameData = {}
ns.GameData = GameData

function GameData.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    return (GetSpellInfo(spellID))
end

-- The player's skill in a profession by its skill line id and its cap
-- (skill, max skill), nil -- not learned
-- (or the client does not tell). The professions of the spellbook first
-- (GetProfessions: the two main ones, fishing, cooking, first aid), the
-- skill list of the character pane by name else.
function GameData.ProfessionSkill(skillLineID)
    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
        local indexes = ok and { p1, p2, p3, p4, p5, p6 } or {}
        for i = 1, 6 do
            if indexes[i] then
                local _, _, rank, maxRank, _, _, line = GetProfessionInfo(indexes[i])
                if line == skillLineID then
                    return rank, maxRank
                end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local name = GameData.ProfessionName(skillLineID)
        for i = 1, GetNumSkillLines() do
            local lineName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and lineName == name then
                return rank, maxRank
            end
        end
    end
    return nil
end

local function CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- The recipes this character has learned, seen in its profession windows:
-- PRRDB.knownRecipes[character] = { [spell id] = true }.
local function KnownRecipes()
    local key = CharacterKey()
    ns.db.knownRecipes[key] = ns.db.knownRecipes[key] or {}
    return ns.db.knownRecipes[key]
end

function GameData.RememberLearnedRecipe(spellID)
    if type(issecretvalue) == "function" and issecretvalue(spellID) then return false end
    if type(spellID) ~= "number" or spellID <= 0 or spellID == math.huge
        or spellID ~= math.floor(spellID) then return false end
    local known = KnownRecipes()
    if known[spellID] then return false end
    known[spellID] = true
    return true
end

-- The profession window of this character is open (not a linked or guild
-- one): every recipe it shows as learned is remembered.
function GameData.RememberLearnedRecipes()
    local api = C_TradeSkillUI
    if not (api and api.GetAllRecipeIDs and api.GetRecipeInfo) then return false end
    if api.IsTradeSkillReady and not api.IsTradeSkillReady() then return false end
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        if api[name] and api[name]() then return false end
    end
    local ok, recipeIDs = pcall(api.GetAllRecipeIDs)
    if not ok or type(recipeIDs) ~= "table" then return false end
    local known = KnownRecipes()
    local isChanged = false
    for _, recipeID in ipairs(recipeIDs) do
        local isRead, info = pcall(api.GetRecipeInfo, recipeID)
        local isLearned = isRead and type(info) == "table" and info.learned == true
        if isLearned and not known[recipeID] then
            known[recipeID] = true
            isChanged = true
        end
    end
    return isChanged
end

-- The character knows the recipe: a spell it has, or seen learned in its
-- profession window.
function GameData.IsRecipeKnown(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end
    return KnownRecipes()[spellID] == true
end

-- the icons of the professions, for a client that does not give them
local PROFESSION_ICONS = {
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [333] = "Interface\\Icons\\Trade_Engraving",
}
local DEFAULT_PROFESSION_ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- The icon of a profession: the one of the spellbook (GetProfessionInfo) when
-- the character has it, else PROFESSION_ICONS.
function GameData.ProfessionIcon(skillLineID)
    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
        local indexes = ok and { p1, p2, p3, p4, p5, p6 } or {}
        for i = 1, 6 do
            if indexes[i] then
                local _, icon, _, _, _, _, line = GetProfessionInfo(indexes[i])
                if line == skillLineID and icon then
                    return icon
                end
            end
        end
    end
    return PROFESSION_ICONS[skillLineID] or DEFAULT_PROFESSION_ICON
end

-- Opens the profession window of the game on a profession; false and why not.
function GameData.OpenProfession(profession)
    if InCombatLockdown and InCombatLockdown() then
        return false, ns.Localization.Text("planner.open_recipe_combat")
    end
    local api = C_TradeSkillUI
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Professions")
    end
    if api and api.OpenTradeSkill and pcall(api.OpenTradeSkill, profession) then
        return true
    end
    return false, ns.Localization.Text("planner.open_recipe_failed")
end

-- The profession window is open with the recipe in its list: the recipe is
-- selected there (its crafting page, the list scrolled to it). The game's
-- OpenRecipe does not always switch a window that is open already.
local function SelectInOpenWindow(spellID)
    local api = C_TradeSkillUI
    local frame = rawget(_G, "ProfessionsFrame")
    local page = frame and frame:IsShown() and frame.CraftingPage
    if not (page and page.SelectRecipe and api and api.GetAllRecipeIDs and api.GetRecipeInfo) then
        return false
    end
    local ok, recipeIDs = pcall(api.GetAllRecipeIDs)
    if not ok or type(recipeIDs) ~= "table" then return false end
    local isInList = false
    for _, recipeID in ipairs(recipeIDs) do
        if recipeID == spellID then
            isInList = true
            break
        end
    end
    if not isInList then return false end
    local isRead, info = pcall(api.GetRecipeInfo, spellID)
    if not (isRead and type(info) == "table") then return false end
    local skipSelectInList = true
    if not pcall(page.SelectRecipe, page, info, skipSelectInList) then return false end
    if page.RecipeList and page.RecipeList.SelectRecipe then
        local scrollToRecipe = true
        pcall(page.RecipeList.SelectRecipe, page.RecipeList, info, scrollToRecipe)
    end
    return true
end

-- Opens the recipe in the profession window of the game; false and why not.
function GameData.OpenRecipe(spellID, profession)
    if InCombatLockdown and InCombatLockdown() then
        return false, ns.Localization.Text("planner.open_recipe_combat")
    end
    local api = C_TradeSkillUI
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Professions")
    end
    if SelectInOpenWindow(spellID) then
        return true
    end
    if api and api.OpenRecipe then
        local ok, result = pcall(api.OpenRecipe, spellID)
        if ok and result ~= false then
            return true
        end
    end
    -- no recipe selection: at least the profession
    if api and api.OpenTradeSkill and profession then
        local ok = pcall(api.OpenTradeSkill, profession)
        if ok then return true end
    end
    return false, ns.Localization.Text("planner.open_recipe_failed")
end

-- Profession name in the client's language by its skill line id (164 -- Blacksmithing).
function GameData.ProfessionName(skillLineID)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, skillLineID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    local key = "professions." .. tostring(skillLineID)
    local name = ns.Localization.Text(key)
    -- a skill line lang/ does not know either
    if name == key then
        return ns.Localization.Text("professions.other", skillLineID)
    end
    return name
end
end)
