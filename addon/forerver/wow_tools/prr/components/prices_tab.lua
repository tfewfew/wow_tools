WoWTools.prr.RegisterSource(function(...)
-- prices_tab.lua -- the "Prices" tab of the planner window:
--
--   [Search recipes and reagents       ]       [Scan missing]  [Scan]
--   [$][=========        87% (650 of 747 checked), prices: 312         ]
--   Open the auction house and press Scan   Last scan: 12.10 14:30
--   Recipe ^                         Cost      Sells for   Profit     Scanned
--   [icon] Lesser Healing Potion [55][80][90][100] [pattern]   12s 40c   30s         17s 60c    12.10 14:30
--          [reagent][reagent]
--
-- Scan looks up the reagents and the results of every profession on the
-- open auction house (services/auction_scan_service.lua), the bar shows how
-- complete the prices of all of them are; the table (the chosen profession) shows the
-- reagents of every recipe, the craft cost, the price of the result, the profit
-- (dataflows/craft_planner.lua) and the oldest scan among its items. A click
-- on a column title sorts by it; the search keeps the recipes whose name (or
-- the name of their result) has the text, "[Name]" -- exactly that name: a
-- Shift+click on an item while the field has the focus puts it so. Hover a reagent: its price and when it was read.
-- "Scan missing" looks up only the items the auction house has not answered for yet.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local AuctionPrices = ns.Dataflows.AuctionPrices
local AuctionScan = ns.Services.AuctionScan
local CraftPlanner = ns.Dataflows.CraftPlanner
local ItemNames = ns.Dataflows.ItemNames
local Text = ns.Localization.Text

local PricesTab = {}
ns.Components.PricesTab = PricesTab

local SCAN_BUTTON_WIDTH = 110
local SCAN_MISSING_BUTTON_WIDTH = 150
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 8
local SEARCH_LEFT_INSET = 6      -- the field's frame is drawn outside of it on the left
local BAR_TOP = -34              -- the bar: the scan, or how complete the prices are
local STATUS_TOP = -62           -- one line under the bar (its frame sticks out by 2)
local LIST_TOP = -82
local ROW_HEIGHT = 36       -- the icon and 2 pixels above and under it
local RESULT_ICON_SIZE = 32
local DATE_COLUMN_WIDTH = 74
local PROGRESS_BAR_HEIGHT = 19
local PROGRESS_ICON_SIZE = 24
local PROGRESS_LEFT = PROGRESS_ICON_SIZE + 10   -- the icon sticks out on the left of the bar
local COVERAGE_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local LOADING_NAME = "..."
local PATTERN_ICON_SIZE = 16     -- the pattern / plans / formula after the name
local PATTERN_ICON_GAP = 4
local NAME_COLUMN_GAP = 12       -- the name to the first money column (as in ui/column_list)

local tab = nil
local scanProgress = nil   -- { done, total, found, isFinished } of the last scan
-- items of the profession the running scan does not look up (Scan missing:
-- the ones checked before) -- the bar counts them as done from the start
local scanSkipped = 0
local searchText = ""

local function DateText(seenAt)
    if not seenAt then
        return ns.Components.PlannerWindow.MoneyText(nil)
    end
    return date(Config.PLANNER_DATE_FORMAT, seenAt)
end


-- The price of every reagent and of the result.
local function ShowRowTooltip(row)
    local PlannerWindow = ns.Components.PlannerWindow
    local evaluation = row.evaluation
    local recipe = evaluation.recipe
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ItemNames.RecipeName(recipe) or LOADING_NAME)
    for _, reagent in ipairs(recipe.reagents) do
        local name = ItemNames.ItemName(reagent[1]) or LOADING_NAME
        local price = AuctionPrices.Get(reagent[1])
        local total = price and price * reagent[2] or nil
        GameTooltip:AddDoubleLine(Text("tooltip.reagent", reagent[2], name), PlannerWindow.DatedMoneyText(total, reagent[1]),
            1, 1, 1, 1, 1, 1)
    end
    if recipe.item then
        local name = ItemNames.ItemName(recipe.item) or LOADING_NAME
        GameTooltip:AddDoubleLine(Text("tooltip.reagent", recipe.count, name), PlannerWindow.DatedMoneyText(evaluation.sale, recipe.item),
            0.6, 0.8, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(Text("planner.cost"), PlannerWindow.MoneyText(evaluation.cost), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(Text("planner.sale"), PlannerWindow.MoneyText(evaluation.sale), 1, 0.82, 0, 1, 1, 1)
    if evaluation.cut then
        GameTooltip:AddDoubleLine(Text("planner.cut", ns.db.settings.planner.auctionCut),
            "-" .. PlannerWindow.MoneyText(evaluation.cut), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(Text("planner.profit"), PlannerWindow.ProfitText(evaluation.profit), 1, 0.82, 0, 1, 1, 1)
    if evaluation.missing > 0 then
        GameTooltip:AddLine(Config.COLOR_HINT .. Text("planner.missing", evaluation.missing) .. "|r")
    end
    GameTooltip:Show()
end

-- Shift+click with the chat open: the link of the result.
local function OnRowClick(row)
    local recipe = row.evaluation.recipe
    if not ns.Utilities.InsertChatLink("item", recipe.item) then
        ns.Utilities.InsertChatLink("spell", recipe.spellID)
    end
end

-- The pattern the recipe is learned from, right after the end of the name
-- text (the name keeps room for it); none for a trainer recipe.
local function FillPatternIcon(row, recipe)
    local icon = row.patternIcon
    if not recipe.recipeItem then
        icon:Hide()
        return
    end
    icon:SetItem(recipe.recipeItem)
    local textWidth = math.min(row.name:GetStringWidth() or 0, row.name:GetWidth() or 0)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", row.name, "LEFT", textWidth + PATTERN_ICON_GAP, 0)
    icon:Show()
end

-- The pattern icon of a row: the item tooltip with its price, a click opens it.
local function CreatePatternIcon(row)
    row.patternIcon = ns.UI.IconButton(row, {
        size = PATTERN_ICON_SIZE,
        onClick = ns.Components.PlannerWindow.OpenItem,
    })
    ns.Components.PlannerWindow.AddPriceTooltip(row.patternIcon)
    -- the name ends before the icon, so a long one is cut and the icon stays clear of the money
    row.name:SetPoint("RIGHT", row.cells[1], "LEFT", -(NAME_COLUMN_GAP + PATTERN_ICON_GAP + PATTERN_ICON_SIZE), 0)
end

local function FillRow(row, evaluation)
    local PlannerWindow = ns.Components.PlannerWindow
    local recipe = evaluation.recipe
    row.evaluation = evaluation
    PlannerWindow.SetRecipeIcon(row.icon, recipe)
    -- the name, then [learn][yellow][green][gray]
    local title = PlannerWindow.RecipeTitle(recipe)
    local levels = ns.SkillRange.Text(recipe)
    if levels then
        title = title .. " " .. levels
    end
    row.name:SetText(title)
    FillPatternIcon(row, recipe)
    PlannerWindow.FillReagentIcons(row, recipe, 1)
    local cost = evaluation.cost
    if evaluation.missing > 0 then
        cost = nil
    end
    row.cells[1]:SetText(PlannerWindow.MoneyText(cost))
    row.cells[2]:SetText(PlannerWindow.MoneyText(evaluation.sale))
    row.cells[3]:SetText(PlannerWindow.ProfitText(evaluation.profit))
    row.cells[4]:SetText(DateText(evaluation.scannedAt))
end

local function RefreshList()
    local profession = ns.Components.PlannerWindow.CurrentProfession()
    local evaluations = {}
    if profession then
        local lowerText = ns.Utilities.Lower(searchText)
        for _, evaluation in ipairs(CraftPlanner.Rows(profession)) do
            if CraftPlanner.Matches(evaluation, lowerText) then
                table.insert(evaluations, evaluation)
            end
        end
        local sort = ns.db.settings.planner.pricesSort
        CraftPlanner.Sort(evaluations, sort.key, sort.ascending)
    end
    tab.list:Fill(#evaluations, function(row, index)
        FillRow(row, evaluations[index])
    end)
end

local function StatusText()
    if not AuctionScan.IsAvailable() then
        return Text("planner.unavailable")
    end
    if scanProgress then
        local isStopped = scanProgress.isFinished and scanProgress.done < scanProgress.total
        if isStopped then
            return Text("planner.stopped", scanProgress.done, scanProgress.total, scanProgress.found)
        end
        if scanProgress.isFinished then
            return Text("planner.finished", scanProgress.found, scanProgress.total)
        end
        return Text("planner.scanning", scanProgress.done, scanProgress.total)
    end
    local text = Text("planner.hint_open")
    if AuctionScan.IsAuctionHouseOpen() then
        text = Text("planner.hint_ready")
    end
    local lastScan = CraftPlanner.LastScanTime(nil)
    if lastScan then
        text = text .. "   " .. Config.COLOR_HINT
            .. Text("planner.last_scan", date(Config.PLANNER_DATE_FORMAT, lastScan)) .. "|r"
    end
    return text
end

local function RefreshControls()
    local profession = ns.Components.PlannerWindow.CurrentProfession()
    local isRunning = AuctionScan.IsRunning()
    if isRunning then
        tab.scanButton:SetText(Text("planner.stop"))
    else
        tab.scanButton:SetText(Text("planner.scan"))
    end
    local canStart = AuctionScan.IsAuctionHouseOpen()
    tab.scanButton:SetEnabled(isRunning or canStart)
    tab.scanMissingButton:SetEnabled(canStart and not isRunning)
    tab.status:SetText(StatusText())

    -- no scan going (and no end of one fading): the bar shows how complete
    -- the prices of all the professions are
    local bar = tab.progressBar
    local isScanShown = isRunning or bar:IsFinishing()
    if isScanShown then return end
    local coverage = CraftPlanner.Coverage(nil)
    local percent = math.floor(coverage.checked / math.max(coverage.total, 1) * 100)
    bar:Start()
    bar:SetIcon(COVERAGE_ICON)
    bar:SetProgress(coverage.checked, coverage.total)
    bar:SetText(Text("planner.coverage", percent, coverage.checked, coverage.total, coverage.priced))
end

-- The bar follows the scan: the item looked up, how far -- of all the items
-- of all the professions, the skipped ones done already (Scan missing starts where
-- the prices are); at the end it flashes and fades out, then shows how
-- complete the prices are again.
local function UpdateProgressBar(done, total, isFinished)
    local bar = tab.progressBar
    if not bar:IsShown() or bar:IsFinishing() then
        bar:Start()
    end
    done = done + scanSkipped
    total = total + scanSkipped
    bar:SetProgress(done, total)
    local itemID = AuctionScan.CurrentItem()
    bar:SetItem(itemID)
    if isFinished then
        bar:SetText(StatusText())
        bar:PlayFinish(RefreshControls)
        return
    end
    -- a browse reads the whole auction house: the bar follows it (the size of
    -- the last one, or a batch ahead the first time), the text -- the prices found
    local listed, expected = AuctionScan.BrowseProgress()
    if listed then
        if expected <= listed then
            expected = listed + Config.AUCTION_BROWSE_BATCH
        end
        bar:SetProgress(listed, expected)
        local percent = math.floor(listed / expected * 100)
        bar:SetText(Text("planner.browse_progress", percent, listed, done, total))
        return
    end
    local percent = math.floor(done / math.max(total, 1) * 100)
    bar:SetText(Text("planner.scanning_progress", percent, done, total))
end

local function OnScanProgress(done, total, found, isFinished)
    if not tab then return end
    scanProgress = { done = done, total = total, found = found, isFinished = isFinished }
    UpdateProgressBar(done, total, isFinished)
    RefreshControls()
    -- the table follows the prices as they come, the whole of it at the end
    if isFinished or done % Config.PLANNER_REFRESH_EVERY_ITEMS == 0 then
        RefreshList()
    end
end

-- The items of every profession; onlyMissing -- just the ones with no answer yet.
local function StartScan(onlyMissing)
    if AuctionScan.IsRunning() then return end
    local items = CraftPlanner.ItemsToScan(nil, onlyMissing)
    scanSkipped = #CraftPlanner.ItemsToScan(nil) - #items
    AuctionScan.Start(items, OnScanProgress)
    RefreshControls()
end

-- The tab inside parent (the content area of the planner window).
function PricesTab.Create(parent)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    tab.scanButton = ns.UI.Button(tab, {
        width = SCAN_BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            if AuctionScan.IsRunning() then
                AuctionScan.Stop()
                return
            end
            StartScan(false)
        end,
    })
    tab.scanButton:SetPoint("TOPRIGHT")

    tab.scanMissingButton = ns.UI.Button(tab, {
        text = Text("planner.scan_missing"),
        width = SCAN_MISSING_BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
        onClick = function()
            StartScan(true)
        end,
    })
    tab.scanMissingButton:SetPoint("RIGHT", tab.scanButton, "LEFT", -BUTTON_GAP, 0)

    tab.search = ns.UI.SearchBox(tab, {
        placeholder = Text("planner.search"),
        onChange = function(text)
            if text == searchText then return end
            searchText = text
            RefreshList()
        end,
    })
    tab.search:SetPoint("TOPLEFT", SEARCH_LEFT_INSET, -1)
    tab.search:SetPoint("RIGHT", tab.scanMissingButton, "LEFT", -BUTTON_GAP * 2, 0)

    tab.status = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tab.status:SetPoint("TOPLEFT", 0, STATUS_TOP)
    tab.status:SetPoint("RIGHT")
    tab.status:SetJustifyH("LEFT")
    tab.status:SetWordWrap(false)

    tab.progressBar = ns.UI.ProgressBar(tab, {
        height = PROGRESS_BAR_HEIGHT,
        iconSize = PROGRESS_ICON_SIZE,
    })
    tab.progressBar:SetPoint("TOPLEFT", PROGRESS_LEFT, BAR_TOP)
    tab.progressBar:SetPoint("RIGHT", -4, 0)

    tab.list = ns.UI.ColumnList(tab, {
        title = Text("planner.recipe"),
        titleKey = "name",
        columns = {
            { title = Text("planner.cost"), width = Config.PLANNER_MONEY_COLUMN_WIDTH, key = "cost" },
            { title = Text("planner.sale"), width = Config.PLANNER_MONEY_COLUMN_WIDTH, key = "sale" },
            { title = Text("planner.profit"), width = Config.PLANNER_MONEY_COLUMN_WIDTH, key = "profit" },
            { title = Text("planner.scanned"), width = DATE_COLUMN_WIDTH, key = "scanned" },
        },
        rowHeight = ROW_HEIGHT,
        iconSize = RESULT_ICON_SIZE,
        iconTop = true,
        onCreateRow = function(row)
            ns.Components.PlannerWindow.CreateReagentIcons(row)
            CreatePatternIcon(row)
        end,
        onIconClick = function(iconButton)
            ns.Components.PlannerWindow.OpenItem(iconButton)
        end,
        onEnter = ShowRowTooltip,
        onClick = OnRowClick,
        sort = {
            descendingFirst = { sale = true, profit = true, scanned = true },
            state = function()
                return ns.db.settings.planner.pricesSort
            end,
            onSort = function(key, ascending)
                ns.db.settings.planner.pricesSort = { key = key, ascending = ascending }
                RefreshList()
            end,
        },
    })
    tab.list:SetPoint("TOPLEFT", 0, LIST_TOP)
    tab.list:SetPoint("BOTTOMRIGHT")
    return tab
end

-- Does the search field wait for an item (it has the focus)?
function PricesTab.IsSearchFocused()
    return tab ~= nil and tab:IsVisible() and tab.search:HasFocus()
end

-- A Shift+clicked item into the search field: "[Light Leather]", an exact search.
function PricesTab.SearchItem(itemID)
    local name = ItemNames.ItemName(itemID)
    if not name then return end
    tab.search:SetText("[" .. name .. "]")
end

function PricesTab.Refresh()
    if not tab then return end
    RefreshControls()
    RefreshList()
end

-- Another profession: the progress of the old one is not shown.
function PricesTab.OnProfessionChanged()
    if AuctionScan.IsRunning() then
        AuctionScan.Stop()
    end
    scanProgress = nil
end

-- The auction house opened or closed.
function PricesTab.OnAuctionHouseChanged()
    if not tab then return end
    RefreshControls()
end
end)
