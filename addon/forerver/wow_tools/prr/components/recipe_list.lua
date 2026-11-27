WoWTools.prr.RegisterSource(function(...)
-- recipe_list.lua -- the recipes of the item window in a scrolling list,
-- grouped by profession under collapsible headers (as in the quest log).
--
-- What it shows depends on the query { itemID, search }:
--   * an item -- the recipes that craft it and the ones it is a reagent for;
--     a search text narrows them to the ones with it in the name or in the name
--     of a reagent (the item comes first);
--   * no item, a search text -- the reagents with that text in the name (a click
--     opens one), the recipes with it in the name, then the other recipes that
--     use one of those reagents; the found reagents are underlined in the rows.
--     The reagents are under a collapsible header like the professions' (kept in
--     settings.window.collapsed["section:reagents"]); without
--     settings.window.searchReagents only recipe names are searched;
--   * neither -- every recipe of the base, all professions collapsed.
-- With a filter every profession opens by itself whenever the filter changes.
--
-- A profession can hold hundreds of recipes, so only the rows in view exist:
-- entries get their place once, frames are put on the visible ones on every
-- scroll (recipe rows -- components/recipe_row.lua).

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local RecipeIndex = ns.Dataflows.RecipeIndex
local RecipeRow = ns.Components.RecipeRow
local ItemRow = ns.Components.ItemRow
local Text = ns.Localization.Text

local RecipeList = {}
ns.Components.RecipeList = RecipeList

local SECTION_HEIGHT = 28
local HINT_HEIGHT = 24
local TEXT_LEFT = 4

-- the height an entry takes in the list
local ENTRY_HEIGHTS = {
    section = SECTION_HEIGHT,
    hint = HINT_HEIGHT,
    profession = Config.PROFESSION_HEADER_HEIGHT + Config.PROFESSION_HEADER_GAP,
    recipe = Config.RECIPE_ROW_HEIGHT,
    item = Config.ITEM_ROW_HEIGHT,
}

-- Collapsed professions while a filter (an item or a search) is on: a new
-- filter opens every profession again, so these are dropped when it changes.
-- Without a filter ("all") the choice is saved in settings.window.collapsed, and
-- so is the reagents header of a search ("section:reagents").
local filteredCollapsed = {}

local REAGENTS_SECTION_KEY = "section:reagents"

-- "Recipes (12):" -> "Recipes (12)": a section title as a header or a contents line.
local function WithoutColon(text)
    local fullwidthColon = "\239\188\154"   -- the Chinese texts end with it
    if text:sub(-#fullwidthColon) == fullwidthColon then
        return text:sub(1, -#fullwidthColon - 1)
    end
    return (text:gsub("%s*:%s*$", ""))
end

local function CollapsedStore(key)
    if key:find("^all:") or key:find("^section:") then
        return ns.db.settings.window.collapsed
    end
    return filteredCollapsed
end

-- Is the profession group collapsed: what the player chose, else the mode's default.
local function IsCollapsed(key, collapsedByDefault)
    local chosen = CollapsedStore(key)[key]
    if chosen == nil then
        return collapsedByDefault
    end
    return chosen
end

-- mode -- "crafted" | "reagent" | "search" | "search_reagent" | "all": each keeps its own collapsed professions.
local function AddGroups(entries, recipes, mode, collapsedByDefault)
    for _, group in ipairs(RecipeIndex.GroupByProfession(recipes)) do
        local key = mode .. ":" .. group.profession
        local collapsed = IsCollapsed(key, collapsedByDefault)
        table.insert(entries, {
            kind = "profession",
            text = Text("window.profession_count", group.name, #group.recipes),
            key = key,
            collapsed = collapsed,
            recipeCount = #group.recipes,
        })
        if not collapsed then
            for _, recipe in ipairs(group.recipes) do
                table.insert(entries, { kind = "recipe", recipe = recipe })
            end
        end
    end
end

-- The recipes of the list with the text in the name, then the others of the list
-- that use one of the reagents (a set of item ids).
local function ByNameAndReagents(recipes, search, reagentSet)
    local byName = RecipeIndex.FilterByName(recipes, search)
    local inByName = {}
    for _, recipe in ipairs(byName) do
        inByName[recipe] = true
    end
    local byReagent = {}
    for _, recipe in ipairs(RecipeIndex.FilterByReagents(recipes, reagentSet)) do
        if not inByName[recipe] then
            table.insert(byReagent, recipe)
        end
    end
    return byName, byReagent
end

local function Narrow(recipes, search, reagentSet)
    if not recipes or search == "" then
        return recipes or {}
    end
    local byName, byReagent = ByNameAndReagents(recipes, search, reagentSet)
    for _, recipe in ipairs(byReagent) do
        table.insert(byName, recipe)
    end
    return byName
end

local function ItemEntries(itemID, search, reagentSet)
    local entries = {}
    local craftedBy = Narrow(RecipeIndex.CraftedBy(itemID), search, reagentSet)
    local reagentFor = Narrow(RecipeIndex.ReagentFor(itemID), search, reagentSet)
    if #craftedBy > 0 then
        table.insert(entries, { kind = "section", text = Text("tooltip.crafted_by") })
        AddGroups(entries, craftedBy, "crafted", false)
    end
    if #reagentFor > 0 then
        table.insert(entries, { kind = "section", text = Text("window.reagent_for", #reagentFor) })
        AddGroups(entries, reagentFor, "reagent", false)
    end
    if #entries == 0 then
        local hintKey = "window.no_recipes"
        if search ~= "" then
            hintKey = "window.nothing_found"
        end
        table.insert(entries, { kind = "hint", text = Text(hintKey) })
    end
    return entries
end

local function SearchEntries(search, reagents, reagentSet)
    local entries = {}
    local byName, byReagent = ByNameAndReagents(RecipeIndex.AllRecipes(), search, reagentSet)
    if #reagents + #byName + #byReagent == 0 then
        table.insert(entries, { kind = "hint", text = Text("window.nothing_found") })
        return entries
    end
    if #reagents > 0 then
        -- a header like a profession's: the same bar, the same plus / minus
        local collapsed = IsCollapsed(REAGENTS_SECTION_KEY, false)
        table.insert(entries, {
            kind = "profession",
            text = WithoutColon(Text("window.found_reagents", #reagents)),
            key = REAGENTS_SECTION_KEY,
            collapsed = collapsed,
            recipeCount = #reagents,
            isTopLevel = true,   -- in the contents it stands with the sections
        })
        if not collapsed then
            for _, itemID in ipairs(reagents) do
                table.insert(entries, { kind = "item", itemID = itemID })
            end
        end
    end
    if #byName > 0 then
        table.insert(entries, { kind = "section", text = Text("window.found_recipes", #byName) })
        AddGroups(entries, byName, "search", false)
    end
    if #byReagent > 0 then
        table.insert(entries, { kind = "section", text = Text("window.found_by_reagent", #byReagent) })
        AddGroups(entries, byReagent, "search_reagent", false)
    end
    return entries
end

local function AllEntries()
    local entries = {}
    local all = RecipeIndex.AllRecipes()
    table.insert(entries, { kind = "section", text = Text("window.all_recipes", #all) })
    AddGroups(entries, all, "all", true)
    return entries
end

-- The entries of the query and the reagents its search found (a set of item ids,
-- empty without a search): those are underlined in the recipe rows.
local function BuildEntries(query)
    local search = query.search or ""
    local reagents, reagentSet = {}, {}
    if search ~= "" and ns.db.settings.window.searchReagents then
        reagents, reagentSet = RecipeIndex.FindReagents(search)
    end
    if query.itemID then
        return ItemEntries(query.itemID, search, reagentSet), reagentSet
    end
    if search ~= "" then
        return SearchEntries(search, reagents, reagentSet), reagentSet
    end
    return AllEntries(), reagentSet
end

local function CreateTextLine(parent)
    local line = CreateFrame("Frame", nil, parent)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    line.text:SetPoint("LEFT", TEXT_LEFT, 0)
    line.text:SetPoint("RIGHT")
    line.text:SetJustifyH("LEFT")
    return line
end

-- options: onOpenItem(itemID) -- a click on an icon. Returns the list; place
-- list.area with SetPoint (leave ns.UI.SCROLL_AREA_BAR_SPACE on the right).
function RecipeList.Create(parent, options)
    local list = {
        area = ns.UI.ScrollArea(parent),
        entries = {},
        query = {},
        pools = { section = {}, hint = {}, profession = {}, recipe = {}, item = {} },
        markedItems = {},
    }
    local content = list.area.content

    local function CreateFrameOf(kind)
        if kind == "recipe" then
            return RecipeRow.Create(content, options.onOpenItem)
        end
        if kind == "item" then
            return ItemRow.Create(content, options.onOpenItem)
        end
        if kind == "profession" then
            local header = ns.UI.ListHeader(content, { height = Config.PROFESSION_HEADER_HEIGHT })
            header:SetOnClick(function(clicked)
                CollapsedStore(clicked.key)[clicked.key] = not clicked.isCollapsed
                list:Show(list.query, true)
            end)
            return header
        end
        local line = CreateTextLine(content)
        if kind == "hint" then
            line.text:SetFontObject("GameFontDisable")
        end
        return line
    end

    local function FillFrame(frame, entry)
        if entry.kind == "recipe" then
            RecipeRow.Fill(frame, entry.recipe, list.query.itemID, list.markedItems)
        elseif entry.kind == "item" then
            ItemRow.Fill(frame, entry.itemID)
        elseif entry.kind == "profession" then
            frame.key = entry.key
            frame.isCollapsed = entry.collapsed
            frame:SetTitle(entry.text)
            frame:SetCollapsed(entry.collapsed)
        else
            frame:SetHeight(entry.height)
            frame.text:SetText(entry.text)
        end
    end

    -- Frames only on the entries in view.
    function list:Render()
        local top = self.area:GetVerticalScroll()
        local bottom = top + self.area:GetHeight()
        local used = { section = 0, hint = 0, profession = 0, recipe = 0, item = 0 }

        for _, entry in ipairs(self.entries) do
            local isVisible = entry.y + entry.height > top and entry.y < bottom
            if isVisible then
                local pool = self.pools[entry.kind]
                used[entry.kind] = used[entry.kind] + 1
                local frame = pool[used[entry.kind]]
                if not frame then
                    frame = CreateFrameOf(entry.kind)
                    pool[used[entry.kind]] = frame
                end
                FillFrame(frame, entry)
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -entry.y)
                frame:SetPoint("RIGHT", content, "RIGHT")
                frame:Show()
            end
        end

        for kind, pool in pairs(self.pools) do
            for i = used[kind] + 1, #pool do
                pool[i]:Hide()
            end
        end
    end

    -- How many recipes and reagents the query found (collapsed professions count too).
    function list:FoundCount()
        local count = 0
        for _, entry in ipairs(self.entries) do
            if entry.kind == "profession" then
                count = count + entry.recipeCount
            end
        end
        return count
    end

    -- The sections and profession headers of the list, for the contents
    -- (components/search_contents.lua): { { text, level = 1 | 2, y }, ... }.
    function list:Contents()
        local lines = {}
        for _, entry in ipairs(self.entries) do
            if entry.kind == "section" then
                table.insert(lines, { text = WithoutColon(entry.text), level = 1, y = entry.y })
            elseif entry.kind == "profession" then
                table.insert(lines, { text = entry.text, level = entry.isTopLevel and 1 or 2, y = entry.y })
            end
        end
        return lines
    end

    -- Scrolls so that the place y of the list is at the top (or as near as the list allows).
    function list:ScrollTo(y)
        local bottom = math.max(0, self.area.content:GetHeight() - self.area:GetHeight())
        self.area:SetVerticalScroll(math.min(y, bottom))
        self:Render()
    end

    -- query: { itemID, search }; keepPosition -- the same query redrawn.
    function list:Show(query, keepPosition)
        local isNewFilter = query.itemID ~= self.query.itemID or query.search ~= self.query.search
        if isNewFilter then
            filteredCollapsed = {}
        end
        self.query = query
        self.entries, self.markedItems = BuildEntries(query)
        local y = 0
        for _, entry in ipairs(self.entries) do
            entry.y = y
            entry.height = ENTRY_HEIGHTS[entry.kind]
            y = y + entry.height
        end
        self.area:SetContentHeight(y, keepPosition)
        self:Render()
    end

    list.area:HookScript("OnVerticalScroll", function()
        list:Render()
    end)
    list.area:HookScript("OnSizeChanged", function()
        list:Render()
    end)

    return list
end
end)
