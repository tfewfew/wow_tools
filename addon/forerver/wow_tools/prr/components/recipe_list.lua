WoWTools.prr.RegisterSource(function(...)
-- recipe_list.lua -- the recipes of the item window in a scrolling list,
-- grouped by profession under collapsible headers (as in the quest log).
--
-- What it shows depends on the query { itemID, search }:
--   * an item -- the recipes that craft it and the ones it is a reagent for;
--     a search text narrows them by name (the item comes first);
--   * no item, a search text -- every recipe with that text in its name;
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
}

-- Collapsed professions while a filter (an item or a search) is on: a new
-- filter opens every profession again, so these are dropped when it changes.
-- Without a filter ("all") the choice is saved in settings.window.collapsed.
local filteredCollapsed = {}

local function CollapsedStore(key)
    if key:find("^all:") then
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

-- mode -- "crafted" | "reagent" | "search" | "all": each keeps its own collapsed professions.
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

local function Narrow(recipes, search)
    if not recipes or search == "" then
        return recipes or {}
    end
    return RecipeIndex.FilterByName(recipes, search)
end

local function ItemEntries(itemID, search)
    local entries = {}
    local craftedBy = Narrow(RecipeIndex.CraftedBy(itemID), search)
    local reagentFor = Narrow(RecipeIndex.ReagentFor(itemID), search)
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

local function SearchEntries(search)
    local entries = {}
    local found = RecipeIndex.FilterByName(RecipeIndex.AllRecipes(), search)
    if #found == 0 then
        table.insert(entries, { kind = "hint", text = Text("window.nothing_found") })
        return entries
    end
    table.insert(entries, { kind = "section", text = Text("window.found", #found) })
    AddGroups(entries, found, "search", false)
    return entries
end

local function AllEntries()
    local entries = {}
    local all = RecipeIndex.AllRecipes()
    table.insert(entries, { kind = "section", text = Text("window.all_recipes", #all) })
    AddGroups(entries, all, "all", true)
    return entries
end

local function BuildEntries(query)
    local search = query.search or ""
    if query.itemID then
        return ItemEntries(query.itemID, search)
    end
    if search ~= "" then
        return SearchEntries(search)
    end
    return AllEntries()
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
        pools = { section = {}, hint = {}, profession = {}, recipe = {} },
    }
    local content = list.area.content

    local function CreateFrameOf(kind)
        if kind == "recipe" then
            return RecipeRow.Create(content, options.onOpenItem)
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
            RecipeRow.Fill(frame, entry.recipe, list.query.itemID)
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
        local used = { section = 0, hint = 0, profession = 0, recipe = 0 }

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

    -- How many recipes the query found (collapsed professions count too).
    function list:FoundCount()
        local count = 0
        for _, entry in ipairs(self.entries) do
            if entry.kind == "profession" then
                count = count + entry.recipeCount
            end
        end
        return count
    end

    -- query: { itemID, search }; keepPosition -- the same query redrawn.
    function list:Show(query, keepPosition)
        local isNewFilter = query.itemID ~= self.query.itemID or query.search ~= self.query.search
        if isNewFilter then
            filteredCollapsed = {}
        end
        self.query = query
        self.entries = BuildEntries(query)
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
