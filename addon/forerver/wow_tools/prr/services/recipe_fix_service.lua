WoWTools.prr.RegisterSource(function(...)
-- recipe_fix_service.lua -- hand fixes of the recipe base, made in the game in
-- developer mode (/prr dev, right click on a recipe row). They are saved in
-- ns.db.fixes and, by scripts/build_database.py, merged into data/fixes.json and
-- built into database/fixes.lua; the in-game ones come on top of the built ones
-- (dataflows/recipe_index.lua, FixOf).
--
-- A fix: skill = 190 -- the required skill, or skillUnknown = true -- "???",
-- the skill is not known; ignored = true -- the recipe is hidden from players;
-- { cleared = true } -- the fix is dropped (a built one too).

local ADDON, ns = ...
ns.Services = ns.Services or {}

local RecipeFix = {}
ns.Services.RecipeFix = RecipeFix

local function Save(spellID, fix)
    ns.db.fixes[spellID] = fix
    ns.Dataflows.RecipeIndex.Invalidate()
end

-- The fix in force with its fields copied, to change one of them.
local function CurrentFix(spellID)
    local fix = {}
    for field, value in pairs(ns.Dataflows.RecipeIndex.FixOf(spellID) or {}) do
        fix[field] = value
    end
    return fix
end

function RecipeFix.SetSkill(spellID, skill)
    local fix = CurrentFix(spellID)
    fix.skill = skill
    fix.skillUnknown = nil
    Save(spellID, fix)
end

function RecipeFix.SetSkillUnknown(spellID)
    local fix = CurrentFix(spellID)
    fix.skill = nil
    fix.skillUnknown = true
    Save(spellID, fix)
end

-- isIgnored -- hide the recipe from players (true) or bring it back (false).
function RecipeFix.SetIgnored(spellID, isIgnored)
    local fix = CurrentFix(spellID)
    if isIgnored then
        fix.ignored = true
    else
        fix.ignored = nil
    end
    -- nothing left: no fix at all
    if next(fix) == nil then
        fix.cleared = true
    end
    Save(spellID, fix)
end

-- Back to the base without a fix (a built one is dropped as well).
function RecipeFix.Clear(spellID)
    Save(spellID, { cleared = true })
end
end)
