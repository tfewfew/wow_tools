WoWTools.prr.RegisterSource(function(...)
-- input.lua -- single-line input with a placeholder while it is empty.
--
-- With options.search it is the game's own search box (SearchBoxTemplate, as in
-- the collections and the Who list): framed field, a magnifier on the left, a
-- clear button on the right, the placeholder in the template's instructions.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local TEXT_INSET = 6
local SEARCH_TEMPLATE = "SearchBoxTemplate"
local SEARCH_LEFT_OVERHANG = 6   -- the template frame is drawn this far left of the box

-- The frame of the game's dropdown (WowStyle1DropdownTemplate on Forever): the
-- same text holder, so fields and selects look alike. It sticks out of the box
-- by these pixels, as Lootified places it on this client.
local DROPDOWN_FRAME_ATLAS = "common-dropdown-textholder"
local DROPDOWN_FRAME_OUTSET_LEFT = 9
local DROPDOWN_FRAME_OUTSET_TOP = 8
local DROPDOWN_FRAME_OUTSET_RIGHT = 8
local DROPDOWN_FRAME_OUTSET_BOTTOM = 9
local DROPDOWN_TEXT_INSET = 9

-- The dropdown frame around the field; returns the text inset, or nil if the
-- client has no such atlas.
local function AddDropdownFrame(input)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(DROPDOWN_FRAME_ATLAS)
    if not hasAtlas then
        return nil
    end
    local frameArt = input:CreateTexture(nil, "BACKGROUND")
    frameArt:SetAtlas(DROPDOWN_FRAME_ATLAS)
    frameArt:SetPoint("TOPLEFT", -DROPDOWN_FRAME_OUTSET_LEFT, DROPDOWN_FRAME_OUTSET_TOP)
    frameArt:SetPoint("BOTTOMRIGHT", DROPDOWN_FRAME_OUTSET_RIGHT, -DROPDOWN_FRAME_OUTSET_BOTTOM)
    input:SetTextInsets(DROPDOWN_TEXT_INSET, DROPDOWN_TEXT_INSET, 0, 0)
    return DROPDOWN_TEXT_INSET
end

-- A thin border and a dark fill, for a client without the dropdown atlas.
local function AddPlainFrame(input)
    input:SetTextInsets(TEXT_INSET, TEXT_INSET, 0, 0)
    input:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    input:SetBackdropColor(0, 0, 0, 0.5)
    input:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    return TEXT_INSET
end

local function PlainInput(parent, options)
    local input = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    input:SetAutoFocus(false)
    input:SetFontObject(options.fontObject or "GameFontHighlightSmall")
    local textInset = AddDropdownFrame(input) or AddPlainFrame(input)

    local placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", textInset, 0)
    placeholder:SetText(options.placeholder or "")
    input.placeholder = placeholder
    input.leftOverhang = 0
    return input
end

-- The game's search box, or nil if this client has no such template.
local function SearchInput(parent, options)
    local ok, input = pcall(CreateFrame, "EditBox", nil, parent, SEARCH_TEMPLATE)
    if not ok or not input then
        return nil
    end
    if input.Instructions then
        input.Instructions:SetText(options.placeholder or "")
    end
    input.leftOverhang = SEARCH_LEFT_OVERHANG
    return input
end

-- options: width, height, placeholder, onChange(text),
-- onEnter(), onEscape() -- instead of just dropping the focus, fontObject,
-- search -- the game's search box look.
-- input.leftOverhang -- how far left of the box its frame is drawn; shift the
-- box right by it to line the frame up with other controls.
-- The template has its own scripts (instructions, clear button), so ours are hooked.
function ns.UI.Input(parent, options)
    local input = nil
    if options.search then
        input = SearchInput(parent, options)
    end
    if not input then
        input = PlainInput(parent, options)
    end
    input:SetSize(options.width, options.height or 20)

    input:HookScript("OnTextChanged", function(self)
        local text = self:GetText()
        if self.placeholder then
            self.placeholder:SetShown(text == "")
        end
        if options.onChange then
            options.onChange(text)
        end
    end)
    input:HookScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if options.onEscape then
            options.onEscape()
        end
    end)
    input:HookScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if options.onEnter then
            options.onEnter()
        end
    end)

    return input
end
end)
