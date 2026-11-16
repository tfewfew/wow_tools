WoWTools.prr.RegisterSource(function(...)
-- favorite_star.lua -- the star badge in the top right corner of an item icon
-- (bag slots, icons of the item window) and the star toggle of the window title.
-- The stars are the ones of the auction house favorites.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local STAR_ATLAS = "auctionhouse-icon-favorite"
local STAR_OFF_ATLAS = "auctionhouse-icon-favorite-off"
local FALLBACK_STAR_TEXT = "*"
local CORNER_STAR_SIZE = 14
-- the badge sticks out of the icon corner: this many pixels for a star of
-- CORNER_STAR_SIZE, smaller stars -- in proportion
local CORNER_OUTSET = 3
local SHADOW_GROWTH = 5          -- the dark outline is this much bigger than the star
local SHADOW_COLOR = { 0, 0, 0, 0.85 }
local BADGE_LEVEL_ABOVE = 10     -- above the border, count and icons of bag addons
local TOGGLE_HOVER_ALPHA = 1
local TOGGLE_OFF_ALPHA = 0.6

local hasStarAtlas = nil

local function HasStarAtlas()
    if hasStarAtlas == nil then
        hasStarAtlas = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil
            and C_Texture.GetAtlasInfo(STAR_ATLAS) ~= nil
    end
    return hasStarAtlas
end

-- The badge: a frame of its own above the button, a dark outline under the star.
local function CreateBadge(button)
    local badge = CreateFrame("Frame", nil, button)
    badge:SetFrameLevel(button:GetFrameLevel() + BADGE_LEVEL_ABOVE)

    badge.shadow = badge:CreateTexture(nil, "ARTWORK", nil, 0)
    badge.shadow:SetPoint("CENTER")
    badge.star = badge:CreateTexture(nil, "ARTWORK", nil, 1)
    badge.star:SetAllPoints()
    if HasStarAtlas() then
        badge.shadow:SetAtlas(STAR_ATLAS)
        badge.shadow:SetVertexColor(SHADOW_COLOR[1], SHADOW_COLOR[2], SHADOW_COLOR[3], SHADOW_COLOR[4])
        badge.star:SetAtlas(STAR_ATLAS)
    else
        badge.shadow:SetColorTexture(SHADOW_COLOR[1], SHADOW_COLOR[2], SHADOW_COLOR[3], SHADOW_COLOR[4])
        badge.star:SetColorTexture(1, 0.82, 0, 1)
    end
    return badge
end

-- Shows or hides the star badge of an item button (created on first need).
-- size -- the star size, CORNER_STAR_SIZE if not given.
function ns.UI.SetFavoriteStar(button, isShown, size)
    local badge = button.prrFavoriteStar
    if not badge then
        if not isShown then return end
        badge = CreateBadge(button)
        button.prrFavoriteStar = badge
    end
    local starSize = size or CORNER_STAR_SIZE
    local outset = math.floor(CORNER_OUTSET * starSize / CORNER_STAR_SIZE + 0.5)
    badge:SetSize(starSize, starSize)
    badge:ClearAllPoints()
    badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", outset, outset)
    badge.shadow:SetSize(starSize + SHADOW_GROWTH, starSize + SHADOW_GROWTH)
    badge:SetShown(isShown and true or false)
end

-- The star toggle: options -- size, tooltipOn, tooltipOff, onClick().
-- toggle:SetFavorite(isFavorite) -- filled or empty.
function ns.UI.FavoriteToggle(parent, options)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(options.size, options.size)
    local icon = toggle:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    local fallback = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fallback:SetPoint("CENTER")

    function toggle:SetFavorite(isFavorite)
        self.isFavorite = isFavorite
        if HasStarAtlas() then
            if isFavorite then
                icon:SetAtlas(STAR_ATLAS)
            else
                icon:SetAtlas(STAR_OFF_ATLAS)
            end
        else
            fallback:SetText(FALLBACK_STAR_TEXT)
            fallback:SetAlpha(isFavorite and 1 or TOGGLE_OFF_ALPHA)
        end
        icon:SetAlpha(isFavorite and 1 or TOGGLE_OFF_ALPHA)
    end

    toggle:SetScript("OnClick", options.onClick)
    toggle:SetScript("OnEnter", function(self)
        icon:SetAlpha(TOGGLE_HOVER_ALPHA)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.isFavorite and options.tooltipOn or options.tooltipOff)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function(self)
        icon:SetAlpha(self.isFavorite and 1 or TOGGLE_OFF_ALPHA)
        GameTooltip:Hide()
    end)
    toggle:SetFavorite(false)
    return toggle
end
end)
