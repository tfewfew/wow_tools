WoWTools.prr.RegisterSource(function(...)
-- other_addons_page.lua -- the "Other addons" page of the settings: the
-- author's other addons as cards -- icon, name, a line on what it is, its
-- features as points, and whether it is installed (installed / installed but
-- turned off / not installed). The cards scroll when they do not fit.
--
-- Copying a name: the game gives addons no clipboard, so the copy icon right
-- after the name (or a click on the name) turns the name itself into a box, in
-- place, with the name selected and "Ctrl+C" in the icon's tooltip -- Ctrl+C
-- copies it and turns it back into the name (the icon is a green tick for a
-- moment); Escape, Enter or a click elsewhere turns it back too, typing does not
-- change it.
--
-- A self-contained module, the same in every addon of the author: the folder
-- shared/other_addons is copied whole and needs nothing of the addon it is in
-- but the addon's namespace (ns.OtherAddons). Its files, in this order in .toc:
--   shared\other_addons\addons.lua           -- the list of the addons
--   shared\other_addons\lang\en.lua          -- the texts (English is the fallback)
--   shared\other_addons\lang\de.lua, fr, es, it, pt, ru, zh
--   shared\other_addons\other_addons_page.lua -- this file
--
-- Use:
--   ns.OtherAddons.Register(category, { exclude = ADDON, saved = aTable })
--     -- a subcategory "Other addons" under the addon's category in the game's
--        settings (Settings.RegisterCanvasLayoutCategory); exclude -- the folder
--        of the addon to leave out, the one the page is in;
--   ns.OtherAddons.CreatePage(parent, { exclude = ADDON, saved = aTable }) -> frame
--     -- only the page, to put somewhere else.
-- The statuses are read again every time the page is shown.
--
-- Languages: English, German, French, Spanish, Italian, Portuguese, Russian and
-- Chinese (Chinese only on a Chinese client: the other clients' fonts have no
-- Chinese letters). The page starts in the client's language; a select in its
-- header changes it at once. saved -- optional: a table the addon keeps (its
-- SavedVariables); the module writes saved.language there to remember the
-- choice. Without it the choice lasts until /reload.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
local OtherAddons = ns.OtherAddons

local FALLBACK_LANGUAGE = "en"
-- the client's locale -> the module's language
local CLIENT_LANGUAGES = {
    deDE = "de",
    frFR = "fr",
    esES = "es",
    esMX = "es",
    itIT = "it",
    ptBR = "pt",
    ptPT = "pt",
    ruRU = "ru",
    zhCN = "zh",
    zhTW = "zh",
}
-- the order of the language select
local LANGUAGE_ORDER = { "en", "de", "fr", "es", "it", "pt", "ru", "zh" }
-- languages whose letters only their own client's fonts have
local OWN_FONT_LANGUAGES = { zh = true }
local LANGUAGE_SELECT_WIDTH = 170
local LANGUAGE_SELECT_HEIGHT = 26
local DROPDOWN_TEMPLATE = "WowStyle1DropdownTemplate"

local PADDING = 24
local HEADER_GAP = 6
local DIVIDER_GAP = 16
local SCROLL_BAR_SPACE = 26      -- room for the scroll bar on the right of the cards
local CARD_GAP = 10
local CARD_INSET = 16            -- from the card edges to its content
local ICON_SIZE = 46
local ICON_CROP = 0.08
local ICON_FRAME = 2
local TEXT_GAP = 14              -- between the icon and the texts
local STATUS_WIDTH = 150
local COPY_ICON_SIZE = 16
local COPY_ICON_GAP = 8          -- between the end of the name and the copy icon
local NAME_BOX_PAD = 4           -- the name box reaches this far around the name
local NAME_BOX_LEVEL_GAP = 5
local STATUS_HEIGHT = 14
local STATUS_DOT_SIZE = 8
local ACCENT_WIDTH = 3
local LINE_GAP = 4               -- between the name, the line and the points
local FEATURES_GAP = 8
local FEATURE_SPACING = 3
-- The points: a step above the game's small font. A font object of the game,
-- never SetFont with a file: an object is a family with a file for every
-- alphabet, SetFont keeps only the Latin one (Cyrillic turned into squares).
local FEATURE_FONT = _G.GameFontHighlightSmall2 and "GameFontHighlightSmall2" or "GameFontHighlightSmall"
local BULLET = "\226\128\162 "   -- a bullet and a space, in UTF-8

local CARD_COLOR = { 0.07, 0.07, 0.09, 0.9 }
local CARD_HOVER_COLOR = { 0.11, 0.11, 0.14, 0.95 }
local BORDER_COLOR = { 0.24, 0.24, 0.28, 1 }
local BORDER_HOVER_COLOR = { 0.45, 0.45, 0.52, 1 }
local DIVIDER_COLOR = { 1, 0.82, 0, 0.35 }
local SUBTITLE_COLOR = { 0.7, 0.7, 0.74 }
local NOTES_COLOR = { 0.85, 0.85, 0.87 }
local FEATURES_COLOR = { 0.68, 0.68, 0.72 }
local FOOTER_COLOR = { 0.55, 0.55, 0.6 }
local NAME_BOX_COLOR = { 0, 0, 0, 0.6 }
local NAME_BOX_LINE_COLOR = { 1, 0.82, 0, 0.8 }
local NAME_HOVER_COLOR = { 1, 0.92, 0.5 }
local NAME_COLOR = { 1, 0.82, 0 }
local COPY_ICON_COLOR = { 0.75, 0.62, 0.3 }
local COPY_ICON_HOVER_COLOR = { 1, 0.85, 0.35 }
local COPY_DONE_COLOR = { 0.3, 0.9, 0.35 }
local TOOLTIP_TEXT_COLOR = { 1, 1, 1 }
-- the copy button: drawn here, in the look of the cards
local BUTTON_COLOR = { 0.13, 0.11, 0.07, 0.95 }
local BUTTON_HOVER_COLOR = { 0.2, 0.16, 0.08, 1 }
local BUTTON_BORDER_COLOR = { 0.55, 0.42, 0.16, 1 }
local BUTTON_HOVER_BORDER_COLOR = { 1, 0.82, 0, 1 }
local BUTTON_TEXT_COLOR = { 1, 0.82, 0 }
local BUTTON_DONE_COLOR = { 0.3, 0.9, 0.35 }
local BUTTON_PRESS_SHIFT = 1
local COPIED_SECONDS = 1.5

local STATE = {
    LOADED = "loaded",
    DISABLED = "disabled",
    MISSING = "missing",
}
local STATE_COLOR = {
    loaded = { 0.3, 0.9, 0.35 },
    disabled = { 1, 0.75, 0.2 },
    missing = { 0.55, 0.55, 0.6 },
}
local DOT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- the module's own icons, in the folder of the addon that carries it
local PICTURE_FOLDER = "Interface\\AddOns\\wow_tools\\prr\\shared\\other_addons\\icons\\"

-- loaded -- installed and on; disabled -- installed, turned off (or not loaded);
-- missing -- not in the AddOns folder
local function AddonState(folder)
    local addOns = C_AddOns or {}
    local isLoaded = addOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded and isLoaded(folder) then
        return STATE.LOADED
    end
    if addOns.DoesAddOnExist then
        local ok, exists = pcall(addOns.DoesAddOnExist, folder)
        if ok then
            return exists and STATE.DISABLED or STATE.MISSING
        end
    end
    local getInfo = addOns.GetAddOnInfo or GetAddOnInfo
    if getInfo then
        local ok, name, _, _, _, reason = pcall(getInfo, folder)
        if ok and name and reason ~= "MISSING" then
            return STATE.DISABLED
        end
    end
    return STATE.MISSING
end

-- { "a", "b" } -> the points, a bullet before each, one per line
local function Points(features)
    local lines = {}
    for _, feature in ipairs(features or {}) do
        table.insert(lines, BULLET .. feature)
    end
    return table.concat(lines, "\n")
end

local function ClientLanguage()
    local locale = GetLocale and GetLocale() or ""
    return CLIENT_LANGUAGES[locale] or FALLBACK_LANGUAGE
end

-- a language the page can show here: its texts are loaded, and its letters are
-- in this client's fonts
local function IsOffered(language)
    if not (OtherAddons.texts and OtherAddons.texts[language]) then
        return false
    end
    if OWN_FONT_LANGUAGES[language] then
        return ClientLanguage() == language
    end
    return true
end

-- the languages of the select, in order
local function OfferedLanguages()
    local languages = {}
    for _, language in ipairs(LANGUAGE_ORDER) do
        if IsOffered(language) then
            table.insert(languages, language)
        end
    end
    return languages
end

-- the language to start with: the one chosen before (saved), options.language,
-- or the client's
local function Language(options)
    options = options or {}
    local candidates = {
        options.saved and options.saved.language,
        options.language,
        ClientLanguage(),
    }
    for index = 1, 3 do
        if candidates[index] and IsOffered(candidates[index]) then
            return candidates[index]
        end
    end
    return FALLBACK_LANGUAGE
end

-- the text at a path ("state", "loaded") in the language, else in English; nil -- none
local function TextIn(language, ...)
    local all = OtherAddons.texts or {}
    local sources = { all[language], all[FALLBACK_LANGUAGE] }
    for sourceIndex = 1, 2 do
        local value = sources[sourceIndex]
        for index = 1, select("#", ...) do
            if type(value) ~= "table" then
                value = nil
                break
            end
            value = value[(select(index, ...))]
        end
        if value ~= nil then
            return value
        end
    end
    return nil
end

-- a 1 pixel frame of four textures; returns them, to recolor
local function PixelBorder(frame, color)
    local edges = {}
    local sides = {
        { "TOPLEFT", "TOPRIGHT", "height" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
        { "TOPLEFT", "BOTTOMLEFT", "width" },
        { "TOPRIGHT", "BOTTOMRIGHT", "width" },
    }
    for _, side in ipairs(sides) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(color[1], color[2], color[3], color[4])
        edge:SetPoint(side[1])
        edge:SetPoint(side[2])
        if side[3] == "height" then
            edge:SetHeight(1)
        else
            edge:SetWidth(1)
        end
        table.insert(edges, edge)
    end
    return edges
end

local function Paint(textures, color)
    for _, texture in ipairs(textures) do
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

-- A flat button in the look of the cards: a dark face, a thin bronze frame and
-- gold text; the frame lights up under the mouse, the text sinks a pixel when
-- pressed. button:Flash(label) shows another label (green) for a moment.
local function StyledButton(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    local face = button:CreateTexture(nil, "BACKGROUND")
    face:SetAllPoints()
    face:SetColorTexture(BUTTON_COLOR[1], BUTTON_COLOR[2], BUTTON_COLOR[3], BUTTON_COLOR[4])
    local border = PixelBorder(button, BUTTON_BORDER_COLOR)
    local caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("CENTER")
    caption:SetText(label)
    caption:SetTextColor(BUTTON_TEXT_COLOR[1], BUTTON_TEXT_COLOR[2], BUTTON_TEXT_COLOR[3])

    local isHover = false
    local function PaintState()
        local faceColor = isHover and BUTTON_HOVER_COLOR or BUTTON_COLOR
        face:SetColorTexture(faceColor[1], faceColor[2], faceColor[3], faceColor[4])
        Paint(border, isHover and BUTTON_HOVER_BORDER_COLOR or BUTTON_BORDER_COLOR)
    end
    button:SetScript("OnEnter", function()
        isHover = true
        PaintState()
    end)
    button:SetScript("OnLeave", function()
        isHover = false
        PaintState()
        caption:SetPoint("CENTER")
    end)
    button:SetScript("OnMouseDown", function()
        caption:SetPoint("CENTER", BUTTON_PRESS_SHIFT, -BUTTON_PRESS_SHIFT)
    end)
    button:SetScript("OnMouseUp", function()
        caption:SetPoint("CENTER")
    end)

    function button:SetLabel(newLabel)
        label = newLabel
        caption:SetText(label)
    end

    local flashId = 0
    function button:Flash(flashLabel)
        flashId = flashId + 1
        local myFlash = flashId
        caption:SetText(flashLabel)
        caption:SetTextColor(BUTTON_DONE_COLOR[1], BUTTON_DONE_COLOR[2], BUTTON_DONE_COLOR[3])
        C_Timer.After(COPIED_SECONDS, function()
            if myFlash == flashId then
                caption:SetText(label)
                caption:SetTextColor(BUTTON_TEXT_COLOR[1], BUTTON_TEXT_COLOR[2], BUTTON_TEXT_COLOR[3])
            end
        end)
    end
    button.caption = caption
    return button
end

local function MakeCard(parent, addon, text)
    local card = CreateFrame("Frame", nil, parent)
    card:EnableMouse(true)

    local background = card:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(CARD_COLOR[1], CARD_COLOR[2], CARD_COLOR[3], CARD_COLOR[4])
    local border = PixelBorder(card, BORDER_COLOR)

    -- a thin bar on the left in the color of the status
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", 1, 1)
    accent:SetWidth(ACCENT_WIDTH)

    -- the icon in a dark frame, at the top left
    local iconFrame = card:CreateTexture(nil, "ARTWORK")
    iconFrame:SetColorTexture(0, 0, 0, 1)
    iconFrame:SetSize(ICON_SIZE + ICON_FRAME * 2, ICON_SIZE + ICON_FRAME * 2)
    iconFrame:SetPoint("TOPLEFT", CARD_INSET, -CARD_INSET)
    local icon = card:CreateTexture(nil, "OVERLAY")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", iconFrame, "CENTER")
    -- a CurseForge icon whole; a game icon without its built-in edge
    if addon.picture then
        icon:SetTexture(PICTURE_FOLDER .. addon.picture)
    else
        icon:SetTexture(addon.icon)
        icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    end

    -- the status at the top right: a round dot and its word
    local status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPRIGHT", -CARD_INSET, -CARD_INSET - 4)
    status:SetJustifyH("RIGHT")
    local dot = card:CreateTexture(nil, "OVERLAY")
    dot:SetSize(STATUS_DOT_SIZE, STATUS_DOT_SIZE)
    dot:SetPoint("RIGHT", status, "LEFT", -6, 0)
    if card.CreateMaskTexture then
        local mask = card:CreateMaskTexture()
        if mask then
            mask:SetTexture(DOT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(dot)
            dot:AddMaskTexture(mask)
        end
    end

    local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", TEXT_GAP, -2)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(addon.title)

    -- the copy icon right after the name (placed by Fit, where the name ends)
    local copyButton = CreateFrame("Button", nil, card)
    copyButton:SetSize(COPY_ICON_SIZE, COPY_ICON_SIZE)
    local copyIcon = copyButton:CreateTexture(nil, "ARTWORK")
    copyIcon:SetAllPoints()
    card.copyButton = copyButton
    card.copyIcon = copyIcon

    -- the name as a box, to copy it: the same font in place of the name, up to the icon
    local nameBox = CreateFrame("EditBox", nil, card)
    nameBox:SetFontObject("GameFontNormalLarge")
    nameBox:SetAutoFocus(false)
    nameBox:SetPoint("TOPLEFT", name, "TOPLEFT", -NAME_BOX_PAD, NAME_BOX_PAD)
    nameBox:SetPoint("RIGHT", copyButton, "LEFT", -2, 0)
    nameBox:SetTextInsets(NAME_BOX_PAD, NAME_BOX_PAD, 0, 0)
    nameBox:SetFrameLevel(card:GetFrameLevel() + NAME_BOX_LEVEL_GAP)
    local boxFace = nameBox:CreateTexture(nil, "BACKGROUND")
    boxFace:SetAllPoints()
    boxFace:SetColorTexture(NAME_BOX_COLOR[1], NAME_BOX_COLOR[2], NAME_BOX_COLOR[3], NAME_BOX_COLOR[4])
    local boxLine = nameBox:CreateTexture(nil, "BORDER")
    boxLine:SetPoint("BOTTOMLEFT")
    boxLine:SetPoint("BOTTOMRIGHT")
    boxLine:SetHeight(1)
    boxLine:SetColorTexture(NAME_BOX_LINE_COLOR[1], NAME_BOX_LINE_COLOR[2], NAME_BOX_LINE_COLOR[3],
        NAME_BOX_LINE_COLOR[4])
    nameBox:Hide()
    card.nameBox = nameBox

    local isCopying = false
    local isHover = false
    local doneId = 0          -- the last "copied" tick; an older one does not undo a newer
    local isDone = false

    local function PaintIcon()
        local color = COPY_ICON_COLOR
        local glyph = "copy"
        if isDone then
            color = COPY_DONE_COLOR
            glyph = "check"
        elseif isHover or isCopying then
            color = COPY_ICON_HOVER_COLOR
        end
        copyIcon:SetTexture(PICTURE_FOLDER .. glyph)
        copyIcon:SetVertexColor(color[1], color[2], color[3])
    end

    -- the icon's tooltip: what it does, or, while the name is a box, the key to press
    local function ShowTooltip()
        GameTooltip:SetOwner(copyButton, "ANCHOR_RIGHT")
        if isCopying then
            GameTooltip:AddLine(text("copy_hint") or "", TOOLTIP_TEXT_COLOR[1], TOOLTIP_TEXT_COLOR[2],
                TOOLTIP_TEXT_COLOR[3])
        else
            GameTooltip:AddLine(text("copy") or "")
            GameTooltip:AddLine(text("copy_tooltip") or "", TOOLTIP_TEXT_COLOR[1], TOOLTIP_TEXT_COLOR[2],
                TOOLTIP_TEXT_COLOR[3], true)
        end
        GameTooltip:Show()
    end

    -- back to the name; isCopied -- after Ctrl+C: a green tick for a moment
    function card:StopCopy(isCopied)
        if isCopying then
            isCopying = false
            nameBox:ClearFocus()
            nameBox:Hide()
            name:Show()
            if GameTooltip:IsOwned(copyButton) then
                GameTooltip:Hide()
            end
        end
        if isCopied then
            doneId = doneId + 1
            local myId = doneId
            isDone = true
            C_Timer.After(COPIED_SECONDS, function()
                if myId == doneId then
                    isDone = false
                    PaintIcon()
                end
            end)
        end
        PaintIcon()
    end
    function card:StartCopy()
        isCopying = true
        name:Hide()
        nameBox:SetText(addon.title)
        nameBox:Show()
        nameBox:SetFocus()
        nameBox:HighlightText()
        PaintIcon()
        ShowTooltip()
    end
    -- Ctrl+C (Cmd+C on a Mac): the box copies on this key press itself, so it
    -- turns back into the name on the next frame
    nameBox:SetScript("OnKeyDown", function(_, key)
        local isCopyKey = key == "C" and (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown()))
        if isCopyKey then
            C_Timer.After(0, function()
                card:StopCopy(true)
            end)
        end
    end)
    nameBox:SetScript("OnEscapePressed", function()
        card:StopCopy(false)
    end)
    nameBox:SetScript("OnEnterPressed", function()
        card:StopCopy(false)
    end)
    nameBox:SetScript("OnEditFocusLost", function()
        card:StopCopy(false)
    end)
    -- read only: whatever is typed, the name comes back, selected
    nameBox:SetScript("OnTextChanged", function(self, isUserInput)
        if isUserInput then
            self:SetText(addon.title)
            self:HighlightText()
        end
    end)

    copyButton:SetScript("OnClick", function()
        if isCopying then
            card:StopCopy(false)
        else
            card:StartCopy()
        end
    end)
    copyButton:SetScript("OnEnter", function()
        isHover = true
        PaintIcon()
        ShowTooltip()
    end)
    copyButton:SetScript("OnLeave", function()
        isHover = false
        PaintIcon()
        if not isCopying then
            GameTooltip:Hide()
        end
    end)
    PaintIcon()

    -- the name itself is clickable too: lighter under the mouse
    local nameButton = CreateFrame("Button", nil, card)
    nameButton:SetAllPoints(name)
    nameButton:SetScript("OnClick", function()
        card:StartCopy()
    end)
    nameButton:SetScript("OnEnter", function()
        name:SetTextColor(NAME_HOVER_COLOR[1], NAME_HOVER_COLOR[2], NAME_HOVER_COLOR[3])
    end)
    nameButton:SetScript("OnLeave", function()
        name:SetTextColor(NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3])
    end)
    card.nameButton = nameButton

    local notes = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    notes:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -LINE_GAP)
    notes:SetJustifyH("LEFT")
    notes:SetJustifyV("TOP")
    notes:SetTextColor(NOTES_COLOR[1], NOTES_COLOR[2], NOTES_COLOR[3])

    local features = card:CreateFontString(nil, "OVERLAY", FEATURE_FONT)
    features:SetJustifyH("LEFT")
    features:SetJustifyV("TOP")
    features:SetSpacing(FEATURE_SPACING)
    features:SetTextColor(FEATURES_COLOR[1], FEATURES_COLOR[2], FEATURES_COLOR[3])

    -- the texts in the page's language; again when the language changes
    function card:ApplyTexts()
        self:StopCopy(false)
        notes:SetText(text("notes", addon.id) or "")
        features:SetText(Points(text("features", addon.id)))
    end
    card:ApplyTexts()

    card:SetScript("OnEnter", function()
        background:SetColorTexture(CARD_HOVER_COLOR[1], CARD_HOVER_COLOR[2], CARD_HOVER_COLOR[3], CARD_HOVER_COLOR[4])
        Paint(border, BORDER_HOVER_COLOR)
    end)
    card:SetScript("OnLeave", function()
        background:SetColorTexture(CARD_COLOR[1], CARD_COLOR[2], CARD_COLOR[3], CARD_COLOR[4])
        Paint(border, BORDER_COLOR)
    end)

    -- The texts wrap in the width of the card; the card is as tall as they are.
    -- The name and the line keep clear of the right column (status, copy button);
    -- the points start under whichever of the two is lower, across the whole width.
    function card:Fit(width)
        local textLeft = CARD_INSET + ICON_SIZE + ICON_FRAME * 2 + TEXT_GAP
        local textWidth = math.max(1, width - textLeft - CARD_INSET)
        local besideColumn = math.max(1, textWidth - STATUS_WIDTH - TEXT_GAP)
        -- the name leaves room for the copy icon, which stands where the name ends
        local nameWidth = math.max(1, besideColumn - COPY_ICON_GAP - COPY_ICON_SIZE)
        name:SetWidth(nameWidth)
        local nameEnd = math.min(name:GetStringWidth() or 0, nameWidth)
        copyButton:ClearAllPoints()
        copyButton:SetPoint("LEFT", name, "LEFT", nameEnd + COPY_ICON_GAP, 0)
        nameBox:SetHeight((name:GetStringHeight() or 0) + NAME_BOX_PAD * 2)
        notes:SetWidth(besideColumn)
        features:SetWidth(textWidth)
        local headerHeight = math.max(
            (name:GetStringHeight() or 0) + LINE_GAP + (notes:GetStringHeight() or 0),
            STATUS_HEIGHT)
        features:ClearAllPoints()
        features:SetPoint("TOPLEFT", card, "TOPLEFT", textLeft, -(CARD_INSET + 2 + headerHeight + FEATURES_GAP))
        local textHeight = 2 + headerHeight + FEATURES_GAP + (features:GetStringHeight() or 0)
        local height = math.max(ICON_SIZE + ICON_FRAME * 2, textHeight) + CARD_INSET * 2
        self:SetSize(width, height)
        return height
    end

    -- the status; the picture of an addon not installed is grey
    function card:Refresh()
        local state = AddonState(addon.folder)
        local color = STATE_COLOR[state]
        accent:SetColorTexture(color[1], color[2], color[3], 1)
        dot:SetColorTexture(color[1], color[2], color[3], 1)
        status:SetText(text("state", state) or "")
        status:SetTextColor(color[1], color[2], color[3])
        icon:SetDesaturated(state == STATE.MISSING)
        icon:SetAlpha(state == STATE.MISSING and 0.7 or 1)
        return state
    end

    return card
end

function OtherAddons.CreatePage(parent, options)
    options = options or {}
    local language = Language(options)
    local function text(...)
        return TextIn(language, ...)
    end
    local page = CreateFrame("Frame", nil, parent)

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)

    local subtitle = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -HEADER_GAP)
    subtitle:SetPoint("RIGHT", page, "RIGHT", -PADDING, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(SUBTITLE_COLOR[1], SUBTITLE_COLOR[2], SUBTITLE_COLOR[3])

    -- the language select at the top right, its label left of it
    local applyLanguage    -- set below: changes the page's language
    local function LanguageName(code)
        return TextIn(code, "language_name") or code
    end
    local function IsLanguage(code)
        return code == language
    end
    local function ChooseLanguage(code)
        applyLanguage(code)
    end
    local function BuildLanguageMenu(_, root)
        for _, code in ipairs(OfferedLanguages()) do
            root:CreateRadio(LanguageName(code), IsLanguage, ChooseLanguage, code)
        end
    end
    local ok, languageSelect = pcall(CreateFrame, "DropdownButton", nil, page, DROPDOWN_TEMPLATE)
    if ok and languageSelect and languageSelect.SetupMenu then
        languageSelect:SetSize(LANGUAGE_SELECT_WIDTH, LANGUAGE_SELECT_HEIGHT)
        languageSelect:SetupMenu(BuildLanguageMenu)
        function languageSelect:ShowLanguage()
            self:GenerateMenu()
        end
    else
        -- a client without the dropdown: a button that goes to the next language
        languageSelect = StyledButton(page, "", LANGUAGE_SELECT_WIDTH, LANGUAGE_SELECT_HEIGHT)
        languageSelect:SetScript("OnClick", function()
            local languages = OfferedLanguages()
            for index, code in ipairs(languages) do
                if code == language then
                    ChooseLanguage(languages[index % #languages + 1])
                    return
                end
            end
        end)
        function languageSelect:ShowLanguage()
            self:SetLabel(LanguageName(language))
        end
    end
    languageSelect:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PADDING, -PADDING)
    page.languageSelect = languageSelect
    local languageLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    languageLabel:SetPoint("RIGHT", languageSelect, "LEFT", -10, 0)

    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -DIVIDER_GAP / 2)
    divider:SetPoint("RIGHT", page, "RIGHT", -PADDING, 0)
    divider:SetColorTexture(DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], DIVIDER_COLOR[4])

    -- the cards and the footer in a scroll frame under the header
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -DIVIDER_GAP)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(PADDING + SCROLL_BAR_SPACE), PADDING)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local cards = {}
    for _, addon in ipairs(OtherAddons.list or {}) do
        if addon.folder ~= options.exclude then
            table.insert(cards, MakeCard(content, addon, text))
        end
    end

    local footer = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetJustifyH("LEFT")
    footer:SetTextColor(FOOTER_COLOR[1], FOOTER_COLOR[2], FOOTER_COLOR[3])

    -- stack the cards in the width the scroll frame has now
    local function Layout()
        local width = scroll:GetWidth() or 0
        if width <= 1 then
            return
        end
        content:SetWidth(width)
        local top = 0
        for _, card in ipairs(cards) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
            top = top + card:Fit(width) + CARD_GAP
        end
        footer:ClearAllPoints()
        footer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(top + DIVIDER_GAP / 2))
        footer:SetWidth(width)
        content:SetHeight(top + DIVIDER_GAP / 2 + (footer:GetStringHeight() or 0))
    end
    scroll:SetScript("OnSizeChanged", Layout)

    function page:Refresh()
        local installed = 0
        for _, card in ipairs(cards) do
            if card:Refresh() ~= STATE.MISSING then
                installed = installed + 1
            end
        end
        subtitle:SetText(string.format(text("subtitle") or "%d / %d", installed, #cards))
        Layout()
    end

    -- every text of the page in its language
    local function ApplyTexts()
        title:SetText(text("title") or "")
        languageLabel:SetText(text("language") or "")
        footer:SetText(text("footer") or "")
        for _, card in ipairs(cards) do
            card:ApplyTexts()
        end
        languageSelect:ShowLanguage()
    end

    applyLanguage = function(code)
        if not IsOffered(code) then
            return
        end
        language = code
        if options.saved then
            options.saved.language = code
        end
        ApplyTexts()
        page:Refresh()
    end
    page.SetLanguage = function(_, code)
        applyLanguage(code)
    end
    page.GetLanguage = function()
        return language
    end
    ApplyTexts()

    page.cards = cards
    page:SetScript("OnShow", function(self)
        self:Refresh()
    end)
    -- a name being copied turns back when the page closes
    page:SetScript("OnHide", function()
        for _, card in ipairs(cards) do
            card:StopCopy(false)
        end
    end)
    page:Refresh()
    return page
end

-- "Other addons" under the addon's own category in the game's settings; nothing
-- on a client without the settings API. category -- what
-- Settings.RegisterCanvasLayoutCategory returned for the addon.
function OtherAddons.Register(category, options)
    local hasApi = Settings and Settings.RegisterCanvasLayoutSubcategory
    if not (category and hasApi) then
        return nil
    end
    local page = OtherAddons.CreatePage(UIParent, options)
    page:Hide()
    return Settings.RegisterCanvasLayoutSubcategory(category, page, TextIn(Language(options), "title"))
end
end)
