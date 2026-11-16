WoWTools.prr.RegisterSource(function(...)
-- prompt.lua -- dialog with a question, one input field and "OK" / "Cancel"
-- (ns.UI.Prompt), or the same dialog without the field (ns.UI.Confirm), which
-- can carry one checkbox for an option of the action.
--
-- Our own window, not a StaticPopup: the built-in popup has a fixed width and
-- look. This one uses the game-window skin (ui/client_border.lua) with the
-- addon title in the title band. It is always on top (FULLSCREEN_DIALOG).

local ADDON, ns = ...
ns.UI = ns.UI or {}

local WIDTH = 360
local PADDING = 20
local TITLE_BAND_HEIGHT = 22     -- the title band of the game-window border
local TOP_WITHOUT_BAND = 16
local GAP = 10
local INPUT_HEIGHT = 26
local ACTION_BUTTON_WIDTH = 120
local ACTION_BUTTON_HEIGHT = 24
local ACTION_GAP = 12
local DEFAULT_MAX_LETTERS = 200
local BACKGROUND_COLOR = { 0.04, 0.04, 0.05, 0.95 }
local CHECKBOX_HEIGHT = 22

local dialog = nil

local function Close()
    dialog:Hide()
end

local function Accept()
    local onAccept = dialog.onAccept
    local text = dialog.input:GetText()
    Close()
    if onAccept then
        onAccept(text)
    end
end

local function CreateDialog()
    local frame = CreateFrame("Frame", "PRRPrompt", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER", 0, 120)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    table.insert(UISpecialFrames, "PRRPrompt")   -- Escape closes it

    local skinned, headerLayer = ns.UI.GameSkin(frame)
    frame.contentTop = TOP_WITHOUT_BAND
    if headerLayer then
        local header = headerLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOP", 0, -1)
        header:SetHeight(TITLE_BAND_HEIGHT - 2)
        frame.header = header
        frame.contentTop = TITLE_BAND_HEIGHT + GAP
    end
    if not skinned then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3], BACKGROUND_COLOR[4])
    end

    local contentWidth = WIDTH - 2 * PADDING

    frame.question = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.question:SetWidth(contentWidth)
    frame.question:SetJustifyH("CENTER")
    frame.question:SetPoint("TOP", 0, -frame.contentTop)

    frame.input = ns.UI.Input(frame, {
        width = contentWidth,
        height = INPUT_HEIGHT,
        fontObject = "GameFontHighlight",
        onEnter = Accept,
        onEscape = Close,
    })
    frame.input:SetPoint("TOP", frame.question, "BOTTOM", 0, -GAP)

    frame.okButton = ns.UI.Button(frame, {
        text = OKAY,
        width = ACTION_BUTTON_WIDTH,
        height = ACTION_BUTTON_HEIGHT,
        onClick = Accept,
    })

    frame.cancelButton = ns.UI.Button(frame, {
        text = CANCEL,
        width = ACTION_BUTTON_WIDTH,
        height = ACTION_BUTTON_HEIGHT,
        onClick = Close,
    })
    return frame
end

-- The option checkbox of a confirmation, made on first use.
local function Checkbox()
    if not dialog.checkbox then
        dialog.checkbox = ns.UI.Checkbox(dialog, {})
    end
    return dialog.checkbox
end

-- Under the question: the field or the checkbox, if shown, then the buttons
-- centered on the window; the window takes the height of what is shown.
local function Layout(hasInput, hasCheckbox)
    dialog.input:SetShown(hasInput)
    if dialog.checkbox then
        dialog.checkbox:SetShown(hasCheckbox)
    end
    local questionHeight = dialog.question:GetStringHeight()
    local contentHeight = questionHeight
    if hasInput then
        contentHeight = contentHeight + GAP + INPUT_HEIGHT
    end
    if hasCheckbox then
        -- the box and its label together, centered under the question
        local checkbox = dialog.checkbox
        local labelGap = select(4, checkbox.label:GetPoint(1)) or 0
        local totalWidth = checkbox:GetWidth() + labelGap + checkbox.label:GetStringWidth()
        checkbox:ClearAllPoints()
        checkbox:SetPoint("TOPLEFT", dialog.question, "BOTTOM", -totalWidth / 2, -GAP)
        contentHeight = contentHeight + GAP + CHECKBOX_HEIGHT
    end

    local buttonsTop = -(contentHeight - questionHeight) - GAP - 4
    dialog.okButton:ClearAllPoints()
    dialog.okButton:SetPoint("TOPRIGHT", dialog.question, "BOTTOM", -ACTION_GAP / 2, buttonsTop)
    dialog.cancelButton:ClearAllPoints()
    dialog.cancelButton:SetPoint("TOPLEFT", dialog.question, "BOTTOM", ACTION_GAP / 2, buttonsTop)

    local height = dialog.contentTop
        + contentHeight
        + GAP + 4 + ACTION_BUTTON_HEIGHT
        + PADDING
    dialog:SetHeight(height)
end

local function Open(text, onAccept)
    if not dialog then
        dialog = CreateDialog()
    end
    dialog.onAccept = onAccept
    if dialog.header then
        dialog.header:SetText(ns.Constants.ADDON_TITLE)
    end
    dialog.question:SetText(text)
end

-- text -- the question above the field; onAccept(entered text) -- on OK or Enter.
-- options (optional): initialText -- text already in the field (selected, so
-- typing replaces it), maxLetters -- how many characters can be entered.
-- Empty input is accepted too. A new prompt replaces an open one.
function ns.UI.Prompt(text, onAccept, options)
    options = options or {}
    Open(text, onAccept)
    dialog.input:SetMaxLetters(options.maxLetters or DEFAULT_MAX_LETTERS)
    dialog.input:SetText(options.initialText or "")
    Layout(true, false)

    dialog:Show()
    dialog:Raise()
    dialog.input:SetFocus()
    dialog.input:HighlightText()
end

-- text -- what is about to happen (several lines are fine); onAccept(checked) --
-- on OK, checked -- the state of the checkbox, if there is one.
-- options (optional): checkbox = { text, checked } -- an option of the action.
-- Only a click on OK confirms: Enter does nothing, Escape and Cancel close.
-- A new dialog replaces an open one.
function ns.UI.Confirm(text, onAccept, options)
    options = options or {}
    local checkboxOptions = options.checkbox
    Open(text, function()
        local checked = nil
        if checkboxOptions then
            checked = dialog.checkbox:GetChecked() and true or false
        end
        onAccept(checked)
    end)
    dialog.input:ClearFocus()
    if checkboxOptions then
        local checkbox = Checkbox()
        checkbox.label:SetText(checkboxOptions.text or "")
        checkbox:SetChecked(checkboxOptions.checked and true or false)
    end
    Layout(false, checkboxOptions ~= nil)

    dialog:Show()
    dialog:Raise()
end
end)
