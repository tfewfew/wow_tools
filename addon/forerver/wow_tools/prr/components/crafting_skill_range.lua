WoWTools.prr.RegisterSource(function(...)
-- Show PRR's colored skill thresholds in the native crafting page and recipe hover.
local _, ns = ...
ns.Components = ns.Components or {}

local CraftingSkillRange = {}
ns.Components.CraftingSkillRange = CraftingSkillRange
local form, label, recipeList

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

local function Refresh()
    if not form or not form:IsVisible() or not ns.db then return end
    local levels = GetLevels(form:GetRecipeInfo())
    label:SetText(levels or "")
    label:SetShown(levels ~= nil)
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
    if form then return end
    local schematic = page and page.SchematicForm
    local checkbox = schematic and schematic.TrackRecipeCheckbox
    if not checkbox or type(schematic.Init) ~= "function"
        or type(schematic.GetRecipeInfo) ~= "function" then return end

    form = schematic
    label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkbox.prrSkillRange = label
    label:SetPoint("RIGHT", checkbox, "LEFT", -8, 0)
    label:SetJustifyH("RIGHT")
    label:SetWordWrap(false)
    label:Hide()

    hooksecurefunc(form, "Init", Refresh)
    form:HookScript("OnShow", Refresh)
    hooksecurefunc(ns.Dataflows.RecipeIndex, "Invalidate", Refresh)
    Refresh()
end
end)
