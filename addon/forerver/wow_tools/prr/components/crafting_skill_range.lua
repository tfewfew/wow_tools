WoWTools.prr.RegisterSource(function(...)
-- Show PRR's colored skill thresholds when hovering native crafting recipes.
local _, ns = ...
ns.Components = ns.Components or {}

local CraftingSkillRange = {}
ns.Components.CraftingSkillRange = CraftingSkillRange
local recipeList

local function IsReadable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function GetLevels(info)
    if not IsReadable(info) or type(info) ~= "table" then return end
    local recipeID = info.recipeID
    if not IsReadable(recipeID) or type(recipeID) ~= "number" then return end
    local recipe = ns.Dataflows.RecipeIndex.Get(recipeID)
    return recipe and ns.SkillRange.Text(recipe)
end

local function OnRecipeEnter(_, row, data)
    if not ns.db or not IsReadable(data) or type(data) ~= "table" then return end
    local parent = row:GetParent()
    while parent and parent ~= recipeList do parent = parent:GetParent() end
    if not parent or GameTooltip:IsForbidden() then return end

    local info = data.recipeInfo
    local levels = GetLevels(info)
    if not levels then return end
    if not (row.Label and GameTooltip:IsShown() and GameTooltip:IsOwned(row.Label)) then
        local name = info.name
        if not IsReadable(name) or type(name) ~= "string" or name == "" then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(name)
    end
    GameTooltip:AddLine(ns.Localization.Text("tooltip.skill_range", levels), 1, 1, 1)
    GameTooltip:Show()
end

function CraftingSkillRange.Setup()
    local frame = rawget(_G, "ProfessionsFrame")
    local page = frame and frame.CraftingPage
    if not recipeList and page and page.RecipeList
        and EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        recipeList = page.RecipeList
        EventRegistry:RegisterCallback("Professions.RecipeListOnEnter", OnRecipeEnter, CraftingSkillRange)
    end
end
end)
