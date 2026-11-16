WoWTools.prr.RegisterSource(function(...)
-- link_dialog.lua -- a small window with a Wowhead link ready to copy.
-- Addons cannot write to the clipboard, so the link is put into a field,
-- selected, and the player presses Ctrl+C once more; the window then closes.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local LinkDialog = {}
ns.Components.LinkDialog = LinkDialog

local FRAME_NAME = "PRRLinkDialog"
local WIDTH = 420
local HEIGHT = 96
local PADDING = 18
local HEADER_HEIGHT = 30
local FIELD_HEIGHT = 22
local CLOSE_AFTER_COPY_SECONDS = 0.1   -- let the client copy the selection first

local frame = nil

local function Create()
    frame = ns.UI.Panel(FRAME_NAME, UIParent, {
        width = WIDTH,
        height = HEIGHT,
        title = Text("link.title"),
        gameSkin = true,
    })
    frame:SetPoint("CENTER", 0, 120)
    frame:SetFrameStrata("DIALOG")
    table.insert(UISpecialFrames, FRAME_NAME)

    local field = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    field:SetHeight(FIELD_HEIGHT)
    field:SetPoint("TOPLEFT", PADDING + 6, -HEADER_HEIGHT)
    field:SetPoint("TOPRIGHT", -PADDING, -HEADER_HEIGHT)
    field:SetAutoFocus(false)
    frame.field = field

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", field, "BOTTOMLEFT", -6, -8)
    hint:SetText(Text("link.hint"))

    -- the field always holds the link: typing does not change it
    field:SetScript("OnTextChanged", function(self, isUserInput)
        if isUserInput then
            self:SetText(frame.url)
            self:HighlightText()
        end
    end)
    field:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    field:SetScript("OnEnterPressed", function()
        frame:Hide()
    end)
    field:SetScript("OnKeyDown", function(_, key)
        local isCopy = key == "C" and IsControlKeyDown()
        if isCopy then
            C_Timer.After(CLOSE_AFTER_COPY_SECONDS, function()
                frame:Hide()
                ns.Utilities.Print(Text("link.copied"))
            end)
        end
    end)
    frame:SetScript("OnHide", function()
        field:ClearFocus()
    end)
end

-- kind -- "item" | "spell"
function LinkDialog.Show(kind, id)
    if not frame then
        Create()
    end
    frame.url = ns.Wowhead.Url(kind, id)
    frame.field:SetText(frame.url)
    frame:Show()
    frame.field:SetFocus()
    frame.field:HighlightText()
end
end)
