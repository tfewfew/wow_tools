WoWTools.prr.RegisterSource(function(...)
-- item_window.lua -- the window from the minimap button: an item slot and
-- every recipe of the item in it (components/recipe_list.lua).
--
-- An item gets into the slot by dragging it onto the slot or the window, by
-- Shift+click on it in the bags while the window is open (events/bag_click.lua),
-- or by a click on an icon in the list. "History" opens the items and searches
-- looked at before (components/history_panel.lua), "Clear" empties the slot and
-- the search. The star after the item name adds it to the favorites, shown by
-- "Favorites" at the left of the window (components/favorites_panel.lua).
-- The search field looks through every recipe by name; with an item in the
-- slot it narrows that item's recipes. Empty slot and search -- every recipe.
--
-- Tabs under the bottom edge: Recipes (all of the above, frame.recipesPage),
-- Prices and Planner -- the craft planner (components/planner_window.lua).
-- The open tab is kept in settings.window.tab. The Recipes tab has the size
-- the player gave the window; the planner tabs -- the size their layout needs.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local Text = ns.Localization.Text

local ItemWindow = {}
ns.Components.ItemWindow = ItemWindow

local FRAME_NAME = "PRRItemWindow"
local HEADER_HEIGHT = 32         -- the title band of the border
local PADDING = 14
local SLOT_SIZE = 40
local SLOT_TEXT_GAP = 10
local SEARCH_TOP_GAP = 8         -- between the slot and the search field
local SEARCH_LEFT_INSET = 6      -- the field's frame is drawn outside of it on the left
local LIST_TOP_GAP = 8           -- between the search field and the list
local CLEAR_BUTTON_WIDTH = 70     -- "Clear" under the icon buttons, right of the slot
local CLEAR_BUTTON_HEIGHT = 18
local CLEAR_BUTTON_GAP = 6        -- between the icon buttons and "Clear"
local TOOL_BUTTON_SIZE = 22       -- the icon buttons: favorites, history
local TOOL_BUTTON_GAP = 8         -- their slot frames stick out, as on the action bar
local HISTORY_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local FAVORITES_ATLAS = "auctionhouse-icon-favorite"   -- the star of the favorite marks
local FAVORITES_ICON = "Interface\\Icons\\INV_Misc_Note_01"   -- without that atlas
local TITLE_STAR_SIZE = 14
local TITLE_STAR_GAP = 6
local HINT_TOP_GAP = 2
local HINT_MAX_LINES = 2
local REFRESH_DELAY_SECONDS = 0.3   -- names coming from the server one by one: redraw once

local RECIPES_TAB = "recipes"

local frame = nil
local resizeBounds = nil   -- the resizable options of the panel: the grip reads its minimum on every drag
local refreshPending = false
local searchText = ""

local function SavePosition(window)
    local point, _, relativePoint, x, y = window:GetPoint()
    ns.db.settings.window.position = { point, relativePoint, x, y }
end

local function IsRecipesTab()
    return ns.db.settings.window.tab == RECIPES_TAB
end

-- after a resize the window is anchored by its top left corner: the position changed too
local function SaveSize(window)
    if IsRecipesTab() then
        ns.db.settings.window.size = { window:GetWidth(), window:GetHeight() }
    end
    SavePosition(window)
end

-- The size the player gave the window, not below the minimum.
local function RecipesSize()
    local size = ns.db.settings.window.size
    if not size then
        return Config.WINDOW_WIDTH, Config.WINDOW_HEIGHT
    end
    return math.max(Config.WINDOW_MIN_WIDTH, size[1]), math.max(Config.WINDOW_MIN_HEIGHT, size[2])
end

-- How to put an item in: the click chosen in the settings (if any, and not
-- Shift+click itself), Shift+click while the window is open, dragging.
local function SlotHint()
    local binding = ns.db.settings.openBinding
    local hasOwnClick = binding ~= "NONE" and binding ~= "SHIFT_CLICK"
        and ns.Constants.OPEN_BINDINGS_BY_ID[binding] ~= nil
    if hasOwnClick then
        return Text("window.slot_hint_binding", Text("options.open_binding.values." .. binding))
    end
    return Text("window.slot_hint")
end

-- Only what found recipes goes to the history.
local function HasFoundRecipes()
    return frame ~= nil and frame.list:FoundCount() > 0
end

-- The favorites changed: the title star, the stars of the list, the panels
-- the bags and the loot window.
function ItemWindow.OnFavoritesChanged()
    ItemWindow.Refresh(true)
    ns.Components.FavoritesPanel.Refresh()
    ns.Components.HistoryPanel.Refresh()
    ns.Components.BagStars.RefreshAll()
    ns.Components.LootGlow.RefreshAll()
end

-- The name is as wide as its text, but not wider than the room before the
-- leftmost button (minus the star): a long one ends with "...". The star is
-- anchored to its right end.
local function LayoutTitle()
    if not frame then return end
    local nameLeft = frame.itemName:GetLeft()
    local buttonsLeft = frame.favoritesButton:GetLeft()
    if not (nameLeft and buttonsLeft) then return end
    local room = buttonsLeft - nameLeft - SLOT_TEXT_GAP - TITLE_STAR_SIZE - TITLE_STAR_GAP
    local textWidth = frame.itemName:GetStringWidth()
    if frame.itemName.GetUnboundedStringWidth then
        textWidth = frame.itemName:GetUnboundedStringWidth()
    end
    frame.itemName:SetWidth(math.max(1, math.min(textWidth, room)))
end

local function AcceptDroppedItem()
    local itemID = ns.UI.TakeCursorItem()
    if itemID then
        ItemWindow.SetItem(itemID)
    end
end

local CreateTabs

local function Create()
    local settings = ns.db.settings.window
    local width, height = RecipesSize()
    resizeBounds = {
        minWidth = Config.WINDOW_MIN_WIDTH,
        minHeight = Config.WINDOW_MIN_HEIGHT,
        onResized = SaveSize,
    }

    frame = ns.UI.Panel(FRAME_NAME, UIParent, {
        width = width,
        height = height,
        title = ns.Constants.ADDON_TITLE,
        gameSkin = true,
        onMoved = SavePosition,
        resizable = resizeBounds,
    })
    local position = settings.position
    frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    -- Escape closes the window
    table.insert(UISpecialFrames, FRAME_NAME)
    -- an item dropped anywhere on the window
    frame:SetScript("OnReceiveDrag", AcceptDroppedItem)
    frame:SetScript("OnMouseUp", AcceptDroppedItem)

    -- the Recipes tab: everything below is on this page, over the whole window
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints(frame)
    frame.recipesPage = page

    frame.slot = ns.UI.ItemSlot(page, {
        size = SLOT_SIZE,
        emptyTooltip = SlotHint,
        clearTooltip = Text("window.slot_clear"),
        onItem = ItemWindow.SetItem,
        onClear = function()
            ItemWindow.SetItem(nil)
        end,
    })
    frame.slot:SetPoint("TOPLEFT", PADDING, -HEADER_HEIGHT)

    frame.itemName = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.itemName:SetPoint("TOPLEFT", frame.slot, "TOPRIGHT", SLOT_TEXT_GAP, -2)
    -- right of the slot: [favorites] [history], "Clear" under them
    frame.historyButton = ns.UI.IconToolButton(page, {
        size = TOOL_BUTTON_SIZE,
        icon = HISTORY_ICON,
        tooltip = Text("window.history"),
        onClick = function()
            ns.Components.HistoryPanel.Toggle(page, ItemWindow.OpenHistoryEntry)
        end,
    })
    frame.historyButton:SetPoint("TOPRIGHT", -PADDING, -HEADER_HEIGHT)

    frame.favoritesButton = ns.UI.IconToolButton(page, {
        size = TOOL_BUTTON_SIZE,
        atlas = FAVORITES_ATLAS,
        icon = FAVORITES_ICON,
        tooltip = Text("window.favorites"),
        onClick = function()
            ns.Components.FavoritesPanel.Toggle(page, {
                onSelect = function(itemID)
                    frame.search:ClearFocus()
                    frame.search:SetText("")
                    searchText = ""
                    ItemWindow.SetItem(itemID)
                end,
                onChanged = ItemWindow.OnFavoritesChanged,
            })
        end,
    })
    frame.favoritesButton:SetPoint("RIGHT", frame.historyButton, "LEFT", -TOOL_BUTTON_GAP, 0)

    frame.clearButton = ns.UI.Button(page, {
        text = Text("window.clear"),
        width = CLEAR_BUTTON_WIDTH,
        height = CLEAR_BUTTON_HEIGHT,
        onClick = function()
            ItemWindow.ClearSearch()
        end,
    })
    frame.clearButton:SetPoint("TOPRIGHT", frame.historyButton, "BOTTOMRIGHT", 0, -CLEAR_BUTTON_GAP)

    -- the name stops before the star, the star stands right after the name
    -- no right anchor: LayoutTitle gives the name the width of its text, at most
    -- the room before the buttons, and the star stands at its right end
    frame.favoriteToggle = ns.UI.FavoriteToggle(page, {
        size = TITLE_STAR_SIZE,
        tooltipOn = Text("favorites.remove"),
        tooltipOff = Text("favorites.add"),
        onClick = function()
            local itemID = ns.db.settings.window.itemID
            if not itemID then return end
            ns.Dataflows.Favorites.Toggle(itemID)
            ItemWindow.OnFavoritesChanged()
        end,
    })
    frame.itemName:SetJustifyH("LEFT")
    frame.itemName:SetWordWrap(false)
    frame.favoriteToggle:SetPoint("LEFT", frame.itemName, "RIGHT", TITLE_STAR_GAP, 0)
    -- a resize changes the room for the name
    frame:HookScript("OnSizeChanged", LayoutTitle)
    frame:HookScript("OnShow", function()
        C_Timer.After(0, LayoutTitle)   -- the window has its size only once it is drawn
    end)

    frame.hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    -- under the name, as wide as the room before the buttons, at most two lines:
    -- it stays within the height of the slot
    frame.hint:SetPoint("TOPLEFT", frame.itemName, "BOTTOMLEFT", 0, -HINT_TOP_GAP)
    frame.hint:SetPoint("RIGHT", frame.favoritesButton, "LEFT", -SLOT_TEXT_GAP, 0)   -- the leftmost button
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetJustifyV("TOP")
    frame.hint:SetWordWrap(true)
    frame.hint:SetMaxLines(HINT_MAX_LINES)

    frame.search = ns.UI.SearchBox(page, {
        placeholder = Text("window.search"),
        onChange = function(text)
            if text == searchText then return end
            searchText = text
            ItemWindow.Refresh(false)
        end,
        onCommit = function(text)
            if not HasFoundRecipes() then return end
            ns.Dataflows.SearchHistory.AddSearch(text)
            ns.Components.HistoryPanel.Refresh()
        end,
    })
    -- the buttons right of the slot are taller than it: the search field goes under both
    local buttonsHeight = TOOL_BUTTON_SIZE + CLEAR_BUTTON_GAP + CLEAR_BUTTON_HEIGHT
    local searchTop = SEARCH_TOP_GAP + math.max(0, buttonsHeight - SLOT_SIZE)
    frame.search:SetPoint("TOPLEFT", frame.slot, "BOTTOMLEFT", SEARCH_LEFT_INSET, -searchTop)
    frame.search:SetPoint("RIGHT", -PADDING, 0)

    frame.list = ns.Components.RecipeList.Create(page, {
        onOpenItem = ItemWindow.SetItem,
    })
    frame.list.area:SetPoint("TOPLEFT", frame.slot, "BOTTOMLEFT", 0, -(searchTop + frame.search:GetHeight() + LIST_TOP_GAP))
    frame.list.area:SetPoint("BOTTOMRIGHT", -(PADDING + ns.UI.SCROLL_AREA_BAR_SPACE), PADDING)

    CreateTabs()
    ItemWindow.Refresh(false)
end

-- The open tab, a known one.
local function CurrentTab()
    local tab = ns.db.settings.window.tab
    for _, plannerTab in ipairs(ns.Components.PlannerWindow.Tabs()) do
        if plannerTab.id == tab then
            return tab
        end
    end
    return RECIPES_TAB
end

-- Recipes -- the size the player gave the window, resizable; the planner tabs
-- -- the size of their layout, as the planner window had.
function ItemWindow.ApplySize()
    if not frame then return end
    if IsRecipesTab() then
        resizeBounds.minWidth = Config.WINDOW_MIN_WIDTH
        resizeBounds.minHeight = Config.WINDOW_MIN_HEIGHT
        frame:SetSize(RecipesSize())
    else
        local width = ns.Components.PlannerWindow.Width()
        resizeBounds.minWidth = width
        resizeBounds.minHeight = Config.PLANNER_HEIGHT
        frame:SetSize(width, Config.PLANNER_HEIGHT)
    end
    if frame.resizeGrip then
        frame.resizeGrip:SetShown(IsRecipesTab())
    end
end

-- Show the tab of settings.window.tab: its page, its size.
local function ApplyTab()
    local tab = CurrentTab()
    ns.db.settings.window.tab = tab
    frame.tabBar:Select(tab)
    frame.recipesPage:SetShown(tab == RECIPES_TAB)
    ItemWindow.ApplySize()
    if tab == RECIPES_TAB then
        ns.Components.PlannerWindow.Hide()
        LayoutTitle()
    else
        ns.Components.PlannerWindow.Show(frame, tab)
    end
end

function CreateTabs()
    local tabs = { { id = RECIPES_TAB, text = Text("window.tab_recipes") } }
    for _, tab in ipairs(ns.Components.PlannerWindow.Tabs()) do
        table.insert(tabs, tab)
    end
    frame.tabBar = ns.UI.TabBar(frame, {
        namePrefix = FRAME_NAME .. "Tab",
        tabs = tabs,
        onSelect = function(tab)
            ItemWindow.ShowTab(tab)
        end,
    })
    ApplyTab()
end

-- Open the window on a tab: "recipes" | "prices" | "planner".
function ItemWindow.ShowTab(tab)
    ns.db.settings.window.tab = tab
    if not frame then
        Create()
    end
    frame:Show()
    ApplyTab()
end

function ItemWindow.IsShown()
    return frame ~= nil and frame:IsShown()
end

function ItemWindow.Toggle()
    if not frame then
        Create()
        frame:Show()
        return
    end
    frame:SetShown(not frame:IsShown())
end

-- The window on the last planner tab; open there already -- closed.
function ItemWindow.TogglePlanner()
    local isOnPlanner = ItemWindow.IsShown() and not IsRecipesTab()
    if isOnPlanner then
        frame:Hide()
        return
    end
    ItemWindow.ShowTab(ns.db.settings.planner.tab or "prices")
end

-- An item to look at always opens the Recipes tab.
local function ShowItem(itemID)
    ns.db.settings.window.itemID = itemID
    if not frame then
        Create()
    end
    frame:Show()
    if not IsRecipesTab() then
        ItemWindow.ShowTab(RECIPES_TAB)
    end
    ItemWindow.Refresh(false)
end

-- itemID -- the item to show (it goes to the history if it has recipes), nil -- empty the slot.
function ItemWindow.SetItem(itemID)
    ShowItem(itemID)
    if itemID and HasFoundRecipes() then
        ns.Dataflows.SearchHistory.AddItem(itemID)
        ns.Components.HistoryPanel.Refresh()
    end
end

-- The search field gets the text (its OnTextChanged redraws the list).
local function SetSearchText(text)
    frame.search:SetText(text)
    searchText = text
end

-- Empty slot and search: every recipe.
function ItemWindow.ClearSearch()
    if not frame then return end
    frame.search:ClearFocus()
    SetSearchText("")
    ShowItem(nil)
end

-- A click in the history: an item -- into the slot with no search, a search --
-- into the field with the slot empty.
function ItemWindow.OpenHistoryEntry(entry)
    frame.search:ClearFocus()
    if entry.kind == "item" then
        SetSearchText("")
        ItemWindow.SetItem(entry.itemID)
        return
    end
    ns.db.settings.window.itemID = nil
    SetSearchText(entry.text)
    ns.Dataflows.SearchHistory.AddSearch(entry.text)
    ns.Components.HistoryPanel.Refresh()
    ItemWindow.Refresh(false)
end

-- keepPosition -- the same item again: keep the list scrolled where it is.
function ItemWindow.Refresh(keepPosition)
    if not frame then return end
    local itemID = ns.db.settings.window.itemID
    frame.slot:SetItem(itemID)
    frame.hint:SetText(SlotHint())   -- the click in the settings may have changed
    frame.list:Show({ itemID = itemID, search = searchText }, keepPosition)

    if itemID then
        frame.itemName:SetText(ns.Dataflows.ItemNames.ItemName(itemID) or "...")
    else
        frame.itemName:SetText("")
    end

    -- the star right after the name, filled for a favorite
    local isFavorite = ns.Dataflows.Favorites.IsFavorite(itemID)
    ns.UI.SetFavoriteStar(frame.slot, isFavorite)
    frame.favoriteToggle:SetShown(itemID ~= nil)
    frame.favoriteToggle:SetFavorite(isFavorite)
    LayoutTitle()
end

-- Item names come from the server one by one: redraw once a moment later.
function ItemWindow.RefreshSoon()
    if refreshPending or not ItemWindow.IsShown() then return end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY_SECONDS, function()
        refreshPending = false
        ItemWindow.Refresh(true)
        ns.Components.HistoryPanel.Refresh()
        ns.Components.FavoritesPanel.Refresh()
    end)
end
end)
