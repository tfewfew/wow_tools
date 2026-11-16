WoWTools.prr.RegisterSource(function(...)
-- skill_range.lua -- the skill levels of a recipe in their colors, as Wowhead
-- shows them: [learn][yellow][green][gray]. The learn level is orange most of
-- the time; green is halfway between yellow and gray (as the server counts it).

local ADDON, ns = ...

local Config = ns.Config

local SkillRange = {}
ns.SkillRange = SkillRange

local UNKNOWN = "?"

local function Level(color, value)
    return color .. "[" .. value .. "]|r"
end

-- The skill to learn a recipe for sorting by it: the ones not known ([?] --
-- none in the base, [???] -- marked unknown by hand) after all the others.
function SkillRange.LearnOrder(recipe)
    if recipe.skillUnknown or not recipe.skill then
        return math.huge
    end
    return recipe.skill
end

-- Sorts by the skill to learn (LearnOrder), then by yellow, then by spell id.
function SkillRange.IsLearnedBefore(a, b)
    local skillA, skillB = SkillRange.LearnOrder(a), SkillRange.LearnOrder(b)
    if skillA ~= skillB then
        return skillA < skillB
    end
    local yellowA, yellowB = a.yellow or 0, b.yellow or 0
    if yellowA ~= yellowB then
        return yellowA < yellowB
    end
    return a.spellID < b.spellID
end

-- The colored levels of a recipe, or nil when nothing is known.
function SkillRange.Text(recipe)
    local learn = recipe.skill
    if recipe.skillUnknown then
        learn = ns.Localization.Text("dev.skill_unknown")
    end
    if not recipe.gray then
        return learn and Level(Config.COLOR_SKILL_ORANGE, learn) or nil
    end
    local green = math.floor((recipe.yellow + recipe.gray) / 2)
    return Level(Config.COLOR_SKILL_ORANGE, learn or UNKNOWN)
        .. Level(Config.COLOR_SKILL_YELLOW, recipe.yellow)
        .. Level(Config.COLOR_SKILL_GREEN, green)
        .. Level(Config.COLOR_SKILL_GRAY, recipe.gray)
end
end)
