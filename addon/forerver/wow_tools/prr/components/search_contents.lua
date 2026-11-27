WoWTools.prr.RegisterSource(function(...)
-- search_contents.lua -- the contents of the item window's list while a search
-- is on: a column at the right with the list's sections and, under each, its
-- professions. A click scrolls the list to that line.
--
--   Reagents (3)
--   Recipes (12)
--     Leatherworking (8)
--     Tailoring (4)

local ADDON, ns = ...
ns.Components = ns.Components or {}

local SearchContents = {}
ns.Components.SearchContents = SearchContents

local ROW_HEIGHT = 18
local PROFESSION_INDENT = 10
local TEXT_LEFT = 6
local DIVIDER_WIDTH = 1
local DIVIDER_COLOR = { 0.5, 0.4, 0.2, 0.6 }
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local ROW_HIGHLIGHT_ALPHA = 0.35

local function CreateRow(panel)
    local row = CreateFrame("Button", nil, panel.area.content)
    row:SetHeight(ROW_HEIGHT)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(ROW_HIGHLIGHT)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(ROW_HIGHLIGHT_ALPHA)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("RIGHT")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if panel.onJump then
            panel.onJump(self.y)
        end
    end)
    return row
end

-- onJump(y) -- a click on a line: y -- its place in the list.
function SearchContents.Create(parent, onJump)
    local panel = CreateFrame("Frame", nil, parent)
    panel.onJump = onJump
    panel.rows = {}

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(DIVIDER_WIDTH)
    divider:SetPoint("TOPLEFT")
    divider:SetPoint("BOTTOMLEFT")
    divider:SetColorTexture(DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], DIVIDER_COLOR[4])

    panel.area = ns.UI.ScrollArea(panel)
    panel.area:SetPoint("TOPLEFT", DIVIDER_WIDTH, 0)
    panel.area:SetPoint("BOTTOMRIGHT", -ns.UI.SCROLL_AREA_BAR_SPACE, 0)

    -- lines: { { text, level = 1 (a section) | 2 (a profession), y }, ... }
    function panel:Fill(lines)
        for i, line in ipairs(lines) do
            local row = self.rows[i]
            if not row then
                row = CreateRow(self)
                self.rows[i] = row
            end
            row.y = line.y
            local isProfession = line.level == 2
            row.text:SetFontObject(isProfession and "GameFontHighlightSmall" or "GameFontNormalSmall")
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", TEXT_LEFT + (isProfession and PROFESSION_INDENT or 0), 0)
            row.text:SetPoint("RIGHT")
            row.text:SetText(line.text)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.area.content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            row:SetPoint("RIGHT", self.area.content, "RIGHT")
            row:Show()
        end
        for i = #lines + 1, #self.rows do
            self.rows[i]:Hide()
        end
        self.area:SetContentHeight(#lines * ROW_HEIGHT)
    end

    return panel
end
end)
