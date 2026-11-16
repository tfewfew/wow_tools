WoWTools.prr.RegisterSource(function(...)
-- sort_header.lua -- clickable column names of a table: a click sorts by the
-- column, a second click on the same column turns the order around. The sorted
-- column is white with an arrow next to its name, the others are gold.
--
-- Works on the column font strings of a header (ui/column_list.lua): an
-- invisible button is laid over each sortable one. The same as in the Dkp addon.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local ARROW_TEXTURE = "Interface\\Buttons\\UI-SortArrow"
local ARROW_WIDTH = 9
local ARROW_HEIGHT = 8
local ARROW_GAP = 3
local ACTIVE_COLOR = { 1, 1, 1 }
local NORMAL_COLOR = { 1, 0.82, 0 }
local HOVER_COLOR = { 1, 0.95, 0.6 }

-- Put the arrow next to the text of the column, on the side the text is justified to.
local function PlaceArrow(arrow, column, isAscending)
    arrow:ClearAllPoints()
    local textWidth = column:GetStringWidth()
    local justify = column:GetJustifyH()
    if justify == "RIGHT" then
        arrow:SetPoint("RIGHT", column, "RIGHT", -(textWidth + ARROW_GAP), 0)
    elseif justify == "CENTER" then
        arrow:SetPoint("LEFT", column, "CENTER", textWidth / 2 + ARROW_GAP, 0)
    else
        arrow:SetPoint("LEFT", column, "LEFT", textWidth + ARROW_GAP, 0)
    end
    -- the texture points down; flipped it points up
    if isAscending then
        arrow:SetTexCoord(0, 0.5625, 1, 0)
    else
        arrow:SetTexCoord(0, 0.5625, 0, 1)
    end
    arrow:Show()
end

local function SetColor(column, color)
    column:SetTextColor(color[1], color[2], color[3])
end

-- columns -- { [key] = font string } of the header;
-- options:
--   sortable      -- { key, ... } the columns that can be sorted by
--   descendingFirst -- { [key] = true } columns whose first click sorts from the
--                   largest (numbers: DKP, level, date); others start from A
--   state()       -- the current { key, ascending } or nil (the list's own order)
--   onSort(key, ascending) -- the player chose a new order
-- Returns an object with :Refresh() -- redraw the arrow after the state changed.
function ns.UI.SortHeader(columns, options)
    local header = {}
    local arrowParent = nil
    local arrow = nil
    local descendingFirst = options.descendingFirst or {}

    local function IsActive(key)
        local state = options.state()
        return state ~= nil and state.key == key
    end

    for _, key in ipairs(options.sortable) do
        local column = columns[key]
        local button = CreateFrame("Button", nil, column:GetParent())
        button:SetAllPoints(column)
        button:SetScript("OnClick", function()
            local state = options.state()
            local ascending = not descendingFirst[key]
            if state and state.key == key then
                ascending = not state.ascending
            end
            options.onSort(key, ascending)
            header:Refresh()
        end)
        button:SetScript("OnEnter", function()
            if not IsActive(key) then
                SetColor(column, HOVER_COLOR)
            end
        end)
        button:SetScript("OnLeave", function()
            if not IsActive(key) then
                SetColor(column, NORMAL_COLOR)
            end
        end)
        arrowParent = arrowParent or column:GetParent()
    end

    if arrowParent then
        arrow = arrowParent:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(ARROW_WIDTH, ARROW_HEIGHT)
        arrow:SetTexture(ARROW_TEXTURE)
        arrow:Hide()
    end

    function header:Refresh()
        local state = options.state()
        for _, key in ipairs(options.sortable) do
            SetColor(columns[key], NORMAL_COLOR)
        end
        if not arrow then return end
        arrow:Hide()
        if not state or not columns[state.key] then return end
        SetColor(columns[state.key], ACTIVE_COLOR)
        PlaceArrow(arrow, columns[state.key], state.ascending)
    end

    header:Refresh()
    return header
end
end)
