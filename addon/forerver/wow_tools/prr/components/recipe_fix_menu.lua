WoWTools.prr.RegisterSource(function(...)
-- recipe_fix_menu.lua -- the developer menu of a recipe row (right click in
-- developer mode): set the required skill, set it to "???", hide the recipe
-- from players or bring it back, drop the fix.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local ItemNames = ns.Dataflows.ItemNames
local RecipeIndex = ns.Dataflows.RecipeIndex
local RecipeFix = ns.Services.RecipeFix
local Text = ns.Localization.Text

local RecipeFixMenu = {}
ns.Components.RecipeFixMenu = RecipeFixMenu

local SKILL_MAX_LETTERS = 3
local MAXIMUM_SKILL = 450

-- The fix is saved: redraw the window with it.
local function Apply(fixAction, recipe, ...)
    fixAction(recipe.spellID, ...)
    ns.Components.ItemWindow.Refresh(true)
end

local function CurrentSkillText(recipe)
    if recipe.skillUnknown then
        return Text("dev.skill_unknown")
    end
    if recipe.skill then
        return tostring(recipe.skill)
    end
    return Text("dev.skill_none")
end

local function AskSkill(recipe)
    ns.UI.Prompt(Text("dev.skill_prompt", ItemNames.RecipeName(recipe) or recipe.spellID), function(text)
        local skill = tonumber(text)
        local isValid = skill and skill >= 1 and skill <= MAXIMUM_SKILL and skill == math.floor(skill)
        if not isValid then
            ns.Utilities.Print(Text("dev.skill_invalid", text))
            return
        end
        Apply(RecipeFix.SetSkill, recipe, skill)
    end, {
        initialText = recipe.skill and tostring(recipe.skill) or "",
        maxLetters = SKILL_MAX_LETTERS,
    })
end

function RecipeFixMenu.Show(owner, recipe)
    local title = (ItemNames.RecipeName(recipe) or "...") .. " #" .. recipe.spellID
    local hasFix = RecipeIndex.FixOf(recipe.spellID) ~= nil
    ns.UI.ShowMenu(owner, title, {
        {
            text = Text("dev.skill_current", CurrentSkillText(recipe)),
            disabled = true,
        },
        { separator = true },
        {
            text = Text("dev.set_skill"),
            onClick = function()
                AskSkill(recipe)
            end,
        },
        {
            text = Text("dev.set_unknown"),
            onClick = function()
                Apply(RecipeFix.SetSkillUnknown, recipe)
            end,
        },
        {
            text = recipe.ignored and Text("dev.unignore") or Text("dev.ignore"),
            onClick = function()
                Apply(RecipeFix.SetIgnored, recipe, not recipe.ignored)
            end,
        },
        {
            text = Text("dev.clear"),
            disabled = not hasFix,
            onClick = function()
                Apply(RecipeFix.Clear, recipe)
            end,
        },
    })
end
end)
