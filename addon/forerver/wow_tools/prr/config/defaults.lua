WoWTools.prr.RegisterSource(function(...)
-- defaults.lua -- tooltip limits, scan speed and default saved settings.

local ADDON, ns = ...

local Config = {}
ns.Config = Config

-- tooltip (components/item_tooltip.lua)
Config.TOOLTIP_RECIPES_PER_PROFESSION = 5   -- "reagent for" names per profession; Shift shows all
Config.TOOLTIP_CRAFTED_RECIPES = 3          -- recipes that create the item; Shift shows all
Config.COLOR_HEADER = "|cffffd100"
Config.COLOR_PROFESSION = "|cff66bbff"
Config.COLOR_TEXT = "|cffd8d8d8"
Config.COLOR_HINT = "|cff8f8f8f"
Config.COLOR_IGNORED = "|cffff6060"   -- the mark of an ignored recipe in developer mode
Config.IGNORED_ROW_ALPHA = 0.5
-- the skill levels of a recipe (utilities/skill_range.lua), the colors of the profession window
Config.COLOR_SKILL_ORANGE = "|cffff8040"
Config.COLOR_SKILL_YELLOW = "|cffffff00"
Config.COLOR_SKILL_GREEN = "|cff40bf40"
Config.COLOR_SKILL_GRAY = "|cff808080"

-- item window (components/item_window.lua)
Config.WINDOW_WIDTH = 520
Config.WINDOW_HEIGHT = 480
Config.WINDOW_MIN_WIDTH = 360
Config.WINDOW_MIN_HEIGHT = 240
Config.SIDE_PANEL_WIDTH = 260   -- the history and favorites panels
Config.HISTORY_LIMIT = 1000   -- items and searches kept in the history
Config.PROFESSION_HEADER_HEIGHT = 24   -- the collapsible profession bar, as in the quest log
Config.PROFESSION_HEADER_GAP = 3
Config.RECIPE_ROW_HEIGHT = 46
Config.RECIPE_ROW_PADDING = 4
Config.RECIPE_ROW_GAP = 8          -- between the result icon and the title / reagents
Config.RECIPE_ICON_SIZE = 38
Config.REAGENT_ICON_SIZE = 22
Config.REAGENT_ICON_GAP = 4
Config.RECIPE_ITEM_ICON_SIZE = 30   -- the pattern / plans of the recipe, at the right edge

-- craft planner (components/planner_window.lua, services/auction_scan_service.lua)
Config.PLANNER_WIDTH = 880
-- the width of the window for each layout of the plan tab: the side-by-side ones need more
Config.PLANNER_LAYOUT_WIDTHS = { 880, 1220, 1060 }
Config.PLANNER_HEIGHT = 540
-- skill lines the craft planner leaves out (no select, no scan): the gathering ones
-- (Herbalism, Mining, Skinning, Fishing -- their Forever camping recipes), Survival,
-- Comprehension, Poisons
Config.PLANNER_HIDDEN_PROFESSIONS = { [182] = true, [186] = true, [393] = true, [356] = true,
    [142] = true, [3012] = true, [40] = true }
Config.PLANNER_DATE_FORMAT = "%d.%m %H:%M"   -- when a price was read
Config.PLANNER_ROW_HEIGHT = 24
Config.PLANNER_ICON_SIZE = 20
Config.PLANNER_MONEY_COLUMN_WIDTH = 96   -- cost, sale, profit
Config.PLANNER_REFRESH_EVERY_ITEMS = 10   -- the list is redrawn while the scan goes
Config.AUCTION_SEARCH_TIMEOUT_SECONDS = 4   -- no answer from the auction house: skip the item
Config.AUCTION_BROWSE_BATCH = 500           -- the items of one browse batch: the bar of the first browse looks one batch ahead
Config.AUCTION_BROWSE_MIN_ITEMS = 30        -- a shorter list is looked up item by item, not by a browse of the whole house
Config.COLOR_PROFIT = "|cff40ff40"
Config.COLOR_LOSS = "|cffff5050"

-- in-game scan of recipes (services/recipe_scan_service.lua)
Config.SCAN_TICK_SECONDS = 0.1
Config.NAME_WARMUP_ITEMS_PER_TICK = 50   -- names asked from the server per tick at login
Config.SCAN_SPELLS_PER_TICK = 200
Config.SCAN_REPORT_PERCENT = 10   -- progress in chat every 10 percent
-- /prr scan full: spell id ranges where recipes live (by the ids of the base:
-- original recipes up to ~45000, seasonal ~430000-462000, Forever 1213000-1320000)
Config.FULL_SCAN_RANGES = {
    { 1, 50000 },
    { 425000, 470000 },
    { 1200000, 1340000 },
}

-- PRRDB on a fresh install; missing keys are added on every load
Config.defaults = {
    settings = {
        -- the language of the addon's texts: "auto" -- the client's, or "en" / "ru"
        -- (utilities/localization.lua; another one takes a reload of the UI)
        language = "auto",
        showTooltip = true,      -- recipe lines in item tooltips at all
        showCraftedBy = true,    -- "Crafted by" block in the tooltip
        showReagentFor = true,   -- "Reagent for" block in the tooltip
        showAuctionPrice = true, -- the auction price of the planner's scan in the tooltip
        tooltipHiddenProfessions = {},   -- [skill line] = true: its recipes are not in tooltips
        copyLink = true,         -- Ctrl+C over an item: a Wowhead link to copy
        lootGlow = true,         -- favorite items in the loot window glow
        developer = false,       -- /prr dev: spell ids on recipe rows, right click -- the fix menu
        openBinding = "ALT_CLICK",   -- the click on an item that opens the window, ns.Constants.OPEN_BINDINGS
        minimap = { hide = false, minimapPos = 210 },   -- LibDBIcon keeps the position here
        planner = {
            profession = nil,   -- the skill line chosen in the planner
            tab = "prices",     -- the last planner tab of the item window: "prices" | "planner"
            layout = 1,         -- the layout of the plan tab (components/leveling_tab.lua LAYOUTS)
            fromSkill = 1,      -- the leveling plan: from this skill...
            fromCurrentSkill = false,   -- ...or from the skill the character has in the profession
            toSkill = 300,      -- ...to this one
            includeYellow = false,   -- yellow recipes count too (a point is not sure)
            recipeSource = "all",    -- the recipes the plan uses: "all" | "trainer" (+ learned) | "auction" (+ on sale)
            yellowChance = 0,        -- percent: the chance of a point from a yellow craft set by the player, 0 -- by the formula of the game
            autoReplaceEnchant = false,
            enchantTargets = {},     -- [enchant spell id] = { guid, itemID }: the item its Craft button enchants
            lastEnchantTarget = nil, -- the item chosen last, tried for an enchant with none of its own   -- "Replace the enchant?" answered yes while the profession window is open
            algorithm = "standard",  -- "standard" | "smart": the items the plan crafts are used by its later steps
            banned = {},        -- [recipe spell id] = true: never used in plans
            pricesSort = { key = "profit", ascending = false },   -- the prices table
            auctionCut = 5,     -- percent the auction house keeps of a sale (neutral: 15)
        },
        window = {
            position = { "CENTER", "CENTER", 0, 0 },
            size = nil,     -- { width, height } after the player resized the window
            itemID = nil,   -- the item in the slot
            tab = "recipes", -- the open tab: "recipes" | "prices" | "planner" (components/item_window.lua)
            collapsed = {}, -- ["all:<profession>"] = true/false: the "all recipes" view, components/recipe_list.lua
        },
    },
    -- [recipe spell id] = { item, profession, count, reagents = { itemID, count, itemID, count } }:
    -- recipes read from the client by the scan; scripts/build_database.py copies them into the base
    scanned = {},
    -- items and searches of the item window, newest first (dataflows/search_history.lua)
    history = {},
    -- favorite item ids, newest first (dataflows/favorites.lua)
    favorites = {},
    -- [item id] = { price = lowest buyout per item in copper (nil -- none on sale), time }:
    -- the auction house scans of the planner (dataflows/auction_prices.lua)
    auctionPrices = {},
    -- [name-realm] = { [recipe spell id] = true }: the recipes each character has
    -- learned, seen in its profession window (utilities/game_data.lua)
    knownRecipes = {},
    -- how many items the last full browse of the auction house had: the scale of the bar of the next one
    auctionBrowseSize = 0,
    -- [recipe spell id] = hand fix made in developer mode (services/recipe_fix_service.lua);
    -- scripts/build_database.py merges them into data/fixes.json and database/fixes.lua
    fixes = {},
    -- item names seen in the game (dataflows/item_names.lua), dropped only when the
    -- game version or the client's language changes:
    -- { version = "1.60.1.70009 ruRU", items = { [item id] = { name, quality } } }
    itemNames = { version = nil, items = {} },
    -- the "Other addons" page (shared/other_addons): the language chosen on it
    otherAddons = {},
}
end)
