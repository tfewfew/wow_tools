WoWTools.prr.RegisterSource(function(...)
-- skill_zones.lua -- the skill-up zones of the recipe chosen in the game's
-- profession window, in the empty space at the bottom of its recipe page,
-- set like the "Reagents:" block above it:
--
--   Skill-ups:                                       PRR [plan] [gear]
--   Yellow  skill-up chance 83%
--   [ orange      | YELLOW  ◆      | green      | gray ]
--     65            95               110          125
--   Materials: 1g 20s 00c                              Sale: 2g 05s 00c
--
-- The zone the skill is in is bright, the others are dimmed; the marker (a
-- line with a diamond) stands on the skill. The zones -- for a recipe with
-- its levels known (SkillRange.Levels, the gray ones of one level too) and a
-- profession the character has; the prices -- for every recipe, by the
-- auction scan of the planner (CraftPlanner.Evaluate): the reagents of one
-- craft and what it makes. A recipe the base lacks is read from the game
-- (RecipeScan.ReadRecipe): prices only. The setting is
-- settings.showSkillZones -- the gear at the right says whose block this is
-- and opens that page of the settings; the steps beside it open the leveling
-- plan of the profession.
-- events/profession_window.lua attaches it to the recipe page.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local Text = ns.Localization.Text

local SkillZones = {}
ns.Components.SkillZones = SkillZones

-- placement on the recipe page: the left edge of "Reagents:", above Track Recipe
local SIDE_INSET = 28
local BOTTOM_OFFSET = 92
local CHECKBOX_GAP = 10

-- rows from the top of the panel
local STATUS_TOP = -16
local BAR_TOP = -36
local BAR_HEIGHT = 10
local LABEL_TOP = -5             -- the levels under the bar
local PRICES_TOP = -66           -- the prices under the levels
local PRICES_ONLY_TOP = -16      -- the prices under the title, without zones
local HEIGHT = 80
local PRICES_ONLY_HEIGHT = 30

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FRAME_COLOR = { 0.32, 0.26, 0.16, 1 }   -- the bronze edge of the window's insets
local SHADOW_COLOR = { 0, 0, 0, 0.9 }
local DIVIDER_ALPHA = 0.75
local DIM_ALPHA = 0.35           -- the zones the skill is not in
local GRAY_TAIL = 0.12           -- the part of the bar after the gray level
local MIN_GRAY_TAIL = 5          -- levels after gray at least: a recipe of one level is all gray
local LABEL_GAP = 6

local MARKER_WIDTH = 2
local MARKER_OVERHANG = 3        -- the line sticks out of the bar above and below
local DIAMOND_SIZE = 7
local DIAMOND_OUTLINE = 2
local MARKER_LEVEL = 5           -- above the zones and the dividers

local ICON_BUTTON_SIZE = 14
local ICON_BUTTON_GAP = 5        -- between "PRR" and the buttons, and between them
local ICON_COLOR = { 0.48, 0.48, 0.48 }   -- as the dim "PRR" (Config.COLOR_ADDON_MARK)
local ICON_HOVER_COLOR = { 1, 0.82, 0 }
local ICON_HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local SETTINGS_PAGE = "profession"

local ZONES = { "orange", "yellow", "green", "gray" }

local panels = {}                -- [recipe page] = panel

local function Hex(zone)
    local color = Config.SKILL_ZONE_COLORS[zone]
    return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

local function SetColor(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

local function Rotate(texture)
    if texture.SetRotation then
        pcall(texture.SetRotation, texture, math.rad(45))
    end
end

-- The frame of the bar: a bronze edge and a dark line inside it, like the
-- insets of the profession window.
local function CreateBarFrame(bar)
    local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    edge:SetPoint("TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", 2, -2)
    SetColor(edge, FRAME_COLOR)
    local shadow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    shadow:SetPoint("TOPLEFT", -1, 1)
    shadow:SetPoint("BOTTOMRIGHT", 1, -1)
    SetColor(shadow, SHADOW_COLOR)
end

-- The marker of the skill: a white line through the bar with a dark outline
-- and a diamond on its top.
local function CreateMarker(bar)
    local marker = CreateFrame("Frame", nil, bar)
    marker:SetSize(DIAMOND_SIZE + DIAMOND_OUTLINE * 2, BAR_HEIGHT + MARKER_OVERHANG * 2)
    marker:SetFrameLevel(bar:GetFrameLevel() + MARKER_LEVEL)
    local outline = marker:CreateTexture(nil, "ARTWORK")
    outline:SetPoint("TOP")
    outline:SetPoint("BOTTOM")
    outline:SetWidth(MARKER_WIDTH + 2)
    SetColor(outline, SHADOW_COLOR)
    local line = marker:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOP", 0, -1)
    line:SetPoint("BOTTOM", 0, 1)
    line:SetWidth(MARKER_WIDTH)
    line:SetColorTexture(1, 1, 1, 1)
    local diamondOutline = marker:CreateTexture(nil, "OVERLAY", nil, 1)
    diamondOutline:SetSize(DIAMOND_SIZE + DIAMOND_OUTLINE, DIAMOND_SIZE + DIAMOND_OUTLINE)
    diamondOutline:SetPoint("CENTER", marker, "TOP", 0, 0)
    SetColor(diamondOutline, SHADOW_COLOR)
    Rotate(diamondOutline)
    local diamond = marker:CreateTexture(nil, "OVERLAY", nil, 2)
    diamond:SetSize(DIAMOND_SIZE, DIAMOND_SIZE)
    diamond:SetPoint("CENTER", marker, "TOP", 0, 0)
    diamond:SetColorTexture(1, 1, 1, 1)
    Rotate(diamond)
    return marker
end

-- A small white-art button of the title row (as the header buttons of Loot
-- Buddy): dim, gold under the mouse, a tooltip of the addon's title and two
-- lines (white, then gray) -- tooltipLines() gives them.
local function CreateIconButton(panel, texture, tooltipLines, onClick)
    local button = CreateFrame("Button", nil, panel)
    button:SetSize(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(texture)
    icon:SetVertexColor(unpack(ICON_COLOR))
    button.icon = icon
    button:SetHighlightTexture(ICON_HIGHLIGHT, "ADD")
    -- pressed: the picture moves a pixel down and right, like game buttons
    button:SetScript("OnMouseDown", function()
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", 1, -1)
    end)
    button:SetScript("OnMouseUp", function()
        icon:ClearAllPoints()
        icon:SetAllPoints()
    end)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        icon:SetVertexColor(unpack(ICON_HOVER_COLOR))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.Constants.ADDON_TITLE)
        local title, hint = tooltipLines()
        GameTooltip:AddLine(title, 1, 1, 1, true)
        GameTooltip:AddLine(hint, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        icon:SetVertexColor(unpack(ICON_COLOR))
        GameTooltip:Hide()
    end)
    return button
end

-- The gear: whose block this is and where it is turned off; a click opens that page of the settings.
local function CreateGear(panel)
    return CreateIconButton(panel, ns.Constants.SETTINGS_ICON, function()
        return Text("skill_zones.gear_title"), Text("skill_zones.gear_hint", Text("options.pages.profession"))
    end, function()
        ns.Components.OptionsPanel.Open(SETTINGS_PAGE)
    end)
end

-- The steps: what the craft planner is; a click opens its plan for the profession of the recipe.
local function CreatePlannerButton(panel)
    return CreateIconButton(panel, ns.Constants.PLANNER_ICON, function()
        return Text("options.pages.planner"), Text("skill_zones.planner_hint")
    end, function()
        if panel.recipe then
            ns.Components.PlannerWindow.OpenLeveling(panel.recipe.profession)
        end
    end)
end

local function Create(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(HEIGHT)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.title:SetPoint("TOPLEFT")
    panel.title:SetText(Text("skill_zones.title"))

    panel.gear = CreateGear(panel)
    panel.gear:SetPoint("TOPRIGHT", 0, 1)
    panel.plannerButton = CreatePlannerButton(panel)
    panel.plannerButton:SetPoint("RIGHT", panel.gear, "LEFT", -ICON_BUTTON_GAP, 0)
    panel.mark = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.mark:SetPoint("TOPRIGHT", panel.plannerButton, "TOPLEFT", -ICON_BUTTON_GAP, -1)
    panel.mark:SetText(Config.COLOR_ADDON_MARK .. ns.Constants.ADDON_SHORT_TITLE .. "|r")

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", 0, STATUS_TOP)
    panel.status:SetJustifyH("LEFT")

    -- the cost of the reagents at the left, the price of what it makes at the right
    panel.cost = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.cost:SetJustifyH("LEFT")
    panel.sale = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sale:SetJustifyH("RIGHT")

    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 0, BAR_TOP)
    bar:SetPoint("TOPRIGHT", 0, BAR_TOP)
    bar:SetHeight(BAR_HEIGHT)
    panel.bar = bar
    CreateBarFrame(bar)

    panel.zones, panel.dividers, panel.labels = {}, {}, {}
    for _, zone in ipairs(ZONES) do
        local color = Config.SKILL_ZONE_COLORS[zone]
        local texture = bar:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(BAR_TEXTURE)
        texture:SetVertexColor(color[1], color[2], color[3], 1)
        panel.zones[zone] = texture
        local divider = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        divider:SetWidth(1)
        divider:SetPoint("TOP")
        divider:SetPoint("BOTTOM")
        SetColor(divider, { 0, 0, 0, DIVIDER_ALPHA })
        panel.dividers[zone] = divider
        panel.labels[zone] = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end

    panel.marker = CreateMarker(bar)

    -- the bar has its width only once the page is laid out
    bar:SetScript("OnSizeChanged", function()
        SkillZones.Layout(panel)
    end)
    return panel
end

-- The Track Recipe checkbox of the page, by the names it had in the game's versions.
local function TrackCheckbox(page)
    for _, key in ipairs({ "TrackRecipeCheckbox", "TrackRecipeCheckBox", "TrackRecipeButton" }) do
        local checkbox = page[key]
        if type(checkbox) == "table" then
            return checkbox
        end
    end
    return nil
end

local function Anchor(panel, page)
    panel:ClearAllPoints()
    panel:SetPoint("LEFT", page, "LEFT", SIDE_INSET, 0)
    panel:SetPoint("RIGHT", page, "RIGHT", -SIDE_INSET, 0)
    local checkbox = TrackCheckbox(page)
    if checkbox then
        panel:SetPoint("BOTTOM", checkbox, "TOP", 0, CHECKBOX_GAP)
    else
        panel:SetPoint("BOTTOM", page, "BOTTOM", 0, BOTTOM_OFFSET)
    end
end

function SkillZones.Attach(page)
    if panels[page] then return panels[page] end
    local panel = Create(page)
    Anchor(panel, page)
    panel:Hide()
    panels[page] = panel
    return panel
end

-- The skill of the character in the profession of a recipe, or nil.
local function Skill(profession)
    local skill = ns.GameData.ProfessionSkill(profession)
    if skill then return skill end
    local api = C_TradeSkillUI
    if api and api.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(api.GetProfessionInfoBySkillLineID, profession)
        info = ok and ns.Utilities.Open(info)
        local skill = type(info) == "table" and ns.Utilities.Open(info.skillLevel)
        if type(skill) == "number" and skill > 0 then
            return skill
        end
    end
    return nil
end

-- The status line: the zone the skill is in and the chance of a skill point
-- there (orange 100%, gray 0%).
function SkillZones.StatusText(zone)
    if zone.zone == "locked" then
        return Config.COLOR_HINT .. Text("skill_zones.locked", zone.learn) .. "|r"
    end
    return Hex(zone.zone) .. Text("skill_zones.zone_" .. zone.zone) .. "|r  "
        .. Text("skill_zones.chance", math.floor(zone.chance * 100 + 0.5))
end

-- Places the zones, the levels and the marker by the width of the bar.
function SkillZones.Layout(panel)
    local recipe, skill = panel.recipe, panel.skill
    if not recipe or not skill then return end
    local width = panel.bar:GetWidth()
    if not width or width <= 0 then return end
    local levels = ns.SkillRange.Levels(recipe)
    local current = ns.SkillRange.Zone(recipe, skill).zone
    local finish = levels.gray + math.max((levels.gray - levels.learn) * GRAY_TAIL / (1 - GRAY_TAIL), MIN_GRAY_TAIL)
    local function X(level)
        local share = (level - levels.learn) / math.max(finish - levels.learn, 1)
        return math.floor(math.max(0, math.min(1, share)) * width + 0.5)
    end
    local edges = {
        orange = { levels.learn, levels.yellow },
        yellow = { levels.yellow, levels.green },
        green = { levels.green, levels.gray },
        gray = { levels.gray, finish },
    }
    local labelRight = -LABEL_GAP
    for index, zone in ipairs(ZONES) do
        local left, right = X(edges[zone][1]), X(edges[zone][2])
        local hasWidth = right - left >= 1
        local texture = panel.zones[zone]
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", panel.bar, "TOPLEFT", left, 0)
        texture:SetPoint("BOTTOMLEFT", panel.bar, "BOTTOMLEFT", left, 0)
        texture:SetWidth(math.max(right - left, 1))
        texture:SetShown(hasWidth)
        texture:SetAlpha((zone == current) and 1 or DIM_ALPHA)
        -- a dark line between two zones
        local divider = panel.dividers[zone]
        divider:ClearAllPoints()
        divider:SetPoint("TOP", panel.bar, "TOPLEFT", left, 0)
        divider:SetPoint("BOTTOM", panel.bar, "BOTTOMLEFT", left, 0)
        divider:SetShown(index > 1 and hasWidth)
        -- the level where the zone starts, under its edge; none for an empty
        -- zone, pushed right of the one before
        local label = panel.labels[zone]
        label:SetText(Hex(zone) .. edges[zone][1] .. "|r")
        label:SetShown(hasWidth)
        if hasWidth then
            local labelWidth = label:GetStringWidth() or 0
            local x = math.max(left - labelWidth / 2, labelRight + LABEL_GAP, 0)
            x = math.min(x, width - labelWidth)
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", panel.bar, "BOTTOMLEFT", x, LABEL_TOP)
            labelRight = x + labelWidth
        end
    end
    panel.marker:ClearAllPoints()
    panel.marker:SetPoint("CENTER", panel.bar, "LEFT", X(skill), 0)
end

-- A recipe the base lacks, as the game gives it: { item, count, reagents }, or nil.
local function GameRecipe(spellID)
    local read = ns.Services.RecipeScan and ns.Services.RecipeScan.ReadRecipe
    local scan = read and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic and read(spellID)
    if not scan then return nil end
    local reagents = {}
    for i = 1, #scan.reagents, 2 do
        table.insert(reagents, { scan.reagents[i], scan.reagents[i + 1] })
    end
    return { spellID = spellID, item = scan.item, count = scan.count or 1, reagents = reagents,
             profession = scan.profession }
end

local function PriceText(copper)
    return ns.Utilities.Money(copper)
end

-- "Materials: 1g 20s 00c" -- the reagents of one craft by the auction scan;
-- "+ ?" when a reagent has no price, "no price" when none has.
function SkillZones.CostText(evaluation)
    local value
    if evaluation.missing > 0 and evaluation.cost == 0 then
        value = Config.COLOR_HINT .. Text("skill_zones.no_price") .. "|r"
    elseif evaluation.missing > 0 then
        value = PriceText(evaluation.cost) .. Config.COLOR_HINT .. " + ?|r"
    else
        value = PriceText(evaluation.cost)
    end
    return Config.COLOR_HINT .. Text("skill_zones.materials") .. "|r " .. value
end

-- "Sale: 2g 05s 00c" -- what one craft makes, by the auction scan; "" for an
-- enchant (it makes no item).
function SkillZones.SaleText(evaluation)
    if not evaluation.recipe.item then return "" end
    local value = evaluation.sale and PriceText(evaluation.sale)
        or (Config.COLOR_HINT .. Text("skill_zones.no_price") .. "|r")
    return Config.COLOR_HINT .. Text("skill_zones.sale") .. "|r " .. value
end

-- Shows the zones and the prices of a recipe (spell id) on the page, or hides them.
function SkillZones.Show(page, spellID)
    local panel = panels[page]
    if not panel then return end
    panel.spellID = spellID
    local recipe = spellID and ns.db.settings.showSkillZones
        and (ns.Dataflows.RecipeIndex.Get(spellID) or GameRecipe(spellID))
    if not recipe then
        panel.recipe = nil
        panel:Hide()
        return
    end
    local skill = ns.SkillRange.Levels(recipe) and recipe.profession and Skill(recipe.profession)
    local hasZones = skill ~= nil
    panel.recipe, panel.skill = recipe, skill
    panel.status:SetShown(hasZones)
    panel.bar:SetShown(hasZones)
    for _, label in pairs(panel.labels) do
        label:SetShown(hasZones)
    end
    if hasZones then
        panel.status:SetText(SkillZones.StatusText(ns.SkillRange.Zone(recipe, skill)))
    end

    local pricesTop = hasZones and PRICES_TOP or PRICES_ONLY_TOP
    panel.cost:ClearAllPoints()
    panel.cost:SetPoint("TOPLEFT", 0, pricesTop)
    panel.sale:ClearAllPoints()
    panel.sale:SetPoint("TOPRIGHT", 0, pricesTop)
    local evaluation = ns.Dataflows.CraftPlanner.Evaluate(recipe)
    panel.cost:SetText(SkillZones.CostText(evaluation))
    panel.sale:SetText(SkillZones.SaleText(evaluation))
    panel:SetHeight(hasZones and HEIGHT or PRICES_ONLY_HEIGHT)
    panel:Show()
    if hasZones then
        SkillZones.Layout(panel)
    end
end

-- Again for the same recipes: the skill went up, the setting changed.
function SkillZones.RefreshAll()
    for page, panel in pairs(panels) do
        SkillZones.Show(page, panel.spellID)
    end
end
end)
