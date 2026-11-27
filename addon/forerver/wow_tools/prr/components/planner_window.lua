WoWTools.prr.RegisterSource(function(...)
-- planner_window.lua -- the craft planner: two tabs of the item window
-- (components/item_window.lua) and the profession they work on:
--
--   [Alchemy            v]                     [Layout 1           v]   <- the plan tab only
--   ...the tab...
--   \_Recipes_/ \_Prices_/ \_Planner_/   <- the item window's tabs under its bottom edge
--
-- This is the page of those two tabs, a frame over the whole item window; the
-- item window shows it and says which tab (settings.planner.tab, the last
-- planner tab). The profession select (ui/select.lua) is the same as in Dkp.
--
-- Prices -- auction prices, craft cost and profit (components/prices_tab.lua);
-- Planner -- the cheapest way to level the profession (components/leveling_tab.lua).
-- The helpers for money and recipe titles are shared by the tabs.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local CraftPlanner = ns.Dataflows.CraftPlanner
local ItemNames = ns.Dataflows.ItemNames
local Text = ns.Localization.Text

local PlannerWindow = {}
ns.Components.PlannerWindow = PlannerWindow

local FRAME_NAME = "PRRPlannerWindow"   -- the page, not a window of its own any more
local HEADER_HEIGHT = 34         -- the title band of the border
local PADDING = 14
local PROFESSION_SELECT_WIDTH = 220
local PROFESSION_SELECT_HEIGHT = 26
local LAYOUT_SELECT_WIDTH = 260
local CHECKBOX_GAP = 12
local ENCHANTING = 333
local ALGORITHM_SELECT_WIDTH = 180
local SELECT_GAP = 8
local CONTENT_TOP_GAP = 8        -- between the profession select and the tab
local LOADING_NAME = "..."
local NO_PRICE = "--"
local REAGENT_ICON_SIZE = 18
local REAGENT_ICON_GAP = 3
local MAX_REAGENT_ICONS = 8

local TABS = {
    { id = "prices", title = "planner.tab_prices", component = "PricesTab" },
    { id = "planner", title = "planner.tab_planner", component = "LevelingTab" },
}

local frame = nil

-- Money with the coin icons, "--" for an unknown amount. coinOffsetY -- see
-- Utilities.Money (a larger font: the coins lower).
function PlannerWindow.MoneyText(copper, coinOffsetY)
    if not copper then
        return Config.COLOR_HINT .. NO_PRICE .. "|r"
    end
    return ns.Utilities.Money(copper, coinOffsetY)
end

-- A profit in green, a loss in red.
function PlannerWindow.ProfitText(profit)
    if not profit then
        return Config.COLOR_HINT .. NO_PRICE .. "|r"
    end
    local color = Config.COLOR_PROFIT
    if profit < 0 then
        color = Config.COLOR_LOSS
    end
    return color .. ns.Utilities.Money(profit) .. "|r"
end

-- The recipe name with the number of items it creates.
function PlannerWindow.RecipeTitle(recipe)
    local name = ItemNames.RecipeName(recipe) or LOADING_NAME
    if recipe.count > 1 then
        name = name .. Config.COLOR_TEXT .. " " .. Text("tooltip.created_count", recipe.count) .. "|r"
    end
    return name
end

-- The icon of a recipe row: the created item, the spell for an enchant.
function PlannerWindow.SetRecipeIcon(iconButton, recipe)
    if recipe.item then
        iconButton:SetItem(recipe.item)
    else
        iconButton:SetSpell(recipe.spellID)
    end
end

-- A click on an item icon of the tables: the item into the item window.
function PlannerWindow.OpenItem(iconButton)
    if iconButton.itemID then
        ns.Components.ItemWindow.SetItem(iconButton.itemID)
    end
end

-- The price of an item with the date it was read, for the tooltips.
function PlannerWindow.DatedMoneyText(copper, itemID)
    local text = PlannerWindow.MoneyText(copper)
    local seenAt = ns.Dataflows.AuctionPrices.SeenAt(itemID)
    if seenAt then
        text = text .. " " .. Config.COLOR_HINT .. date(Config.PLANNER_DATE_FORMAT, seenAt) .. "|r"
    end
    return text
end

-- The item tooltip of an icon gets the auction price with its date.
function PlannerWindow.AddPriceTooltip(icon)
    icon:HookScript("OnEnter", function(self)
        if not self.itemID then return end
        local price = ns.Dataflows.AuctionPrices.Get(self.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(Text("planner.price_each"), PlannerWindow.DatedMoneyText(price, self.itemID),
            1, 0.82, 0, 1, 1, 1)
        GameTooltip:Show()
    end)
end

-- The reagent icons of a table row, under its name (next to row.icon): the
-- item tooltip with the price added, a click opens the item.
function PlannerWindow.CreateReagentIcons(row)
    row.reagentIcons = {}
    for i = 1, MAX_REAGENT_ICONS do
        local icon = ns.UI.IconButton(row, {
            size = REAGENT_ICON_SIZE,
            onClick = PlannerWindow.OpenItem,
        })
        if i == 1 then
            icon:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
        else
            icon:SetPoint("LEFT", row.reagentIcons[i - 1], "RIGHT", REAGENT_ICON_GAP, 0)
        end
        PlannerWindow.AddPriceTooltip(icon)
        row.reagentIcons[i] = icon
    end
end

-- The reagents of a recipe on the icons; times -- the counts multiplied (the
-- crafts of a plan step), 1 -- one craft.
function PlannerWindow.FillReagentIcons(row, recipe, times)
    for i, reagentIcon in ipairs(row.reagentIcons) do
        local reagent = recipe.reagents[i]
        if reagent then
            reagentIcon:SetItem(reagent[1], reagent[2] * times)
            reagentIcon:Show()
        else
            reagentIcon:Hide()
        end
    end
end

-- The chosen profession, or the first one there is.
function PlannerWindow.CurrentProfession()
    local chosen = ns.db.settings.planner.profession
    local professions = CraftPlanner.Professions()
    for _, profession in ipairs(professions) do
        if profession == chosen then
            return chosen
        end
    end
    return professions[1]
end

-- The item window is as wide as the layout of the plan tab needs on the planner tabs.
function PlannerWindow.Width()
    return Config.PLANNER_LAYOUT_WIDTHS[ns.db.settings.planner.layout] or Config.PLANNER_WIDTH
end

local function SelectedTab()
    local selected = ns.db.settings.planner.tab
    for _, tab in ipairs(TABS) do
        if tab.id == selected then
            return tab
        end
    end
    return TABS[1]
end

local function RefreshTabs()
    local selected = SelectedTab()
    for _, tab in ipairs(TABS) do
        frame.tabFrames[tab.id]:SetShown(tab == selected)
    end
    frame.professionSelect:Refresh()
    frame.layoutSelect:SetShown(selected.id == "planner")
    frame.layoutSelect:Refresh()
    frame.algorithmSelect:SetShown(selected.id == "planner")
    frame.algorithmSelect:Refresh()
    local isEnchanting = PlannerWindow.CurrentProfession() == ENCHANTING
    frame.autoReplaceCheckbox:SetShown(selected.id == "planner" and isEnchanting)
    ns.Components[selected.component].Refresh()
end

local function SetProfession(profession)
    ns.db.settings.planner.profession = profession
    for _, tab in ipairs(TABS) do
        ns.Components[tab.component].OnProfessionChanged()
    end
    RefreshTabs()
end

-- window -- the item window: the page covers it.
local function Create(window)
    frame = CreateFrame("Frame", FRAME_NAME, window)
    frame:SetAllPoints(window)

    frame.professionSelect = ns.UI.Select(frame, {
        width = PROFESSION_SELECT_WIDTH,
        height = PROFESSION_SELECT_HEIGHT,
        emptyText = Text("planner.no_profession"),
        choices = function()
            local choices = {}
            for _, profession in ipairs(CraftPlanner.Professions()) do
                table.insert(choices, { value = profession, text = ns.GameData.ProfessionName(profession) })
            end
            return choices
        end,
        selected = PlannerWindow.CurrentProfession,
        onChange = SetProfession,
    })
    frame.professionSelect:SetPoint("TOPLEFT", PADDING, -HEADER_HEIGHT)

    -- Enchanting: answer "Replace the enchant?" yes (events/enchant.lua)
    frame.autoReplaceCheckbox = ns.UI.Checkbox(frame, {
        text = Text("planner.auto_replace_enchant"),
        checked = ns.db.settings.planner.autoReplaceEnchant,
        tooltip = Text("planner.auto_replace_enchant_hint"),
        onChange = function(checked)
            ns.db.settings.planner.autoReplaceEnchant = checked
        end,
    })
    frame.autoReplaceCheckbox:SetPoint("LEFT", frame.professionSelect, "RIGHT", CHECKBOX_GAP, 0)

    -- the layout of the plan tab, on the right while it is open
    frame.layoutSelect = ns.UI.Select(frame, {
        width = LAYOUT_SELECT_WIDTH,
        height = PROFESSION_SELECT_HEIGHT,
        choices = ns.Components.LevelingTab.Layouts,
        selected = function()
            return ns.db.settings.planner.layout
        end,
        onChange = function(layout)
            ns.db.settings.planner.layout = layout
            ns.Components.ItemWindow.ApplySize()
            ns.Components.LevelingTab.ApplyLayout()
            ns.Components.LevelingTab.Refresh()
        end,
    })
    frame.layoutSelect:SetPoint("TOPRIGHT", -PADDING, -HEADER_HEIGHT)

    -- the algorithm of the plan, left of the layout
    frame.algorithmSelect = ns.UI.Select(frame, {
        width = ALGORITHM_SELECT_WIDTH,
        height = PROFESSION_SELECT_HEIGHT,
        choices = ns.Components.LevelingTab.Algorithms,
        selected = function()
            return ns.db.settings.planner.algorithm
        end,
        onChange = function(algorithm)
            ns.db.settings.planner.algorithm = algorithm
            ns.Components.LevelingTab.Refresh()
        end,
    })
    frame.algorithmSelect:SetPoint("RIGHT", frame.layoutSelect, "LEFT", -SELECT_GAP, 0)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", PADDING, -(HEADER_HEIGHT + PROFESSION_SELECT_HEIGHT + CONTENT_TOP_GAP))
    content:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    frame.tabFrames = {}
    for _, tab in ipairs(TABS) do
        frame.tabFrames[tab.id] = ns.Components[tab.component].Create(content)
    end

    frame:HookScript("OnShow", RefreshTabs)
end

-- The planner tabs for the tab bar of the item window: { { id, text }, ... }.
function PlannerWindow.Tabs()
    local tabs = {}
    for _, tab in ipairs(TABS) do
        table.insert(tabs, { id = tab.id, text = Text(tab.title) })
    end
    return tabs
end

-- The item window shows the page on a planner tab (id -- "prices" | "planner").
function PlannerWindow.Show(window, id)
    ns.db.settings.planner.tab = id
    if not frame then
        Create(window)
    end
    frame:Show()
    RefreshTabs()
end

function PlannerWindow.Hide()
    if frame then
        frame:Hide()
    end
end

-- /prr planner, the button on the settings page: the item window on the last
-- planner tab, or closed when it is open there already.
function PlannerWindow.Toggle()
    ns.Components.ItemWindow.TogglePlanner()
end

-- The item window on the Plan tab with a profession (the skill-up zones in
-- the profession window open it); one the planner has no recipes of -- the
-- last chosen.
function PlannerWindow.OpenLeveling(profession)
    for _, known in ipairs(CraftPlanner.Professions()) do
        if known == profession and profession ~= ns.db.settings.planner.profession then
            if frame then
                SetProfession(profession)
            else
                ns.db.settings.planner.profession = profession
            end
            break
        end
    end
    ns.Components.ItemWindow.ShowTab("planner")
end

function PlannerWindow.IsShown()
    return frame ~= nil and frame:IsVisible()
end

function PlannerWindow.Refresh()
    if not frame then return end
    RefreshTabs()
end

-- The auction house opened or closed: the scan buttons and the hint follow.
function PlannerWindow.OnAuctionHouseChanged()
    if not frame then return end
    ns.Components.PricesTab.OnAuctionHouseChanged()
end
end)
