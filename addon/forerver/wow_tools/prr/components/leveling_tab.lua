WoWTools.prr.RegisterSource(function(...)
-- leveling_tab.lua -- the "Planner" tab of the planner window: the cheapest
-- way to level the chosen profession (dataflows/skill_planner.lua):
--
--   Skill [  1 ] - [ 150 ]   [x] Include yellow recipes   | the recipes (RecipePicker):
--   Total: 12g 40s / About 160 crafts                      | search, filter, force and
--                                                          | restrict switches
--   Recipe                          Skill       Crafts       Cost
--   [icon] Light Armor Kit          1-30        30           1g 20s
--          [reagent x30][reagent x30]                             <- for all the crafts of the step
--   [icon] Heavy Armor Kit          100-115     22 (+7)      3g      <- yellow: overspend
--   Reagents to buy: 4g 10s                              [To Shopping list]   <- with Auctionator
--   Reagent                  Need    Have    Buy     Cost
--   [icon] Light Leather     120     40      80      4g
--
-- Crafts are the average; with yellow recipes some fail -- the average extra
-- crafts (the overspend) are marked "(+N)" and summed under the total.
-- The plan is counted again on every change (the skill fields, the switches).
-- Right click on a step, or the switches of the recipe list on the right:
-- restrict the recipe (it is left out of every plan), force it (used wherever it gives points),
-- set its price for this plan. Forced recipes and set prices belong to the
-- current plan: another profession starts a clean one.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local AuctionPrices = ns.Dataflows.AuctionPrices
local Config = ns.Config
local ItemNames = ns.Dataflows.ItemNames
local SkillPlanner = ns.Dataflows.SkillPlanner
local Text = ns.Localization.Text

local LevelingTab = {}
ns.Components.LevelingTab = LevelingTab

local RECIPE_BUTTON_SIZE = 20
local KNOWN_TINT = { 0.4, 1, 0.4 }   -- a learned recipe: its row, the line of its tooltip
local KNOWN_TINT_ALPHA = 0.15        -- faint: a hint, not a highlight
local NOT_ON_SALE_TINT = { 1, 0.15, 0.15 }   -- the recipe to buy is not on the auction house: its row
local NOT_ON_SALE_TINT_ALPHA = 0.25
local CHECKBOX_GAP = 14          -- between a checkbox label and the next checkbox
local RECIPE_BUTTON_GAP = 10     -- before the skill column
local SKILL_INPUT_WIDTH = 46
local SKILL_MAX_LETTERS = 3
local MAXIMUM_SKILL = 450
local SIDE_WIDTH = 260           -- the recipe list on the right
local WIDE_SIDE_WIDTH = 520      -- the right column of layout 3: the reagents and the recipes
local BUTTON_HEIGHT = 22
local GAP = 8
local SUMMARY_TOP = -32
local SKILL_BAR_TOP = -30        -- the skill bar (From current skill), under the skill row
local SKILL_BAR_ROW = 32         -- the summary goes down by it while the bar is shown
local SUMMARY_LINE_SPACING = 4   -- between the total and the overspend line under it
local SUMMARY_LINE_HEIGHT = 14   -- a line of GameFontHighlight
-- the skill row and the summary (three lines)
local HEADER_HEIGHT = 74 + SUMMARY_LINE_HEIGHT + 2 * SUMMARY_LINE_SPACING
local STEP_ROW_HEIGHT = 36       -- the icon and 2 pixels above and under it
local STEP_ICON_SIZE = 32
local SKILL_COLUMN_WIDTH = 70
local CRAFTS_COLUMN_WIDTH = 64
local CRAFT_COLUMN_WIDTH = 30     -- the Craft button of a learned recipe
local REAGENTS_HEIGHT = 170      -- the reagents to buy, under the steps
local REAGENTS_TITLE_HEIGHT = 16
local YELLOW_CHANCE_SELECT_WIDTH = 250   -- the chance of yellow crafts, under their checkbox: the whole text fits
local YELLOW_CHANCE_SELECT_HEIGHT = 22
local LARGE_TEXT_COIN_OFFSET = -3        -- the coins in the summary (a font larger than the tables)
local REAGENTS_TITLE_COIN_OFFSET = -1    -- the coins in the reagents title
local SECOND_ROW_TOP = -28               -- the selects under the skill row: the recipes, the chance of yellow crafts
local SECOND_ROW = 28                    -- the skill bar and the summary are under it
local RECIPE_SOURCE_SELECT_WIDTH = 230
local RECIPE_SOURCES = { "all", "trainer", "auction" }   -- the recipes the plan may use
local YELLOW_CHANCES = { 10, 20, 30, 40, 50, 60, 70, 80, 90 }   -- percent, after "Auto"
local SHOPPING_BUTTON_WIDTH = 130   -- "To Shopping list", right of the title of the reagents
local SHOPPING_BUTTON_HEIGHT = 20
local REAGENTS_TITLE_GAP = 12    -- between the steps and the title of the reagents
local TITLE_TABLE_GAP = 10       -- between a title (the summary, the reagents one) and its table
local REAGENT_ROW_HEIGHT = 22
local REAGENT_ICON_SIZE = 18
local COUNT_COLUMN_WIDTH = 46
local NEED_COLUMN_WIDTH = 90     -- "120 | ~35" with yellow recipes
local TILDE_DROP = 3             -- the font draws "~" high: lowered to the middle of the digits
local MIN_EXTRA_CRAFTS_SHOWN = 0.5   -- less overspend is not worth a mark
local SKILL_BAR_HEIGHT = 3       -- under the skill range: orange and yellow points
local ORANGE_COLOR = { 1, 0.5, 0.25 }
local YELLOW_COLOR = { 1, 1, 0 }
local LOADING_NAME = "..."
local FORCED_MARK = "|cffffd100>|r "
local COLOR_CUSTOM_PRICE = "|cff66bbff"

local tab = nil
-- the current plan: forced recipes and prices set by the player
local plan = { forced = {}, prices = {} }
local result = nil
-- the recipes the plan buys: { byStep = { [step] = price | false (no price) }, total, unknown }
local purchases = nil

local function ReadSkill(input, fallback)
    local value = tonumber(input:GetText())
    if not value then
        return fallback
    end
    return math.max(1, math.min(MAXIMUM_SKILL, math.floor(value)))
end

local function SummaryText()
    if not result then
        return Config.COLOR_HINT .. Text("planner.set_range") .. "|r"
    end
    local function MoneyText(copper)
        return ns.Components.PlannerWindow.MoneyText(copper, LARGE_TEXT_COIN_OFFSET)
    end
    -- three lines: the money (with the recipes to buy), the crafts, the overspend
    local lines = {}
    local money = Text("planner.total", MoneyText(result.totalCost + purchases.total))
    if purchases.total > 0 then
        money = money .. " " .. Config.COLOR_HINT .. Text("planner.total_recipes", MoneyText(purchases.total)) .. "|r"
    end
    if purchases.unknown > 0 then
        money = money .. "  " .. Config.COLOR_LOSS .. Text("planner.recipes_without_price", purchases.unknown) .. "|r"
    end
    table.insert(lines, money)
    local crafts = Text("planner.total_crafts", math.ceil(result.totalCrafts))
    if result.stuckAt then
        crafts = crafts .. "  " .. Config.COLOR_LOSS .. Text("planner.stuck", result.stuckAt) .. "|r"
    end
    table.insert(lines, crafts)
    if result.extraCrafts >= MIN_EXTRA_CRAFTS_SHOWN then
        table.insert(lines, Config.COLOR_HINT
            .. Text("planner.overspend", math.ceil(result.extraCrafts), MoneyText(result.extraCost)) .. "|r")
    end
    return table.concat(lines, "\n")
end

-- Not learned, and the item that teaches it (the base knows it) is in neither
-- the bags nor the bank: the plan has to buy it.
local function IsRecipeToBuy(recipe)
    return recipe.recipeItem ~= nil and not ns.GameData.IsRecipeKnown(recipe.spellID)
        and ns.Utilities.ItemCount(recipe.recipeItem) == 0
end

-- The price of the pattern the plan has to buy for a recipe; nil -- nothing
-- to buy, or no price (the plan cannot weigh it).
local function RecipePrice(recipe)
    if IsRecipeToBuy(recipe) and not recipe.recipeItemBound then
        return AuctionPrices.Get(recipe.recipeItem)
    end
    return nil
end

-- The recipes the plan may use (settings.planner.recipeSource): "all"; "trainer"
-- -- the ones a trainer teaches (no pattern in the base), learned ones, and the
-- ones whose pattern is in the bags or the bank; "auction" -- those and the ones
-- whose pattern is on the auction house (by the last scan, not bound).
function LevelingTab.IsRecipeAvailable(recipe)
    local source = ns.db.settings.planner.recipeSource
    if source ~= "trainer" and source ~= "auction" then return true end
    if not recipe.recipeItem then return true end
    local isOwned = ns.GameData.IsRecipeKnown(recipe.spellID) or ns.Utilities.ItemCount(recipe.recipeItem) > 0
    if isOwned then return true end
    return source == "auction" and not recipe.recipeItemBound and AuctionPrices.Get(recipe.recipeItem) ~= nil
end

-- Why a recipe to buy has no price, or nil (it has one, or is not to buy):
-- "bound" -- it binds when picked up, never on the auction house; "not_on_sale"
-- -- the last scan found none; "not_scanned" -- never looked up yet.
local function RecipeProblem(recipe)
    if not IsRecipeToBuy(recipe) then return nil end
    if recipe.recipeItemBound then return "bound" end
    if AuctionPrices.Get(recipe.recipeItem) then return nil end
    if AuctionPrices.SeenAt(recipe.recipeItem) then return "not_on_sale" end
    return "not_scanned"
end

-- The tooltip line of a recipe item without a price, red.
local function AddRecipeProblemLine(problem, itemName)
    local key = "planner.recipe_" .. problem
    GameTooltip:AddLine(Text(key, itemName), NOT_ON_SALE_TINT[1], NOT_ON_SALE_TINT[2], NOT_ON_SALE_TINT[3], true)
end

-- The reagents of the plan, with the recipe items it has to buy first (one of
-- each, isRecipe; problem -- see RecipeProblem): { itemID, count, price, isRecipe, problem, ... }.
local function PlanReagents()
    if not result then return {} end
    local list = {}
    local seen = {}
    for _, step in ipairs(result.steps) do
        local recipe = step.recipe
        if IsRecipeToBuy(recipe) and not seen[recipe.recipeItem] then
            seen[recipe.recipeItem] = true
            table.insert(list, {
                itemID = recipe.recipeItem,
                count = 1,
                price = AuctionPrices.Get(recipe.recipeItem),
                isRecipe = true,
                problem = RecipeProblem(recipe),
            })
        end
    end
    for _, reagent in ipairs(SkillPlanner.Reagents(result)) do
        table.insert(list, reagent)
    end
    return list
end

-- The recipes the plan has to buy, each counted once, at the first step that
-- needs it (see purchases).
local function CountPurchases()
    local counted = { byStep = {}, total = 0, unknown = 0 }
    local seen = {}
    for _, step in ipairs(result and result.steps or {}) do
        local recipe = step.recipe
        if IsRecipeToBuy(recipe) and not seen[recipe.recipeItem] then
            seen[recipe.recipeItem] = true
            local price = AuctionPrices.Get(recipe.recipeItem)
            counted.byStep[step] = price or false
            if price then
                counted.total = counted.total + price
            else
                counted.unknown = counted.unknown + 1
            end
        end
    end
    return counted
end

local function FillRow(row, step)
    local PlannerWindow = ns.Components.PlannerWindow
    local recipe = step.recipe
    row.step = step
    PlannerWindow.SetRecipeIcon(row.icon, recipe)
    local name = PlannerWindow.RecipeTitle(recipe)
    if step.isForced then
        name = FORCED_MARK .. name
    end
    row.name:SetText(name)
    PlannerWindow.FillReagentIcons(row, recipe, SkillPlanner.StepCrafts(step))
    -- learned: a faint tint, a click opens it in the profession; not learned --
    -- the item that teaches it, when the base knows one
    row.isKnown = ns.GameData.IsRecipeKnown(recipe.spellID)
    row.knownTint:SetShown(row.isKnown)
    row.craftButton:SetShown(row.isKnown and ns.Services.CraftService.CanCraft(recipe))
    row.craftButton:SetStep(step)
    if not row.isKnown and recipe.recipeItem then
        row.recipeButton:SetItem(recipe.recipeItem)
        row.recipeButton:Show()
    else
        row.recipeButton:Hide()
    end
    -- the recipe has to be bought, but the auction house has none: red
    row.isRecipeToBuy = IsRecipeToBuy(recipe)
    row.recipeProblem = RecipeProblem(recipe) or false
    row.notOnSaleTint:SetShown(row.recipeProblem ~= false)
    row.cells[1]:SetText(Text("planner.skill_range", step.from, step.to))
    -- the bar: as many parts orange and yellow as points of each color
    local points = step.orangePoints + step.yellowPoints
    local width = row.cells[1]:GetWidth()
    local orangeWidth = width * step.orangePoints / math.max(points, 1)
    row.orangeBar:SetWidth(math.max(orangeWidth, 0.01))
    row.orangeBar:SetShown(step.orangePoints > 0)
    row.yellowBar:SetShown(step.yellowPoints > 0)
    local crafts = tostring(SkillPlanner.StepCrafts(step))
    if step.extraCrafts >= MIN_EXTRA_CRAFTS_SHOWN then
        crafts = crafts .. Config.COLOR_HINT .. " (+" .. math.ceil(step.extraCrafts) .. ")|r"
    end
    row.cells[2]:SetText(crafts)
    -- the recipe to buy is in the cost of its first step; no price -- "+?"
    local recipePrice = purchases.byStep[step]
    local cost = PlannerWindow.MoneyText(step.cost + (recipePrice or 0))
    if step.hasNoPrice then
        cost = PlannerWindow.MoneyText(nil)
    elseif step.hasCustomPrice then
        cost = COLOR_CUSTOM_PRICE .. "*|r " .. cost
    end
    if recipePrice == false then
        cost = cost .. " " .. Config.COLOR_LOSS .. "+?|r"
    end
    row.recipePrice = recipePrice
    row.cells[3]:SetText(cost)
end

-- "120 | ~35" in the Need column, right-aligned in it: three texts, the "~"
-- on its own to be lowered.
local function CreateNeedTexts(row)
    -- a recipe item without a price: the row red (FillReagentRow)
    row.problemTint = row:CreateTexture(nil, "BORDER")
    row.problemTint:SetAllPoints()
    row.problemTint:SetColorTexture(NOT_ON_SALE_TINT[1], NOT_ON_SALE_TINT[2], NOT_ON_SALE_TINT[3], NOT_ON_SALE_TINT_ALPHA)
    row.problemTint:Hide()
    local cell = row.cells[1]
    row.needYellow = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.needYellow:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    row.needYellow:SetTextColor(1, 1, 0)
    row.needTilde = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.needTilde:SetPoint("RIGHT", row.needYellow, "LEFT", 0, -TILDE_DROP)
    row.needTilde:SetTextColor(1, 1, 0)
    row.needTilde:SetText("~")
    row.needOrange = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.needOrange:SetPoint("RIGHT", row.needTilde, "LEFT", 0, TILDE_DROP)
end

-- One reagent of the plan: needed, in the bags and the bank, to buy, its cost.
local function FillReagentRow(row, reagent)
    local MoneyText = ns.Components.PlannerWindow.MoneyText
    row.reagent = reagent
    row.icon:SetItem(reagent.itemID)
    local name = ItemNames.ItemName(reagent.itemID) or LOADING_NAME
    -- smart: the part the plan crafts itself
    if reagent.crafted and reagent.crafted > 0 then
        name = name .. Config.COLOR_HINT .. " " .. Text("planner.crafted_in_plan", reagent.crafted) .. "|r"
    end
    row.name:SetText(name)
    -- a recipe item without a price (bound, not on sale, not scanned): the row red
    row.problemTint:SetShown(reagent.problem ~= nil)
    local have = ns.Utilities.ItemCount(reagent.itemID)
    local toBuy = math.max(0, reagent.count - have)
    -- with yellow recipes: for sure (orange) | on average (yellow); a recipe item -- just one
    local isSplit = ns.db.settings.planner.includeYellow and not reagent.isRecipe
    row.needOrange:SetShown(isSplit)
    row.needTilde:SetShown(isSplit)
    row.needYellow:SetShown(isSplit)
    if isSplit then
        row.cells[1]:SetText("")
        row.needOrange:SetText(Config.COLOR_SKILL_ORANGE .. reagent.orangeCount .. "|r | ")
        row.needYellow:SetText(tostring(reagent.yellowCount))
    else
        row.cells[1]:SetText(tostring(reagent.count))
    end
    row.cells[2]:SetText(tostring(have))
    if toBuy == 0 then
        row.cells[3]:SetText(Config.COLOR_PROFIT .. "0|r")
        row.cells[4]:SetText(MoneyText(0))
        return
    end
    row.cells[3]:SetText(tostring(toBuy))
    row.cells[4]:SetText(MoneyText(reagent.price and reagent.price * toBuy or nil))
end

-- What the plan still has to buy: { { itemID, quantity }, ... }, the most needed first.
local function ReagentsToBuy()
    local list = {}
    for _, reagent in ipairs(PlanReagents()) do
        local toBuy = math.ceil(reagent.count - ns.Utilities.ItemCount(reagent.itemID))
        -- a bound recipe item is never on the auction house: not in the shopping list
        if toBuy > 0 and reagent.problem ~= "bound" then
            table.insert(list, { itemID = reagent.itemID, quantity = toBuy })
        end
    end
    return list
end

-- "To Shopping list": the reagents to buy go to a shopping list of Auctionator
-- named after the plan ("PRR: Leatherworking 1-300"), every item an exact
-- search with its quantity; a list of the same plan is replaced.
local function SendToShoppingList()
    local entries = {}
    local unnamed = 0
    for _, reagent in ipairs(ReagentsToBuy()) do
        local name = ItemNames.ItemPlainName(reagent.itemID)
        if name then
            table.insert(entries, { name = name, quantity = reagent.quantity })
        else
            unnamed = unnamed + 1   -- the server has not sent the item yet
        end
    end
    if #entries == 0 then return end
    local settings = ns.db.settings.planner
    local listName = Text("planner.shopping_list_name",
        ns.GameData.ProfessionName(ns.Components.PlannerWindow.CurrentProfession()), settings.fromSkill, settings.toSkill)
    if not ns.Utilities.CreateAuctionatorShoppingList(listName, entries) then
        ns.Utilities.Print(Text("planner.shopping_list_failed"))
        return
    end
    local message = Text("planner.shopping_list_done", listName, #entries)
    if unnamed > 0 then
        message = message .. " " .. Text("planner.shopping_list_unnamed", unnamed)
    end
    ns.Utilities.Print(message)
end

local function ShowShoppingButtonTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(Text("planner.to_shopping_list"))
    GameTooltip:AddLine(Text("planner.to_shopping_list_hint"), 1, 1, 1, true)
    GameTooltip:Show()
end

-- Shown with Auctionator only, enabled while the plan has something to buy.
local function RefreshShoppingButton(hasToBuy)
    local button = tab.shoppingButton
    local hasAuctionator = ns.Utilities.HasAuctionatorShoppingLists()
    button:SetShown(hasAuctionator)
    tab.reagentsTitle:SetPoint("RIGHT", hasAuctionator and button or tab.reagentsBlock,
        hasAuctionator and "LEFT" or "RIGHT", hasAuctionator and -GAP or 0, 0)
    button:SetEnabled(hasToBuy)
end

local function RefreshReagents()
    local reagents = PlanReagents()
    local buyCost = 0
    local unknown = 0
    local hasToBuy = false
    for _, reagent in ipairs(reagents) do
        local toBuy = math.max(0, reagent.count - ns.Utilities.ItemCount(reagent.itemID))
        hasToBuy = hasToBuy or toBuy > 0
        if toBuy > 0 and reagent.price then
            buyCost = buyCost + reagent.price * toBuy
        elseif toBuy > 0 then
            unknown = unknown + 1
        end
    end
    local title = Text("planner.reagents_title",
        ns.Components.PlannerWindow.MoneyText(buyCost, REAGENTS_TITLE_COIN_OFFSET))
    if unknown > 0 then
        title = title .. "  " .. Config.COLOR_HINT .. Text("planner.missing", unknown) .. "|r"
    end
    tab.reagentsTitle:SetText(title)
    RefreshShoppingButton(hasToBuy)
    tab.reagents:Fill(#reagents, function(row, index)
        FillReagentRow(row, reagents[index])
    end)
end

local function RefreshView()
    purchases = CountPurchases()
    tab.summary:SetText(SummaryText())
    local steps = result and result.steps or {}
    tab.list:Fill(#steps, function(row, index)
        FillRow(row, steps[index])
    end)
    RefreshReagents()
end

-- "Auto", "Yellow skill-up chance: 10%" ... for the select of the chance of yellow crafts.
local function YellowChanceChoices()
    local choices = { { value = SkillPlanner.YELLOW_CHANCE_AUTO, text = Text("planner.yellow_chance_auto") } }
    for _, percent in ipairs(YELLOW_CHANCES) do
        table.insert(choices, { value = percent, text = Text("planner.yellow_chance", percent) })
    end
    return choices
end

-- The lines of the header under the skill row: the selects (the recipes, the
-- chance of yellow crafts while they are on), then the skill bar (a learned
-- profession), then the summary.
local function LayoutHeader()
    local top = -SECOND_ROW
    tab.skillBar:SetPoint("TOPLEFT", 0, SKILL_BAR_TOP + top)
    if tab.skillBar:IsShown() then
        top = top - SKILL_BAR_ROW
    end
    tab.summary:SetPoint("TOPLEFT", 0, SUMMARY_TOP + top)
end

-- The chance select only with yellow recipes on.
local function RefreshYellowChance()
    local isShown = ns.db.settings.planner.includeYellow == true
    tab.yellowChanceSelect:SetShown(isShown)
    tab.yellowChanceSelect:Refresh()
    LayoutHeader()
end

local isSettingCurrentSkill = false   -- the From field is being filled by the code

-- "From profession": the skill of the character in the profession goes into
-- the From field, the cap of it into the To field, which can not be typed in
-- then; a profession not
-- learned (the client does not know a skill) has no checkbox (and no skill
-- bar), the field stays as it is.
local function ApplyCurrentSkill(profession)
    local settings = ns.db.settings.planner
    local skill, maxSkill = ns.GameData.ProfessionSkill(profession)
    -- the checkbox only for a profession the character has learned
    tab.currentSkillCheckbox:SetShown(skill ~= nil)
    local current = settings.fromCurrentSkill and skill
    -- a learned profession: the skill bar of the profession window on the
    -- next line, the summary under it
    local isBarShown = skill ~= nil
    tab.skillBar:SetShown(isBarShown)
    if isBarShown then
        tab.skillBar:SetSkill(profession, ns.GameData.ProfessionName(profession), skill, maxSkill or skill)
    end
    LayoutHeader()
    tab.fromInput:SetEnabled(not current)
    tab.toInput:SetEnabled(not current)
    if not current then return end
    -- From -- the skill, To -- the cap of the profession (it goes up with the next rank)
    settings.fromSkill = math.max(1, current)
    settings.toSkill = math.max(settings.fromSkill, maxSkill or settings.toSkill)
    isSettingCurrentSkill = true
    tab.fromInput:SetText(tostring(settings.fromSkill))
    tab.toInput:SetText(tostring(settings.toSkill))
    isSettingCurrentSkill = false
end

-- Plan again with what is in the fields now; a range that is not one yet
-- (being typed, from >= to) leaves the plan empty.
local function Calculate()
    if isSettingCurrentSkill then return end
    local profession = ns.Components.PlannerWindow.CurrentProfession()
    -- the fields change while the tab is still being built
    if not (tab and tab.reagents and profession) then return end
    local settings = ns.db.settings.planner
    ApplyCurrentSkill(profession)
    settings.fromSkill = ReadSkill(tab.fromInput, settings.fromSkill)
    settings.toSkill = ReadSkill(tab.toInput, settings.toSkill)
    result = nil
    if settings.fromSkill < settings.toSkill then
        result = SkillPlanner.Plan({
            profession = profession,
            from = settings.fromSkill,
            to = settings.toSkill,
            includeYellow = settings.includeYellow,
            yellowChance = settings.yellowChance,
            isRecipeAvailable = LevelingTab.IsRecipeAvailable,
            recipePrice = RecipePrice,
            algorithm = settings.algorithm,
            forced = plan.forced,
            prices = plan.prices,
        })
    end
    RefreshView()
    tab.picker:Refresh()
end

local function AskPrice(recipe)
    local current = plan.prices[recipe.spellID]
    ns.UI.Prompt(Text("planner.price_prompt", ItemNames.RecipeName(recipe) or LOADING_NAME), function(text)
        local copper = ns.Utilities.ParseMoney(text)
        if not copper then
            ns.Utilities.Print(Text("planner.price_invalid", text))
            return
        end
        plan.prices[recipe.spellID] = copper
        Calculate()
    end, {
        initialText = current and ns.Utilities.PlainMoney(current) or "",
    })
end

local function ShowStepMenu(row)
    local recipe = row.step.recipe
    local spellID = recipe.spellID
    local items = {
        {
            text = Text("planner.restrict"),
            onClick = function()
                SkillPlanner.SetBanned(spellID, true)
                plan.forced[spellID] = nil
                Calculate()
            end,
        },
    }
    if plan.forced[spellID] then
        table.insert(items, {
            text = Text("planner.unforce"),
            onClick = function()
                plan.forced[spellID] = nil
                Calculate()
            end,
        })
    else
        table.insert(items, {
            text = Text("planner.force"),
            onClick = function()
                plan.forced[spellID] = true
                Calculate()
            end,
        })
    end
    table.insert(items, {
        text = Text("planner.set_price"),
        onClick = function()
            AskPrice(recipe)
        end,
    })
    if plan.prices[spellID] then
        table.insert(items, {
            text = Text("planner.reset_price"),
            onClick = function()
                plan.prices[spellID] = nil
                Calculate()
            end,
        })
    end
    ns.UI.ShowMenu(row, ItemNames.RecipeName(recipe) or LOADING_NAME, items)
end

-- Right click -- the menu of the step; Shift+click with the chat open -- the link.
-- Right click -- the menu of the step; Shift+click -- the link into the chat;
-- a click on a learned recipe opens it in the profession window.
local function OnRowClick(row, mouseButton)
    if mouseButton == "RightButton" then
        ShowStepMenu(row)
        return
    end
    local recipe = row.step.recipe
    if ns.Utilities.InsertChatLink("item", recipe.item) or ns.Utilities.InsertChatLink("spell", recipe.spellID) then
        return
    end
    if row.isKnown then
        local ok, why = ns.GameData.OpenRecipe(recipe.spellID, recipe.profession)
        if not ok and why then
            ns.Utilities.Print(why)
        end
    end
end

-- A row of Reagents to buy: the tooltip of its item, its price per item with
-- the date of the scan; a recipe the auction house has none of says so.
local function ShowReagentTooltip(row)
    local reagent = row.reagent
    if not reagent then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(reagent.itemID)
    ns.Wowhead.SetHovered("item", reagent.itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(Text("planner.price_each"),
        ns.Components.PlannerWindow.DatedMoneyText(AuctionPrices.Get(reagent.itemID), reagent.itemID), 1, 0.82, 0, 1, 1, 1)
    if reagent.problem then
        GameTooltip:AddLine(" ")
        AddRecipeProblemLine(reagent.problem, ItemNames.ItemName(reagent.itemID) or LOADING_NAME)
    end
    GameTooltip:Show()
end

local function ShowRowTooltip(row)
    local step = row.step
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ItemNames.RecipeName(step.recipe) or LOADING_NAME)
    GameTooltip:AddLine(ns.SkillRange.Text(step.recipe) or "", 1, 1, 1)
    GameTooltip:AddLine(Text("planner.step_points", step.orangePoints, step.yellowPoints), 1, 1, 1)
    if row.isKnown then
        GameTooltip:AddLine(Text("planner.open_recipe_hint"), KNOWN_TINT[1], KNOWN_TINT[2], KNOWN_TINT[3], true)
    end
    local recipeItemName = step.recipe.recipeItem and (ItemNames.ItemName(step.recipe.recipeItem) or LOADING_NAME)
    if row.isRecipeToBuy then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Text("planner.recipe_to_buy", recipeItemName), 1, 0.82, 0, true)
        if row.recipeProblem then
            AddRecipeProblemLine(row.recipeProblem, recipeItemName)
        end
    end
    if row.recipePrice then
        GameTooltip:AddDoubleLine(Text("planner.recipe_price_in_cost"), ns.Components.PlannerWindow.MoneyText(row.recipePrice),
            1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(Config.COLOR_HINT .. Text("planner.step_hint") .. "|r", 1, 1, 1, true)
    GameTooltip:Show()
end

local function ToggleForce(recipe)
    local spellID = recipe.spellID
    if plan.forced[spellID] then
        plan.forced[spellID] = nil
    else
        plan.forced[spellID] = true
        SkillPlanner.SetBanned(spellID, false)
    end
    Calculate()
end

local function ToggleRestrict(recipe)
    local spellID = recipe.spellID
    local isRestricted = not SkillPlanner.IsBanned(spellID)
    SkillPlanner.SetBanned(spellID, isRestricted)
    if isRestricted then
        plan.forced[spellID] = nil
    end
    Calculate()
end


-- A field left: it shows the skill the plan uses.
local function NormalizeSkillFields()
    local settings = ns.db.settings.planner
    tab.fromInput:SetText(tostring(settings.fromSkill))
    tab.toInput:SetText(tostring(settings.toSkill))
end

local function CreateSkillInput(parent)
    local input = ns.UI.Input(parent, {
        width = SKILL_INPUT_WIDTH,
        height = BUTTON_HEIGHT,
        onChange = Calculate,
    })
    input:HookScript("OnEditFocusLost", NormalizeSkillFields)
    return input
end

-- The tab inside parent (the content area of the planner window).
function LevelingTab.Create(parent)
    local settings = ns.db.settings.planner
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    -- the blocks; ApplyLayout puts them in their places
    tab.split = CreateFrame("Frame", nil, tab)
    tab.picker = ns.Components.RecipePicker.Create(tab, {
        isForced = function(spellID)
            return plan.forced[spellID] == true
        end,
        isRestricted = SkillPlanner.IsBanned,
        onToggleForce = ToggleForce,
        onToggleRestrict = ToggleRestrict,
    })

    -- the skill range and the summary
    local header = CreateFrame("Frame", nil, tab)
    header:SetHeight(HEADER_HEIGHT)
    tab.header = header

    local skillLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skillLabel:SetPoint("TOPLEFT", 0, -4)
    skillLabel:SetText(Text("planner.skill"))

    tab.fromInput = CreateSkillInput(header)
    tab.fromInput:SetPoint("LEFT", skillLabel, "RIGHT", GAP + 4, 0)
    tab.fromInput:SetMaxLetters(SKILL_MAX_LETTERS)
    tab.fromInput:SetText(tostring(settings.fromSkill))

    local dash = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dash:SetPoint("LEFT", tab.fromInput, "RIGHT", GAP, 0)
    dash:SetText("-")

    tab.toInput = CreateSkillInput(header)
    tab.toInput:SetPoint("LEFT", dash, "RIGHT", GAP + 4, 0)
    tab.toInput:SetMaxLetters(SKILL_MAX_LETTERS)
    tab.toInput:SetText(tostring(settings.toSkill))

    tab.yellowCheckbox = ns.UI.Checkbox(header, {
        text = Text("planner.include_yellow"),
        checked = settings.includeYellow,
        tooltip = Text("planner.include_yellow_hint"),
        onChange = function(checked)
            settings.includeYellow = checked
            RefreshYellowChance()
            Calculate()
        end,
    })
    tab.yellowCheckbox:SetPoint("LEFT", tab.toInput, "RIGHT", GAP + 4, 0)

    -- with yellow recipes: the chance of a point from their crafts (Auto -- the formula of the game)
    tab.yellowChanceSelect = ns.UI.Select(header, {
        width = YELLOW_CHANCE_SELECT_WIDTH,
        height = YELLOW_CHANCE_SELECT_HEIGHT,
        choices = YellowChanceChoices,
        selected = function()
            return settings.yellowChance
        end,
        onChange = function(value)
            settings.yellowChance = value
            Calculate()
        end,
    })
    -- the second row: [the recipes] [the chance of yellow crafts]
    tab.recipeSourceSelect = ns.UI.Select(header, {
        width = RECIPE_SOURCE_SELECT_WIDTH,
        height = YELLOW_CHANCE_SELECT_HEIGHT,
        choices = LevelingTab.RecipeSources,
        selected = function()
            return settings.recipeSource
        end,
        onChange = function(value)
            settings.recipeSource = value
            Calculate()
        end,
    })
    tab.recipeSourceSelect:SetPoint("TOPLEFT", header, "TOPLEFT", 0, SECOND_ROW_TOP)
    tab.recipeSourceSelect:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Text("planner.recipe_source_title"))
        GameTooltip:AddLine(Text("planner.recipe_source_hint"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab.recipeSourceSelect:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    tab.yellowChanceSelect:SetPoint("LEFT", tab.recipeSourceSelect, "RIGHT", GAP, 0)
    tab.yellowChanceSelect:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Text("planner.yellow_chance_title"))
        GameTooltip:AddLine(Text("planner.yellow_chance_hint"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab.yellowChanceSelect:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    tab.currentSkillCheckbox = ns.UI.Checkbox(header, {
        text = Text("planner.from_current_skill"),
        checked = settings.fromCurrentSkill,
        tooltip = Text("planner.from_current_skill_hint"),
        onChange = function(checked)
            settings.fromCurrentSkill = checked
            Calculate()
        end,
    })
    tab.currentSkillCheckbox:SetPoint("LEFT", tab.yellowCheckbox.label, "RIGHT", CHECKBOX_GAP, 0)

    tab.skillBar = ns.UI.ProfessionBar(header)
    tab.skillBar:SetPoint("TOPLEFT", 0, SKILL_BAR_TOP)
    tab.skillBar:Hide()
    -- a click opens the profession window
    tab.skillBar:EnableMouse(true)
    tab.skillBar:SetScript("OnMouseUp", function()
        local profession = ns.Components.PlannerWindow.CurrentProfession()
        local ok, why = ns.GameData.OpenProfession(profession)
        if not ok and why then
            ns.Utilities.Print(why)
        end
    end)
    tab.skillBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(Text("planner.open_profession_hint"))
        GameTooltip:Show()
    end)
    tab.skillBar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    tab.summary = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tab.summary:SetPoint("TOPLEFT", 0, SUMMARY_TOP)
    tab.summary:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    tab.summary:SetJustifyH("LEFT")
    tab.summary:SetSpacing(SUMMARY_LINE_SPACING)
    RefreshYellowChance()

    -- the steps of the plan
    tab.list = ns.UI.ColumnList(tab, {
        title = Text("planner.recipe"),
        columns = {
            { title = Text("planner.skill_column"), width = SKILL_COLUMN_WIDTH },
            { title = Text("planner.crafts"), width = CRAFTS_COLUMN_WIDTH },
            { title = Text("planner.cost"), width = Config.PLANNER_MONEY_COLUMN_WIDTH },
            { title = "", width = CRAFT_COLUMN_WIDTH },
        },
        rowHeight = STEP_ROW_HEIGHT,
        iconSize = STEP_ICON_SIZE,
        iconTop = true,
        onIconClick = function(iconButton)
            ns.Components.PlannerWindow.OpenItem(iconButton)
        end,
        onCreateRow = function(row)
            -- the reagents of the step: counts for all its crafts
            ns.Components.PlannerWindow.CreateReagentIcons(row)
            -- a learned recipe that makes an item: Craft -- the crafts of the step
            row.craftButton = ns.Components.CraftButton.Create(row)
            row.craftButton:SetPoint("RIGHT", row.cells[4], "RIGHT", 0, 0)
            -- a learned recipe: the row faintly tinted (a click opens the recipe)
            row.knownTint = row:CreateTexture(nil, "BORDER")
            row.knownTint:SetAllPoints()
            row.knownTint:SetColorTexture(KNOWN_TINT[1], KNOWN_TINT[2], KNOWN_TINT[3], KNOWN_TINT_ALPHA)
            row.knownTint:Hide()
            -- a recipe to buy that is not on the auction house: the row red
            row.notOnSaleTint = row:CreateTexture(nil, "BORDER")
            row.notOnSaleTint:SetAllPoints()
            row.notOnSaleTint:SetColorTexture(NOT_ON_SALE_TINT[1], NOT_ON_SALE_TINT[2], NOT_ON_SALE_TINT[3],
                NOT_ON_SALE_TINT_ALPHA)
            row.notOnSaleTint:Hide()
            -- not learned: the item that teaches it (a pattern, plans) at the end of
            -- the reagents when the base knows it, a click opens it in the item window
            row.recipeButton = ns.UI.IconButton(row, {
                size = RECIPE_BUTTON_SIZE,
                onClick = ns.Components.PlannerWindow.OpenItem,
            })
            row.recipeButton:SetPoint("BOTTOMRIGHT", row.cells[1], "BOTTOMLEFT", -RECIPE_BUTTON_GAP, 0)
            row.recipeButton:HookScript("OnEnter", function()
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(Config.COLOR_HINT .. Text("planner.recipe_item_hint") .. "|r", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            local skillCell = row.cells[1]
            row.orangeBar = row:CreateTexture(nil, "ARTWORK")
            row.orangeBar:SetColorTexture(ORANGE_COLOR[1], ORANGE_COLOR[2], ORANGE_COLOR[3])
            row.orangeBar:SetHeight(SKILL_BAR_HEIGHT)
            row.orangeBar:SetPoint("TOPLEFT", skillCell, "BOTTOMLEFT", 0, -1)
            row.yellowBar = row:CreateTexture(nil, "ARTWORK")
            row.yellowBar:SetColorTexture(YELLOW_COLOR[1], YELLOW_COLOR[2], YELLOW_COLOR[3])
            row.yellowBar:SetHeight(SKILL_BAR_HEIGHT)
            row.yellowBar:SetPoint("TOPLEFT", row.orangeBar, "TOPRIGHT", 0, 0)
            row.yellowBar:SetPoint("TOPRIGHT", skillCell, "BOTTOMRIGHT", 0, -1)
        end,
        onEnter = ShowRowTooltip,
        onClick = OnRowClick,
    })

    -- the reagents of the whole plan: what to buy
    local reagentsBlock = CreateFrame("Frame", nil, tab)
    tab.reagentsBlock = reagentsBlock
    tab.reagentsTitle = reagentsBlock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.reagentsTitle:SetHeight(REAGENTS_TITLE_HEIGHT)
    tab.reagentsTitle:SetPoint("TOPLEFT")
    tab.reagentsTitle:SetPoint("RIGHT")
    tab.reagentsTitle:SetJustifyH("LEFT")
    -- in the same line, at its right end: the reagents to a shopping list of Auctionator
    tab.shoppingButton = ns.UI.Button(reagentsBlock, {
        text = Text("planner.to_shopping_list"),
        width = SHOPPING_BUTTON_WIDTH,
        height = SHOPPING_BUTTON_HEIGHT,
        onClick = SendToShoppingList,
    })
    tab.shoppingButton:SetPoint("RIGHT", reagentsBlock, "TOPRIGHT", 0, -REAGENTS_TITLE_HEIGHT / 2)
    tab.shoppingButton:SetScript("OnEnter", ShowShoppingButtonTooltip)
    tab.shoppingButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    -- a disabled button gets no OnEnter: the motion script keeps the hint
    if tab.shoppingButton.SetMotionScriptsWhileDisabled then
        tab.shoppingButton:SetMotionScriptsWhileDisabled(true)
    end
    tab.reagents = ns.UI.ColumnList(reagentsBlock, {
        title = Text("planner.reagent"),
        columns = {
            { title = Text("planner.need"), width = NEED_COLUMN_WIDTH, tooltip = Text("planner.need_hint") },
            { title = Text("planner.have"), width = COUNT_COLUMN_WIDTH },
            { title = Text("planner.buy"), width = COUNT_COLUMN_WIDTH },
            { title = Text("planner.cost"), width = Config.PLANNER_MONEY_COLUMN_WIDTH },
        },
        rowHeight = REAGENT_ROW_HEIGHT,
        iconSize = REAGENT_ICON_SIZE,
        onIconClick = function(iconButton)
            ns.Components.PlannerWindow.OpenItem(iconButton)
        end,
        onCreateRow = CreateNeedTexts,
        -- the whole row: the item tooltip with its price, as on its icon
        onEnter = ShowReagentTooltip,
        onLeave = function()
            ns.Wowhead.SetHovered(nil)
        end,
        -- Shift+click on a row: the link of the reagent into the chat
        onClick = function(row)
            if row.reagent then
                ns.Utilities.InsertChatLink("item", row.reagent.itemID)
            end
        end,
    })
    tab.reagents:SetPoint("TOPLEFT", tab.reagentsTitle, "BOTTOMLEFT", 0, -TITLE_TABLE_GAP)
    tab.reagents:SetPoint("BOTTOMRIGHT")

    LevelingTab.ApplyLayout()
    return tab
end

-- The places of the blocks for each layout (settings.planner.layout); every
-- table is TITLE_TABLE_GAP under its title (the summary, "Reagents to buy").
--   1 -- the plan and the reagents on the left, one over the other; the recipes on the right
--   2 -- the plan, the reagents and the recipes side by side
--   3 -- the plan on the left at full height; the reagents and the recipes on the right
local function PlaceStepsUnderSummary()
    tab.list:SetPoint("TOPLEFT", tab.summary, "BOTTOMLEFT", 0, -TITLE_TABLE_GAP)
end

local LAYOUTS = {
    function()
        tab.picker:SetPoint("TOPRIGHT")
        tab.picker:SetPoint("BOTTOMRIGHT")
        tab.picker:SetWidth(SIDE_WIDTH)
        tab.header:SetPoint("TOPLEFT")
        tab.header:SetPoint("RIGHT", tab.picker, "LEFT", -GAP * 2, 0)
        tab.reagentsBlock:SetPoint("BOTTOMLEFT")
        tab.reagentsBlock:SetPoint("RIGHT", tab.picker, "LEFT", -GAP * 2, 0)
        tab.reagentsBlock:SetHeight(REAGENTS_HEIGHT + REAGENTS_TITLE_HEIGHT + TITLE_TABLE_GAP)
        PlaceStepsUnderSummary()
        tab.list:SetPoint("BOTTOMRIGHT", tab.reagentsBlock, "TOPRIGHT", 0, REAGENTS_TITLE_GAP)
    end,
    function()
        tab.picker:SetPoint("TOPRIGHT")
        tab.picker:SetPoint("BOTTOMRIGHT")
        tab.picker:SetWidth(SIDE_WIDTH)
        -- the room left of the recipes, split in two for the steps and the reagents
        tab.split:SetPoint("TOPLEFT")
        tab.split:SetPoint("BOTTOMRIGHT", tab.picker, "BOTTOMLEFT", -GAP * 2, 0)
        tab.header:SetPoint("TOPLEFT")
        tab.header:SetPoint("RIGHT", tab.split, "RIGHT", 0, 0)
        PlaceStepsUnderSummary()
        tab.list:SetPoint("BOTTOMRIGHT", tab.split, "BOTTOM", -GAP, 0)
        -- the table of the reagents level with the steps, its title above it
        tab.reagentsBlock:SetPoint("TOPLEFT", tab.list, "TOPRIGHT", GAP * 2, REAGENTS_TITLE_HEIGHT + TITLE_TABLE_GAP)
        tab.reagentsBlock:SetPoint("BOTTOMRIGHT", tab.split, "BOTTOMRIGHT", 0, 0)
    end,
    function()
        tab.reagentsBlock:SetPoint("TOPRIGHT")
        tab.reagentsBlock:SetWidth(WIDE_SIDE_WIDTH)
        tab.reagentsBlock:SetPoint("BOTTOM", tab, "CENTER", 0, GAP)
        tab.picker:SetPoint("TOPRIGHT", tab, "RIGHT", 0, -GAP)
        tab.picker:SetPoint("BOTTOMRIGHT")
        tab.picker:SetWidth(WIDE_SIDE_WIDTH)
        tab.header:SetPoint("TOPLEFT")
        tab.header:SetPoint("RIGHT", tab.reagentsBlock, "LEFT", -GAP * 2, 0)
        PlaceStepsUnderSummary()
        tab.list:SetPoint("BOTTOMRIGHT", tab.picker, "BOTTOMLEFT", -GAP * 2, 0)
    end,
}

-- Puts the blocks in the places of the chosen layout.
function LevelingTab.ApplyLayout()
    if not tab then return end
    local place = LAYOUTS[ns.db.settings.planner.layout] or LAYOUTS[1]
    for _, block in ipairs({ tab.picker, tab.header, tab.list, tab.reagentsBlock, tab.split }) do
        block:ClearAllPoints()
    end
    place()
    tab.picker:Show()
end

local ALGORITHMS = { "standard", "smart" }

-- The algorithms of the plan for the select of the window: { value, text }.
-- The choices of the recipe select: { value, text }.
function LevelingTab.RecipeSources()
    local choices = {}
    for _, source in ipairs(RECIPE_SOURCES) do
        table.insert(choices, { value = source, text = Text("planner.recipe_source_" .. source) })
    end
    return choices
end

function LevelingTab.Algorithms()
    local choices = {}
    for _, algorithm in ipairs(ALGORITHMS) do
        table.insert(choices, { value = algorithm, text = Text("planner.algorithm_" .. algorithm) })
    end
    return choices
end

-- The layouts for the select of the window: { value, text }.
function LevelingTab.Layouts()
    local choices = {}
    for index in ipairs(LAYOUTS) do
        table.insert(choices, { value = index, text = Text("planner.layout_" .. index) })
    end
    return choices
end

function LevelingTab.Refresh()
    if not tab then return end
    NormalizeSkillFields()
    Calculate()   -- the prices may have changed
end

-- The skills of the character changed: the skill bar and a plan from the
-- current skill follow.
function LevelingTab.OnSkillsChanged()
    if tab and tab:IsVisible() then
        Calculate()
    end
end

-- The bags changed: the "have" and "buy" columns follow, and the recipes to
-- buy (a pattern put in the bags is not to buy any more).
function LevelingTab.OnBagsChanged()
    if not (tab and tab:IsVisible() and result) then return end
    -- a pattern in the bags makes its recipe usable for "trainer" / "auction": plan again
    if ns.db.settings.planner.recipeSource ~= "all" then
        Calculate()
        return
    end
    RefreshView()
end

-- Another profession: a clean plan.
function LevelingTab.OnProfessionChanged()
    plan = { forced = {}, prices = {} }
    result = nil
end
end)
