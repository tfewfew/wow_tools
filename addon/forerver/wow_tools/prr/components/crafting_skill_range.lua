WoWTools.prr.RegisterSource(function(...)
-- Show PRR's colored skill thresholds beside the native recipe tracking checkbox.
local _, ns = ...
ns.Components = ns.Components or {}

local CraftingSkillRange = {}
ns.Components.CraftingSkillRange = CraftingSkillRange
local form, label

local function Refresh()
    if not form or not form:IsVisible() or not ns.db then return end
    local info = form:GetRecipeInfo()
    local recipe
    if type(info) == "table" and not (issecretvalue and issecretvalue(info)) then
        local recipeID = info.recipeID
        if type(recipeID) == "number" and not (issecretvalue and issecretvalue(recipeID)) then
            recipe = ns.Dataflows.RecipeIndex.Get(recipeID)
        end
    end
    local levels = recipe and ns.SkillRange.Text(recipe)
    label:SetText(levels or "")
    label:SetShown(levels ~= nil)
end

function CraftingSkillRange.Setup()
    if form then return end
    local frame = rawget(_G, "ProfessionsFrame")
    local page = frame and frame.CraftingPage
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
