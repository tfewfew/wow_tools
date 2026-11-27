WoWTools.prr.RegisterSource(function(...)
-- profession_window.lua -- the skill-up zones (components/skill_zones.lua) on
-- the recipe page of the game's profession window: Blizzard_Professions is
-- loaded on demand, the page is taken when it is there; a new recipe on the
-- page -- its Init; the skill went up -- the zones again.

local ADDON, ns = ...

local SkillZones = ns.Components.SkillZones

local hookedPage = nil

-- The recipe page of the profession window (ProfessionsFrame.CraftingPage.SchematicForm), or nil.
local function RecipePage()
    local frame = rawget(_G, "ProfessionsFrame")
    local craftingPage = frame and frame.CraftingPage
    return craftingPage and craftingPage.SchematicForm
end

local function Hook()
    if hookedPage then return end
    local page = RecipePage()
    if not (page and type(page.Init) == "function" and type(page.GetRecipeInfo) == "function") then return end
    hookedPage = page
    SkillZones.Attach(page)
    local function RefreshRecipe(self)
        if not ns.db then return end
        local info = self.GetRecipeInfo and ns.Utilities.Open(self:GetRecipeInfo())
        local id = type(info) == "table" and ns.Utilities.Open(info.recipeID)
        SkillZones.Show(self, type(id) == "number" and id or nil)
    end
    hooksecurefunc(page, "Init", RefreshRecipe)
    page:HookScript("OnShow", RefreshRecipe)
    RefreshRecipe(page)
end

ns.Events.On("ADDON_LOADED", function(name)
    if name == "Blizzard_Professions" then
        Hook()
    end
end)

SkillZones.Setup = Hook
ns.Events.On("PLAYER_LOGIN", Hook)
ns.Events.On("TRADE_SKILL_SHOW", Hook)

local function Refresh()
    if not ns.db then return end
    SkillZones.RefreshAll()
end
ns.Events.On("SKILL_LINES_CHANGED", Refresh)
ns.Events.On("TRADE_SKILL_LIST_UPDATE", Refresh)
end)
