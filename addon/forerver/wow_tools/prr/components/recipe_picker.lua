WoWTools.prr.RegisterSource(function(...)
-- recipe_picker.lua -- the side section of the leveling plan: every recipe of
-- the profession with two switches -- force (used wherever it gives a point)
-- and restrict (never used):
--
--   [All recipes             v]      All / Forced / Restricted
--   [Search recipes            ]
--   [icon] Light Armor Kit        [v] [x]
--          [1][30][45][60]
--
-- Knows nothing of the plan itself: the leveling tab gives the state and
-- takes the clicks (options).

local ADDON, ns = ...
ns.Components = ns.Components or {}

local CraftPlanner = ns.Dataflows.CraftPlanner
local ItemNames = ns.Dataflows.ItemNames
local Text = ns.Localization.Text

local RecipePicker = {}
ns.Components.RecipePicker = RecipePicker

local SEARCH_LEFT_INSET = 6
local SELECT_HEIGHT = 26
local GAP = 6
local ROW_HEIGHT = 28             -- the icon and 2 pixels above and under it
local LIST_TOP_PADDING = 4
local ICON_SIZE = 24
local SWITCH_SIZE = 16
local SWITCH_GAP = 4
local SWITCH_OFF_ALPHA = 0.25
local SWITCHES_WIDTH = SWITCH_SIZE * 2 + SWITCH_GAP + 4
local FORCE_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local RESTRICT_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local LOADING_NAME = "..."

local FILTERS = { "all", "forced", "restricted" }

-- A small switch: bright when on, dim when off; a tooltip says what it does.
local function CreateSwitch(row, texture, onClick)
    local switch = CreateFrame("Button", nil, row)
    switch:SetSize(SWITCH_SIZE, SWITCH_SIZE)
    switch.texture = switch:CreateTexture(nil, "ARTWORK")
    switch.texture:SetAllPoints()
    switch.texture:SetTexture(texture)
    switch:SetScript("OnClick", function(self)
        onClick(self:GetParent().recipe)
    end)
    switch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip)
        GameTooltip:Show()
    end)
    switch:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    function switch:SetOn(isOn, tooltip)
        self.texture:SetAlpha(isOn and 1 or SWITCH_OFF_ALPHA)
        self.tooltip = tooltip
    end
    return switch
end

-- options: isForced(spellID), isRestricted(spellID), onToggleForce(recipe),
-- onToggleRestrict(recipe). Returns the section; picker:Refresh() redraws it.
function RecipePicker.Create(parent, options)
    local picker = CreateFrame("Frame", nil, parent)
    local searchText = ""
    local filter = "all"

    local function Matches(recipe, lowerText)
        if filter == "forced" and not options.isForced(recipe.spellID) then
            return false
        end
        if filter == "restricted" and not options.isRestricted(recipe.spellID) then
            return false
        end
        return CraftPlanner.Matches({ recipe = recipe }, lowerText)
    end

    local function FillRow(row, recipe)
        local PlannerWindow = ns.Components.PlannerWindow
        row.recipe = recipe
        PlannerWindow.SetRecipeIcon(row.icon, recipe)
        row.name:SetText(PlannerWindow.RecipeTitle(recipe))
        row.levels:SetText(ns.SkillRange.Text(recipe) or "")
        local isForced = options.isForced(recipe.spellID)
        local isRestricted = options.isRestricted(recipe.spellID)
        row.force:SetOn(isForced, Text(isForced and "planner.unforce" or "planner.force"))
        row.restrict:SetOn(isRestricted, Text(isRestricted and "planner.unrestrict" or "planner.restrict"))
        row:SetAlpha(isRestricted and ns.Config.IGNORED_ROW_ALPHA or 1)
    end

    function picker:Refresh()
        local profession = ns.Components.PlannerWindow.CurrentProfession()
        local recipes = {}
        if profession then
            local lowerText = ns.Utilities.Lower(searchText)
            for _, recipe in ipairs(CraftPlanner.Recipes(profession)) do
                if Matches(recipe, lowerText) then
                    table.insert(recipes, recipe)
                end
            end
        end
        CraftPlanner.SortBySkill(recipes)
        self.list:Fill(#recipes, function(row, index)
            FillRow(row, recipes[index])
        end)
    end

    picker.search = ns.UI.SearchBox(picker, {
        placeholder = Text("planner.search"),
        onChange = function(text)
            if text == searchText then return end
            searchText = text
            picker:Refresh()
        end,
    })
    -- the filter on top, the search under it
    picker.search:SetPoint("TOPLEFT", SEARCH_LEFT_INSET, -(SELECT_HEIGHT + GAP))
    picker.search:SetPoint("RIGHT", 0, 0)

    picker.filter = ns.UI.Select(picker, {
        width = 1,
        height = SELECT_HEIGHT,
        choices = function()
            local choices = {}
            for _, value in ipairs(FILTERS) do
                table.insert(choices, { value = value, text = Text("planner.filter_" .. value) })
            end
            return choices
        end,
        selected = function()
            return filter
        end,
        onChange = function(value)
            filter = value
            picker:Refresh()
        end,
    })
    picker.filter:SetPoint("TOPLEFT", 0, 0)
    picker.filter:SetPoint("RIGHT", 0, 0)

    picker.list = ns.UI.ColumnList(picker, {
        columns = {},
        plain = true,
        topPadding = LIST_TOP_PADDING,
        rowHeight = ROW_HEIGHT,
        iconSize = ICON_SIZE,
        iconTop = true,
        nameRightInset = SWITCHES_WIDTH,
        onIconClick = function(iconButton)
            ns.Components.PlannerWindow.OpenItem(iconButton)
        end,
        onCreateRow = function(row)
            row.name:SetFontObject("GameFontHighlightSmall")
            row.levels = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.levels:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
            row.restrict = CreateSwitch(row, RESTRICT_TEXTURE, options.onToggleRestrict)
            row.restrict:SetPoint("RIGHT", -2, 0)
            row.force = CreateSwitch(row, FORCE_TEXTURE, options.onToggleForce)
            row.force:SetPoint("RIGHT", row.restrict, "LEFT", -SWITCH_GAP, 0)
        end,
        onEnter = function(row)
            GameTooltip:SetOwner(row, "ANCHOR_LEFT")
            GameTooltip:SetText(ItemNames.RecipeName(row.recipe) or LOADING_NAME)
            GameTooltip:AddLine(ns.SkillRange.Text(row.recipe) or "", 1, 1, 1)
            ns.RecipeSources.AddTooltip(GameTooltip, row.recipe)
            GameTooltip:Show()
        end,
    })
    picker.list:SetPoint("TOPLEFT", picker.search, "BOTTOMLEFT", -SEARCH_LEFT_INSET, -GAP)
    picker.list:SetPoint("BOTTOMRIGHT")

    return picker
end
end)
