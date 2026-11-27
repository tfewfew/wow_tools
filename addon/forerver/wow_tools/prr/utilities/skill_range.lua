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

-- The levels of the zones { learn, yellow, green, gray }, or nil when the
-- yellow and gray of the recipe are not known. Without the learn level,
-- the available range starts at yellow.
function SkillRange.Levels(recipe)
    if not (recipe.yellow and recipe.gray) or recipe.gray < recipe.yellow then return nil end
    local learn = recipe.skill
    if recipe.skillUnknown or not learn then
        learn = recipe.yellow
    end
    return {
        learn = learn,
        yellow = recipe.yellow,
        green = recipe.green or math.floor((recipe.yellow + recipe.gray) / 2),   -- gathering: its own
        gray = recipe.gray,
    }
end

-- Where a skill is among the zones of a recipe: { zone = "locked" | "orange" |
-- "yellow" | "green" | "gray", chance = of a skill-up, next = the next zone,
-- nextLevel = where it starts, learn }; nil without the levels. The chance of
-- yellow and green -- (gray - skill) / (gray - yellow), as the server counts it.
function SkillRange.Zone(recipe, skill)
    local levels = SkillRange.Levels(recipe)
    if not levels then return nil end
    local zone = { learn = levels.learn }
    if skill < levels.learn then
        zone.zone, zone.chance, zone.nextLevel = "locked", 0, levels.learn
        if levels.learn >= levels.gray then
            zone.next = "gray"
        elseif levels.learn >= levels.green then
            zone.next = "green"
        elseif levels.learn >= levels.yellow then
            zone.next = "yellow"
        else
            zone.next = "orange"
        end
    elseif skill < levels.yellow then
        zone.zone, zone.chance, zone.next, zone.nextLevel = "orange", 1, "yellow", levels.yellow
    elseif skill < levels.gray then
        zone.chance = (levels.gray - skill) / math.max(levels.gray - levels.yellow, 1)
        if skill < levels.green then
            zone.zone, zone.next, zone.nextLevel = "yellow", "green", levels.green
        else
            zone.zone, zone.next, zone.nextLevel = "green", "gray", levels.gray
        end
    else
        zone.zone, zone.chance = "gray", 0
    end
    return zone
end

-- The colored levels of a recipe, or nil when nothing is known.
function SkillRange.Text(recipe, trainerRank)
    local learn = trainerRank or recipe.skill
    if not trainerRank then
        if recipe.skillUnknown then
            learn = ns.Localization.Text("dev.skill_unknown")
        end
        if learn and recipe.skillReference then
            learn = learn .. "*"
        end
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
