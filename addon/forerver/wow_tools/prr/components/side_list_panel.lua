WoWTools.prr.RegisterSource(function(...)
-- side_list_panel.lua -- a list panel docked to a side of the item window (it
-- moves and hides with the window): a title, rows of an icon and a text with a
-- small cross at the right, an optional button at the bottom. Hundreds of rows:
-- only the ones in view get a frame. The history (right) and the favorites
-- (left) are such panels.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config

local SideListPanel = {}
ns.Components.SideListPanel = SideListPanel

local HEADER_HEIGHT = 32
local PADDING = 12
local ROW_HEIGHT = 22
local ICON_SIZE = 18
local ICON_TEXT_GAP = 6
local FOOTER_BUTTON_HEIGHT = 22
local DOCK_OVERLAP = 4   -- the borders of the window and the panel meet
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
-- the cross of the game's search field (SearchBoxTemplate)
local REMOVE_ICON_ATLAS = "common-search-clearbutton"
local REMOVE_SIZE = 10
local REMOVE_ALPHA = 0.5
local REMOVE_HOVER_ALPHA = 1

-- options:
--   side -- "LEFT" | "RIGHT" of the window; title; emptyText -- shown with no rows;
--   entries() -- the list to show; fill(row, entry) -- row.icon, row.text;
--   onSelect(entry) -- a click on a row; itemOf(entry) -- its item, for
--   Shift+click into the open chat (optional); onRemove(entry) -- a click on the cross;
--   onEnter(row, entry) / onLeave(row) -- hover (tooltips);
--   footer -- { text, onClick } -- a button at the bottom (optional), or
--   hint -- a note at the bottom instead (optional);
--   onDropItem(itemID) -- an item dragged onto the panel (optional).
function SideListPanel.Create(window, options)
    local panel = CreateFrame("Frame", nil, window)
    if options.side == "LEFT" then
        panel:SetPoint("TOPRIGHT", window, "TOPLEFT", DOCK_OVERLAP, 0)
        panel:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", DOCK_OVERLAP, 0)
    else
        panel:SetPoint("TOPLEFT", window, "TOPRIGHT", -DOCK_OVERLAP, 0)
        panel:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", -DOCK_OVERLAP, 0)
    end
    panel:SetWidth(Config.SIDE_PANEL_WIDTH)
    panel:EnableMouse(true)
    panel.rows = {}

    local _, headerLayer = ns.UI.GameSkin(panel)
    local title = (headerLayer or panel):CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -4)
    title:SetText(options.title)

    local function AcceptDroppedItem()
        local itemID = ns.UI.TakeCursorItem()
        if itemID and options.onDropItem then
            options.onDropItem(itemID)
        end
    end

    local function Render()
        local entries = options.entries()
        local area = panel.area
        local first = math.floor(area:GetVerticalScroll() / ROW_HEIGHT) + 1
        local last = math.min(#entries, first + math.ceil(area:GetHeight() / ROW_HEIGHT))

        local used = 0
        for index = first, last do
            used = used + 1
            local row = panel.rows[used]
            if not row then
                row = panel:CreateRow()
                panel.rows[used] = row
            end
            row.entry = entries[index]
            options.fill(row, entries[index])
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            row:SetPoint("RIGHT", area.content, "RIGHT")
            row:Show()
        end
        for i = used + 1, #panel.rows do
            panel.rows[i]:Hide()
        end
        panel.empty:SetShown(#entries == 0)
    end

    function panel:CreateRow()
        local row = CreateFrame("Button", nil, self.area.content)
        row:SetHeight(ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(ROW_HIGHLIGHT)
        highlight:SetBlendMode("ADD")

        -- a frame, not a texture: it carries the favorite star in its corner
        row.iconFrame = CreateFrame("Frame", nil, row)
        row.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
        row.iconFrame:SetPoint("LEFT", 2, 0)
        row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
        row.icon:SetAllPoints()

        -- the cross: just the icon, brighter under the mouse
        row.remove = CreateFrame("Button", nil, row)
        row.remove:SetSize(REMOVE_SIZE, REMOVE_SIZE)
        row.remove:SetPoint("RIGHT", -2, 0)
        local cross = row.remove:CreateTexture(nil, "ARTWORK")
        cross:SetAllPoints()
        cross:SetAtlas(REMOVE_ICON_ATLAS)
        cross:SetAlpha(REMOVE_ALPHA)
        row.remove:SetScript("OnEnter", function()
            cross:SetAlpha(REMOVE_HOVER_ALPHA)
        end)
        row.remove:SetScript("OnLeave", function()
            cross:SetAlpha(REMOVE_ALPHA)
        end)
        row.remove:SetScript("OnClick", function()
            options.onRemove(row.entry)
            panel:Refresh()
        end)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.iconFrame, "RIGHT", ICON_TEXT_GAP, 0)
        row.text:SetPoint("RIGHT", row.remove, "LEFT", -ICON_TEXT_GAP, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        row:SetScript("OnClick", function(self)
            local itemID = options.itemOf and options.itemOf(self.entry)
            if ns.Utilities.InsertChatLink("item", itemID) then return end
            options.onSelect(self.entry)
        end)
        row:SetScript("OnEnter", function(self)
            if options.onEnter then
                options.onEnter(self, self.entry)
            end
        end)
        row:SetScript("OnLeave", function(self)
            if options.onLeave then
                options.onLeave(self)
            end
        end)
        if options.onDropItem then
            row:SetScript("OnReceiveDrag", AcceptDroppedItem)
        end
        return row
    end

    local footer = nil
    if options.footer then
        footer = ns.UI.Button(panel, {
            text = options.footer.text,
            height = FOOTER_BUTTON_HEIGHT,
            onClick = function()
                options.footer.onClick()
                panel.area:SetContentHeight(0, false)
                panel:Refresh()
            end,
        })
        footer:SetPoint("BOTTOMLEFT", PADDING, PADDING)
        footer:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    elseif options.hint then
        -- a note at the bottom instead of a button, always shown
        footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footer:SetPoint("BOTTOMLEFT", PADDING, PADDING)
        footer:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
        footer:SetJustifyH("CENTER")
        footer:SetText(options.hint)
    end

    panel.area = ns.UI.ScrollArea(panel)
    panel.area:SetPoint("TOPLEFT", PADDING, -HEADER_HEIGHT)
    if footer then
        panel.area:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -ns.UI.SCROLL_AREA_BAR_SPACE, PADDING)
    else
        panel.area:SetPoint("BOTTOMRIGHT", -(PADDING + ns.UI.SCROLL_AREA_BAR_SPACE), PADDING)
    end
    panel.area:HookScript("OnVerticalScroll", Render)
    panel.area:HookScript("OnSizeChanged", Render)

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("TOP", panel.area, "TOP", 0, -PADDING)
    panel.empty:SetPoint("LEFT", PADDING, 0)
    panel.empty:SetPoint("RIGHT", -PADDING, 0)
    panel.empty:SetText(options.emptyText)

    if options.onDropItem then
        panel:SetScript("OnReceiveDrag", AcceptDroppedItem)
        panel:SetScript("OnMouseUp", AcceptDroppedItem)
    end

    -- Redraw after the list changed (and when item names came).
    function panel:Refresh()
        if not self:IsShown() then return end
        self.area:SetContentHeight(#options.entries() * ROW_HEIGHT, true)
        Render()
    end

    function panel:Toggle()
        self:SetShown(not self:IsShown())
        self:Refresh()
    end

    panel:Hide()
    return panel
end
end)
