WoWTools.prr.RegisterSource(function(...)
-- panel.lua -- draggable window with a border, a title and a close button.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local TITLE_BAND_HEIGHT = 22   -- the title band of the game-window border
local CLOSE_BUTTON_SHRINK = 2  -- pixels off the template close button, to fit the band
local RESIZE_GRIP_SIZE = 16
local RESIZE_GRIP_OFFSET = 4   -- from the bottom right corner, inside the border
local RESIZE_GRIP_TEXTURE = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber"
local TITLE_LEFT = 14           -- left-aligned title: from the window's left edge
local HEADER_BUTTON_SIZE = 16   -- icon buttons in the title band, left of the close button
local HEADER_BUTTON_GAP = 6          -- between icon buttons, and from the last one to the title
local HEADER_BUTTON_CLOSE_GAP = 4    -- from the close button
local ICON_CROP = 0.08          -- icon textures have a frame around the picture: cut it off
local HEADER_BUTTON_HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"

-- Pin the window by its top left corner where it stands now, so that resizing
-- moves only the bottom right corner (anchored by the saved CENTER, the window
-- would grow in both directions).
local function PinTopLeft(frame)
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if not left or not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Corner grip that resizes the window by dragging, like the chat window's.
-- resizable: minWidth, minHeight, onResized(frame) -- when the drag ends; the
-- window is anchored by its top left corner by then, so save the position too.
--
-- The size is computed by hand every frame: the size at the press plus how far
-- the mouse went, not smaller than the minimum and not past the screen edges.
-- The client's StartSizing made the window jump to a random size on a click
-- of the grip on this client, whatever the anchor.
local function AddResizeGrip(frame, resizable)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -RESIZE_GRIP_OFFSET, RESIZE_GRIP_OFFSET)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)   -- above the border
    grip:SetNormalTexture(RESIZE_GRIP_TEXTURE .. "-Up")
    grip:SetHighlightTexture(RESIZE_GRIP_TEXTURE .. "-Highlight")
    grip:SetPushedTexture(RESIZE_GRIP_TEXTURE .. "-Down")

    -- what the window and the mouse were at the press
    local start = nil

    local function StopSizing()
        if not start then return end
        start = nil
        grip:SetScript("OnUpdate", nil)
        if resizable.onResized then
            resizable.onResized(frame)
        end
    end

    local function FollowMouse()
        -- the button went up outside of the grip and OnMouseUp got lost
        if not IsMouseButtonDown("LeftButton") then
            StopSizing()
            return
        end

        local cursorX, cursorY = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        local width = start.width + (cursorX - start.cursorX) / scale
        local height = start.height + (start.cursorY - cursorY) / scale

        -- the window may not grow past the right and bottom screen edges
        local maxWidth = UIParent:GetRight() - start.left
        local maxHeight = start.top - UIParent:GetBottom()
        width = math.max(resizable.minWidth, math.min(maxWidth, width))
        height = math.max(resizable.minHeight, math.min(maxHeight, height))
        frame:SetSize(width, height)
    end

    grip:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        PinTopLeft(frame)
        local cursorX, cursorY = GetCursorPosition()
        start = {
            cursorX = cursorX,
            cursorY = cursorY,
            width = frame:GetWidth(),
            height = frame:GetHeight(),
            left = frame:GetLeft(),
            top = frame:GetTop(),
        }
        grip:SetScript("OnUpdate", FollowMouse)
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    -- closed with Escape in the middle of a drag
    frame:HookScript("OnHide", StopSizing)
    frame.resizeGrip = grip
end

-- A small icon button with a tooltip. options: icon, tooltip, onClick.
local function HeaderButton(parent, options)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(HEADER_BUTTON_SIZE, HEADER_BUTTON_SIZE)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(options.icon)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    button:SetHighlightTexture(HEADER_BUTTON_HIGHLIGHT, "ADD")

    -- pressed: the picture moves a pixel down and right, like game buttons
    button:SetScript("OnMouseDown", function()
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", 1, -1)
    end)
    button:SetScript("OnMouseUp", function()
        icon:ClearAllPoints()
        icon:SetAllPoints()
    end)
    button:SetScript("OnClick", options.onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(options.tooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return button
end

local function ApplyTooltipLook(frame)
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    frame:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
end

-- options: width, height, title, onMoved(frame), onClose(),
-- resizable -- { minWidth, minHeight, onResized(frame) }: a corner grip to resize,
-- gameSkin -- the game-window look (ui/client_border.lua) instead of the
-- tooltip one: the title goes centered into the title band of the border,
-- titleLeft -- the title at the left edge instead of centered,
-- headerButtons -- { { icon, tooltip, onClick }, ... }: icon buttons left of the
-- close button, the first one nearest to it; frame:SetHeaderButtonsShown(isShown)
-- hides and shows them
function ns.UI.Panel(name, parent, options)
    local frame = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(options.width, options.height)

    local skinned = false
    local headerLayer = nil
    if options.gameSkin then
        skinned, headerLayer = ns.UI.GameSkin(frame)
    end
    if not skinned then
        ApplyTooltipLook(frame)
    end

    -- Our windows share the strata. Without this their child frames (border,
    -- title band, scroll bar) interleave by frame level where two windows
    -- overlap. Toplevel: a click raises the whole window with its children
    -- above the others; a window that opens comes up on top too -- on every
    -- Show, also of a window already open under another one (OnShow does not
    -- come then), and once more on the next frame: a Raise while the window
    -- is only being shown may not take.
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    local function BringToFront(self)
        self:Raise()
        C_Timer.After(0, function()
            if self:IsShown() then
                self:Raise()
            end
        end)
    end
    hooksecurefunc(frame, "Show", BringToFront)
    hooksecurefunc(frame, "SetShown", function(self, isShown)
        if isShown then
            BringToFront(self)
        end
    end)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if options.onMoved then
            options.onMoved(self)
        end
    end)

    local closeButton = nil
    if headerLayer then
        frame.title = headerLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.title:SetPoint("TOP", 0, -1)
        frame.title:SetHeight(TITLE_BAND_HEIGHT - 2)
        closeButton = CreateFrame("Button", nil, headerLayer, "UIPanelCloseButton")
        closeButton:SetSize(closeButton:GetWidth() - CLOSE_BUTTON_SHRINK, closeButton:GetHeight() - CLOSE_BUTTON_SHRINK)
        closeButton:SetPoint("TOPRIGHT", -3, 0)
    else
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.title:SetPoint("TOPLEFT", 12, -10)
        closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeButton:SetSize(24, 24)
        closeButton:SetPoint("TOPRIGHT", -3, -3)
    end
    frame.title:SetText(options.title or "")

    -- icon buttons, right to left from the close button
    local headerButtons = {}
    local leftmost = closeButton
    for _, buttonOptions in ipairs(options.headerButtons or {}) do
        local button = HeaderButton(closeButton:GetParent(), buttonOptions)
        local gap = -HEADER_BUTTON_GAP
        if leftmost == closeButton then
            gap = -HEADER_BUTTON_CLOSE_GAP
        end
        button:SetPoint("RIGHT", leftmost, "LEFT", gap, 0)
        table.insert(headerButtons, button)
        leftmost = button
    end

    -- a left-aligned title ends before the leftmost shown button
    local titleTop = nil
    if options.titleLeft then
        local _, _, _, _, top = frame.title:GetPoint(1)
        titleTop = top
        frame.title:SetJustifyH("LEFT")
        frame.title:SetWordWrap(false)
    end
    local function PlaceTitle(isButtonsShown)
        if not titleTop then return end
        local rightNeighbour = closeButton
        if isButtonsShown and #headerButtons > 0 then
            rightNeighbour = headerButtons[#headerButtons]
        end
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", TITLE_LEFT, titleTop)
        frame.title:SetPoint("RIGHT", rightNeighbour, "LEFT", -HEADER_BUTTON_GAP, 0)
    end
    PlaceTitle(true)

    function frame:SetHeaderButtonsShown(isShown)
        for _, button in ipairs(headerButtons) do
            button:SetShown(isShown)
        end
        PlaceTitle(isShown)
    end

    closeButton:SetScript("OnClick", options.onClose or function()
        frame:Hide()
    end)

    if options.resizable then
        AddResizeGrip(frame, options.resizable)
    end

    return frame
end
end)
