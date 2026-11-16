WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Shared panel appearance. All colors, textures, layers and dimensions are presentation only.

local _, Addon = ...
local panels = {}
function Addon.ApplyAppearance()
    local appearance = Addon.db.appearance or {}
    for _, panel in ipairs(panels) do
        panel:SetBackdropColor(0.035, 0.027, 0.018, appearance.opacity or 0.97)
        panel.raynnaPaper:SetAlpha(appearance.paper == false and 0 or 0.3)
    end
end
Addon.Theme = { gold = { 1, 0.82, 0.18 }, text = { 0.92, 0.86, 0.72 }, muted = { 0.8, 0.74, 0.6 } }
function Addon.SkinPanel(frame, titleBar)
    panels[#panels + 1] = frame
    frame:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8X8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true,
        tileSize = 32,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.035, 0.027, 0.018, 0.97)
    frame:SetBackdropBorderColor(0.74, 0.55, 0.22, 1)
    if not frame.raynnaPaper then
        local paper = frame:CreateTexture(nil, 'BACKGROUND', nil, 1)
        paper:SetPoint('TOPLEFT', 5, titleBar and -27 or -5)
        paper:SetPoint('BOTTOMRIGHT', -5, 5)
        paper:SetTexture('Interface\\AddOns\\wow_tools\\raynna_bestiary\\Media\\RaynnaParchment.tga')
        paper:SetVertexColor(0.42, 0.36, 0.27, 1)
        paper:SetAlpha(0.3)
        frame.raynnaPaper = paper
    end
    if titleBar and not frame.raynnaTitleArt then
        local art = frame:CreateTexture(nil, 'ARTWORK', nil, 0)
        art:SetPoint('TOPLEFT', 4, -4)
        art:SetPoint('TOPRIGHT', -4, -4)
        art:SetHeight(22)
        art:SetColorTexture(0.24, 0.115, 0.035, 1)
        local grain = frame:CreateTexture(nil, 'ARTWORK', nil, 1)
        grain:SetAllPoints(art)
        grain:SetTexture('Interface\\AddOns\\wow_tools\\raynna_bestiary\\Media\\RaynnaParchment.tga')
        grain:SetVertexColor(0.45, 0.22, 0.07, 1)
        grain:SetAlpha(0.4)
        frame.raynnaTitleArt = art
        local line = frame:CreateTexture(nil, 'ARTWORK', nil, 2)
        line:SetPoint('TOPLEFT', 5, -26)
        line:SetPoint('TOPRIGHT', -5, -26)
        line:SetHeight(1)
        line:SetColorTexture(0.63, 0.43, 0.14, 0.9)
    end
    Addon.ApplyAppearance()
end
end)
