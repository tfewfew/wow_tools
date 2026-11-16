WoWTools.prr.RegisterSource(function(...)
-- column_list.lua -- a scrolling list of rows with column titles, in the look
-- of the auction house tables:
--
--   | Recipe ^                         | Cost     | Sells for  | Profit    |   <- column tabs
--   [icon] Lesser Healing Potion         12s 40c    30s          17s 60c       <- striped rows
--
-- The column tabs are the textures of the game's column headers (the Who list,
-- the auction house: WhoFrame-ColumnTabs), the rows -- the stripes of the
-- auction house (auctionhouse-rowstripe-*, plain colors on a client without
-- them) in the game's inset well.
-- Every row: an icon (ui/icon_button.lua: the item tooltip, the quality
-- border), a name and cells right-aligned in fixed-width columns.
-- Hundreds of rows: only the ones in view get a frame (the frames move to the
-- rows in view on every scroll). Columns with a key sort on a click of their
-- title (ui/sort_header.lua: an arrow by the sorted one).

local ADDON, ns = ...
ns.UI = ns.UI or {}

local TITLE_HEIGHT = 22
local LIST_TOP_GAP = 2
local ICON_TEXT_GAP = 6
local COLUMN_GAP = 12            -- between cells; a column tab sticks out by half of it
local TAB_OUTSET = COLUMN_GAP / 2
local TAB_TEXT_INSET = 8         -- the name title inside its tab
local COLUMN_TABS_TEXTURE = "Interface\\FriendsFrame\\WhoFrame-ColumnTabs"
-- left edge, middle, right edge of the column tab texture
local TAB_LEFT_COORDS = { 0, 0.078125, 0, 0.75 }
local TAB_MIDDLE_COORDS = { 0.078125, 0.90625, 0, 0.75 }
local TAB_RIGHT_COORDS = { 0.90625, 0.96875, 0, 0.75 }
local TAB_EDGE_WIDTH = 5
local STRIPE_ATLASES = { "auctionhouse-rowstripe-1", "auctionhouse-rowstripe-2" }
local STRIPE_COLORS = { { 1, 1, 1, 0.04 }, { 0, 0, 0, 0 } }
-- the hover: added light over the row (the highlight layer is drawn above the
-- text, an opaque one would hide it -- the auction house one is)
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local ROW_HIGHLIGHT_ALPHA = 0.45
local INSET_TEMPLATE = "InsetFrameTemplate"   -- the dark well with a thin edge of the game's windows
local LIST_BACKGROUND_COLOR = { 0.03, 0.03, 0.03, 0.9 }   -- a client without the template
local INSET_OUTSET = 2           -- the edge of the well sticks out of the rows

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function CoordsTexture(parent, coords)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture(COLUMN_TABS_TEXTURE)
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    return texture
end

-- A column tab under a title: the left and right edges and the middle.
local function CreateColumnTab(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetHeight(TITLE_HEIGHT)
    local left = CoordsTexture(tab, TAB_LEFT_COORDS)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(TAB_EDGE_WIDTH)
    local right = CoordsTexture(tab, TAB_RIGHT_COORDS)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(TAB_EDGE_WIDTH)
    local middle = CoordsTexture(tab, TAB_MIDDLE_COORDS)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return tab
end

-- Cells right to left: the last column at the right edge.
local function CreateCells(parent, columns, fontObject)
    local cells = {}
    local rightNeighbour = nil
    for i = #columns, 1, -1 do
        local cell = parent:CreateFontString(nil, "OVERLAY", fontObject)
        cell:SetWidth(columns[i].width)
        cell:SetJustifyH("RIGHT")
        cell:SetWordWrap(false)
        if rightNeighbour then
            cell:SetPoint("RIGHT", rightNeighbour, "LEFT", -COLUMN_GAP, 0)
        else
            cell:SetPoint("RIGHT", -TAB_OUTSET, 0)
        end
        cells[i] = cell
        rightNeighbour = cell
    end
    return cells
end

-- The background of the rows and the scroll bar: the game's inset well.
local function CreateInset(list, area)
    local ok, inset = pcall(CreateFrame, "Frame", nil, list, INSET_TEMPLATE)
    if not (ok and inset) then
        inset = CreateFrame("Frame", nil, list)
        local fill = inset:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(LIST_BACKGROUND_COLOR[1], LIST_BACKGROUND_COLOR[2],
            LIST_BACKGROUND_COLOR[3], LIST_BACKGROUND_COLOR[4])
    end
    inset:SetPoint("TOPLEFT", area, "TOPLEFT", -INSET_OUTSET, INSET_OUTSET)
    inset:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, -INSET_OUTSET)
    inset:SetFrameLevel(list:GetFrameLevel())
    area:SetFrameLevel(inset:GetFrameLevel() + 1)
end

-- A column with a tooltip: what its numbers mean, on hover over its tab. Only
-- such tabs take the mouse: the others leave the clicks to the sort titles.
local function AddColumnTooltip(tab, column)
    if not column.tooltip then return end
    tab:EnableMouse(true)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(column.title)
        GameTooltip:AddLine(column.tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- The column tabs with the titles; the sortable ones sort on a click.
local function CreateHeader(list, titles, options)
    titles:SetHeight(TITLE_HEIGHT)
    local titleCells = CreateCells(titles, options.columns, "GameFontNormalSmall")
    local nameTitle = titles:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameTitle:SetPoint("LEFT", TAB_TEXT_INSET, 0)
    nameTitle:SetJustifyH("LEFT")

    -- the tabs: one over every column, the name tab up to the first column
    list.columnTabs = {}
    for i, cell in ipairs(titleCells) do
        local tab = CreateColumnTab(titles)
        list.columnTabs[i] = tab
        tab:SetPoint("LEFT", cell, "LEFT", -TAB_OUTSET, 0)
        tab:SetPoint("RIGHT", cell, "RIGHT", TAB_OUTSET, 0)
        AddColumnTooltip(tab, options.columns[i])
    end
    local nameTab = CreateColumnTab(titles)
    nameTab:SetPoint("LEFT", 0, 0)
    if titleCells[1] then
        nameTab:SetPoint("RIGHT", titleCells[1], "LEFT", -TAB_OUTSET, 0)
        nameTitle:SetPoint("RIGHT", titleCells[1], "LEFT", -COLUMN_GAP, 0)
    else
        nameTab:SetPoint("RIGHT", 0, 0)
    end

    nameTitle:SetText(options.title)
    local sortColumns = {}
    local sortable = {}
    if options.titleKey then
        sortColumns[options.titleKey] = nameTitle
        table.insert(sortable, options.titleKey)
    end
    for i, column in ipairs(options.columns) do
        titleCells[i]:SetText(column.title)
        if column.key then
            sortColumns[column.key] = titleCells[i]
            table.insert(sortable, column.key)
        end
    end
    if options.sort then
        list.sortHeader = ns.UI.SortHeader(sortColumns, {
            sortable = sortable,
            descendingFirst = options.sort.descendingFirst,
            state = options.sort.state,
            onSort = options.sort.onSort,
        })
    end
end

-- options: title -- of the name column, titleKey -- its sort key (optional);
-- columns -- { { title, width, key, tooltip }, ... } (tooltip -- a hint on the
-- hover of the column title, optional); rowHeight, iconSize,
-- onIconClick(iconButton, mouseButton) -- a click on the icon (optional);
-- nameRightInset -- room right of the name in a list without columns (optional);
-- onCreateRow(row) -- more regions for a row (optional); iconTop -- the icon
-- at the top of the row instead of its middle (optional);
-- onEnter(row), onLeave(row), onClick(row, mouseButton);
-- sort -- { descendingFirst, state(), onSort(key, ascending) } of ns.UI.SortHeader
-- for the columns with a key (optional); topPadding -- room above the first
-- row (optional); plain -- just the rows in the well:
-- no column tabs, no stripes (a simple list).
-- list:SetPoint(...) places it (titles on top), list:Fill(count, fill(row, index)).
function ns.UI.ColumnList(parent, options)
    local list = CreateFrame("Frame", nil, parent)
    list.rows = {}          -- the frames
    list.count = 0
    list.fill = nil

    -- the column tabs on top; a plain list has none
    local titles = CreateFrame("Frame", nil, list)
    titles:SetPoint("TOPLEFT")
    titles:SetPoint("TOPRIGHT", -ns.UI.SCROLL_AREA_BAR_SPACE, 0)
    if options.plain then
        titles:SetHeight(1)
    else
        CreateHeader(list, titles, options)
    end

    local area = ns.UI.ScrollArea(list)
    area:SetPoint("TOPLEFT", titles, "BOTTOMLEFT", 0, -LIST_TOP_GAP)
    area:SetPoint("BOTTOMRIGHT", -ns.UI.SCROLL_AREA_BAR_SPACE, 0)
    list.area = area

    CreateInset(list, area)
    local hasStripes = HasAtlas(STRIPE_ATLASES[1]) and HasAtlas(STRIPE_ATLASES[2])

    -- The stripe of a row by its place: odd and even rows differ.
    local function PaintStripe(row, index)
        if options.plain then return end
        local parity = (index % 2) + 1
        if hasStripes then
            row.stripe:SetAtlas(STRIPE_ATLASES[parity])
            return
        end
        local color = STRIPE_COLORS[parity]
        row.stripe:SetColorTexture(color[1], color[2], color[3], color[4])
    end

    local function CreateRow()
        local row = CreateFrame("Button", nil, area.content)
        row:SetHeight(options.rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(ROW_HIGHLIGHT)
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(ROW_HIGHLIGHT_ALPHA)

        -- the item of the row: its own tooltip and the border of its quality
        row.icon = ns.UI.IconButton(row, {
            size = options.iconSize,
            onClick = options.onIconClick,
        })
        if options.iconTop then
            row.icon:SetPoint("TOPLEFT", TAB_OUTSET, -2)
        else
            row.icon:SetPoint("LEFT", TAB_OUTSET, 0)
        end

        row.cells = CreateCells(row, options.columns, "GameFontHighlightSmall")

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if options.iconTop then
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", ICON_TEXT_GAP, 0)
        else
            row.name:SetPoint("LEFT", row.icon, "RIGHT", ICON_TEXT_GAP, 0)
        end
        if row.cells[1] then
            row.name:SetPoint("RIGHT", row.cells[1], "LEFT", -COLUMN_GAP, 0)
        else
            row.name:SetPoint("RIGHT", -(options.nameRightInset or 2), 0)
        end
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        if options.onCreateRow then
            options.onCreateRow(row)
        end
        if options.onEnter then
            row:SetScript("OnEnter", options.onEnter)
        end
        row:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if options.onLeave then
                options.onLeave(self)
            end
        end)
        if options.onClick then
            row:SetScript("OnClick", options.onClick)
        end
        return row
    end

    -- Frames on the rows in view.
    function list:Render()
        if not self.fill then return end
        local topPadding = options.topPadding or 0
        local top = math.max(0, area:GetVerticalScroll() - topPadding)
        local first = math.max(1, math.floor(top / options.rowHeight) + 1)
        local visibleCount = math.ceil(area:GetHeight() / options.rowHeight) + 1
        local last = math.min(self.count, first + visibleCount - 1)
        local used = 0
        for index = first, last do
            used = used + 1
            local row = self.rows[used]
            if not row then
                row = CreateRow()
                self.rows[used] = row
            end
            row.index = index
            PaintStripe(row, index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, -(topPadding + (index - 1) * options.rowHeight))
            row:SetPoint("RIGHT", area.content, "RIGHT", 0, 0)
            self.fill(row, index)
            row:Show()
        end
        for i = used + 1, #self.rows do
            self.rows[i]:Hide()
        end
    end

    -- count rows, fill(row, index) sets the content of a row in view.
    -- keepPosition -- the same rows again: the scroll stays where it is.
    function list:Fill(count, fill, keepPosition)
        self.count = count
        self.fill = fill
        area:SetContentHeight((options.topPadding or 0) + count * options.rowHeight, keepPosition ~= false)
        self:Render()
    end

    area:HookScript("OnVerticalScroll", function()
        list:Render()
    end)
    area:HookScript("OnSizeChanged", function()
        list:Render()
    end)

    return list
end
end)
