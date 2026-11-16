WoWTools.prr.RegisterSource(function(...)
-- icon_tool_button.lua -- a small button with a picture and a tooltip in the
-- look of the game's action buttons: the icon with its own beveled corners
-- inside the slot frame of the action bar, pressed -- the pressed slot.

local ADDON, ns = ...
ns.UI = ns.UI or {}

-- the action bar slot (ActionButtonTemplate): its frame is this much bigger than the button
local SLOT_FRAME_TEXTURE = "Interface\\Buttons\\UI-Quickslot2"
local EMPTY_SLOT_TEXTURE = "Interface\\Buttons\\UI-Quickslot"   -- the dark slot, under an atlas picture
local PUSHED_TEXTURE = "Interface\\Buttons\\UI-Quickslot-Depress"
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"
local SLOT_FRAME_SCALE = 66 / 36
local ATLAS_INSET = 3      -- an atlas picture (no frame of its own) sits inside the slot

-- options: size, icon -- a texture path, or atlas (icon -- the fallback when
-- the client has no such atlas), tooltip, onClick(button, mouseButton),
-- template -- of the button (SecureActionButtonTemplate, optional)
function ns.UI.IconToolButton(parent, options)
    local button = CreateFrame("Button", nil, parent, options.template)
    button:SetSize(options.size, options.size)

    local hasAtlas = options.atlas and C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(options.atlas)
    local icon = button:CreateTexture(nil, "ARTWORK")
    button.icon = icon   -- a texture path can be changed later: button.icon:SetTexture(path)
    if hasAtlas then
        icon:SetAtlas(options.atlas)
        icon:SetPoint("TOPLEFT", ATLAS_INSET, -ATLAS_INSET)
        icon:SetPoint("BOTTOMRIGHT", -ATLAS_INSET, ATLAS_INSET)
    else
        -- the whole icon: its own frame gives the beveled corners of action buttons
        icon:SetTexture(options.icon)
        icon:SetAllPoints()
    end

    local frameSize = options.size * SLOT_FRAME_SCALE
    -- the empty slot goes under an atlas picture, the slot frame over an icon
    local normal = button:CreateTexture(nil, hasAtlas and "BACKGROUND" or "OVERLAY")
    normal:SetTexture(hasAtlas and EMPTY_SLOT_TEXTURE or SLOT_FRAME_TEXTURE)
    normal:SetSize(frameSize, frameSize)
    normal:SetPoint("CENTER")
    button:SetPushedTexture(PUSHED_TEXTURE)
    button:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")

    if options.onClick then
        button:SetScript("OnClick", options.onClick)
    end
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
end)
