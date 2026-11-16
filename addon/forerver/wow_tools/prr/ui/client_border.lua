WoWTools.prr.RegisterSource(function(...)
-- client_border.lua -- a border exactly like the game's own windows (game menu,
-- options): thin bronze-gold edges with beveled corners.
--
-- The game draws those borders with NineSlice layouts. The layout name is not
-- guessed but asked from the game windows: their NineSlice knows its layoutType, and
-- NineSliceUtil.ApplyLayoutByName puts the same layout on our frame; a layout
-- with a title band wins. Guessing
-- failed before: DialogBorderTemplate exists but is the old dialog border.
-- Same approach as the window skin in SimpleQuestingTools.

local ADDON, ns = ...
ns.UI = ns.UI or {}

-- windows to ask, the game menu first: its style is the one we want
local DONORS = {
    "GameMenuFrame", "SettingsPanel", "QuestLogFrame", "CharacterFrame",
    "SpellBookFrame", "FriendsFrame", "MerchantFrame", "MailFrame",
}

local FALLBACK_TEMPLATE = "DialogBorderTemplate"

local TITLE_BAND_MIN_HEIGHT = 16   -- a top edge this tall comes with a title band

-- What the last border was made from, for debugging: "layout X from window Y",
-- "template X" or nil if nothing worked.
ns.UI.clientBorderSource = nil

-- The layouts of the game windows, each once, in the order of DONORS.
local function ClientLayouts()
    local layouts, seen = {}, {}
    for _, name in ipairs(DONORS) do
        local donor = _G[name]
        local layout = donor and ((donor.NineSlice and donor.NineSlice.layoutType) or donor.layoutType)
        if type(layout) == "string" and not seen[layout] then
            seen[layout] = true
            table.insert(layouts, { layout = layout, donor = name })
        end
    end
    return layouts
end

-- Did the border pieces get created? A layout or template can be found but draw nothing.
local function IsPainted(border)
    return (border.TopLeftCorner or border.TopEdge or border.NineSlice) ~= nil
end

local function HasTitleBand(border)
    return border.TopEdge ~= nil and border.TopEdge:GetHeight() >= TITLE_BAND_MIN_HEIGHT
end

local function ApplyLayout(frame, layout)
    local border = CreateFrame("Frame", nil, frame)
    border:SetAllPoints()
    local ok = pcall(NineSliceUtil.ApplyLayoutByName, border, layout)
    if ok and IsPainted(border) then
        return border
    end
    border:Hide()
    return nil
end

-- The first game layout with a title band; without one -- the first that draws.
-- Which window has which layout differs between client builds (the game menu
-- lost its title band once), so every donor is tried.
local function LayoutBorder(frame)
    if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName) then
        return nil
    end
    local fallback, fallbackSource = nil, nil
    for _, candidate in ipairs(ClientLayouts()) do
        local border = ApplyLayout(frame, candidate.layout)
        if border and HasTitleBand(border) then
            if fallback then fallback:Hide() end
            ns.UI.clientBorderSource = "layout " .. candidate.layout .. " from " .. candidate.donor
            return border
        end
        if border and not fallback then
            fallback = border
            fallbackSource = "layout " .. candidate.layout .. " from " .. candidate.donor
        elseif border then
            border:Hide()
        end
    end
    ns.UI.clientBorderSource = fallbackSource
    return fallback
end

local function TemplateBorder(frame)
    local ok, border = pcall(CreateFrame, "Frame", nil, frame, FALLBACK_TEMPLATE)
    if not ok or not border then
        return nil
    end
    if not IsPainted(border) then
        border:Hide()
        return nil
    end
    border:SetAllPoints()
    ns.UI.clientBorderSource = "template " .. FALLBACK_TEMPLATE
    return border
end

-- Put a game-window border around frame. Returns the border frame, or nil if
-- neither the client layout nor the fallback template drew anything.
-- The border has no middle: put your own background under it.
function ns.UI.ClientBorder(frame)
    return LayoutBorder(frame) or TemplateBorder(frame)
end

local SKIN_BACKGROUND_COLOR = { 0.04, 0.04, 0.05, 0.95 }
local SKIN_BACKGROUND_INSET = 3
-- the brown background of the Forever character list, the same as the alert banner
local SKIN_BACKGROUND_ATLAS = "heavybronze-frame-background"

-- Window background under a game-window border: the alert banner's brown
-- atlas, or a dark color on a client without it. Returns the texture.
function ns.UI.WindowBackground(frame)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", SKIN_BACKGROUND_INSET, -SKIN_BACKGROUND_INSET)
    background:SetPoint("BOTTOMRIGHT", -SKIN_BACKGROUND_INSET, SKIN_BACKGROUND_INSET)

    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SKIN_BACKGROUND_ATLAS)
    if hasAtlas then
        background:SetAtlas(SKIN_BACKGROUND_ATLAS)
    else
        background:SetColorTexture(SKIN_BACKGROUND_COLOR[1], SKIN_BACKGROUND_COLOR[2],
            SKIN_BACKGROUND_COLOR[3], SKIN_BACKGROUND_COLOR[4])
    end
    return background
end
-- The game-window skin for our window: dark background under the game border.
-- Returns false if no border could be drawn (the window keeps its own look),
-- otherwise true and, when the border has a title band, a layer above the
-- border for the title and the close button (the border covers the window's
-- own regions there).
function ns.UI.GameSkin(frame)
    local border = ns.UI.ClientBorder(frame)
    if not border then
        return false
    end

    ns.UI.WindowBackground(frame)

    local topEdgeHeight = border.TopEdge and border.TopEdge:GetHeight() or 0
    if topEdgeHeight < TITLE_BAND_MIN_HEIGHT then
        return true
    end
    local headerLayer = CreateFrame("Frame", nil, frame)
    headerLayer:SetAllPoints()
    headerLayer:SetFrameLevel(border:GetFrameLevel() + 2)
    return true, headerLayer
end
end)
