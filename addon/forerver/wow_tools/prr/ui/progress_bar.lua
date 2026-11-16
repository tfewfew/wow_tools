WoWTools.prr.RegisterSource(function(...)
-- progress_bar.lua -- a progress bar in the look of the game's cast bar: the
-- fill with a spark in a frame, an item icon on the left, a text on the bar.
-- At the end it flashes, holds and fades out.
--
-- Drawn with the textures of the game's own cast bar (the same atlases as the
-- cast bar of the Dkp addon), with plain ones for a client without them.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local ICON_GAP = 6
local SPARK_WIDTH = 12
local SPARK_EXTRA_HEIGHT = 10
local FINISH_HOLD_SECONDS = 1.2
local FINISH_FADE_SECONDS = 0.6
local FLASH_IN_SECONDS = 0.15
local FLASH_OUT_SECONDS = 0.6
local FALLBACK_FILL_COLOR = { 1, 0.7, 0 }
local FALLBACK_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local QUESTION_MARK_ICON = 134400
local OUTLINE_FONT_OBJECT = "GameFontHighlightSmallOutline"   -- white, a black outline around the letters

local ATLAS = {
    fill = "ui-castingbar-filling-standard",
    background = "ui-castingbar-background",
    border = "ui-castingbar-frame",
    spark = "ui-castingbar-pip",
    flash = "ui-castingbar-full-glow-standard",
}

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A texture of the bar from an atlas; nil if the client has no such atlas.
local function AtlasTexture(bar, layer, subLevel, atlas)
    if not HasAtlas(atlas) then
        return nil
    end
    local texture = bar:CreateTexture(nil, layer, nil, subLevel)
    texture:SetAtlas(atlas)
    return texture
end

local function CreateTextures(bar, height)
    if HasAtlas(ATLAS.fill) then
        bar:SetStatusBarTexture(bar:CreateTexture(nil, "ARTWORK"))
        bar:GetStatusBarTexture():SetAtlas(ATLAS.fill)
    else
        bar:SetStatusBarTexture(FALLBACK_BAR_TEXTURE)
        bar:SetStatusBarColor(FALLBACK_FILL_COLOR[1], FALLBACK_FILL_COLOR[2], FALLBACK_FILL_COLOR[3])
    end

    local background = AtlasTexture(bar, "BACKGROUND", 2, ATLAS.background)
    if not background then
        background = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
        background:SetColorTexture(0, 0, 0, 0.6)
    end
    background:SetPoint("TOPLEFT", -1, 1)
    background:SetPoint("BOTTOMRIGHT", 1, -1)

    local border = AtlasTexture(bar, "OVERLAY", 0, ATLAS.border)
    if border then
        border:SetPoint("TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", 2, -2)
    end

    bar.spark = AtlasTexture(bar, "OVERLAY", 2, ATLAS.spark)
    if bar.spark then
        bar.spark:SetSize(SPARK_WIDTH, height + SPARK_EXTRA_HEIGHT)
    end

    bar.flash = AtlasTexture(bar, "OVERLAY", 1, ATLAS.flash)
    if bar.flash then
        bar.flash:SetBlendMode("ADD")
        bar.flash:SetPoint("TOPLEFT", -1, 1)
        bar.flash:SetPoint("BOTTOMRIGHT", 1, -1)
        bar.flash:SetAlpha(0)
    end
end

local function AddAlpha(group, from, to, seconds, order, delay)
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    alpha:SetDuration(seconds)
    alpha:SetOrder(order)
    if delay then
        alpha:SetStartDelay(delay)
    end
end

-- options: height (of the bar itself), iconSize. Place it with SetPoint: the
-- icon sticks out on the left by iconSize + a gap, leave room for it.
-- bar:SetProgress(done, total), bar:SetText(text) -- on the bar, bar:SetItem(itemID),
-- bar:PlayFinish(onHidden) -- flash, hold, fade out, hide.
function ns.UI.ProgressBar(parent, options)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(options.height)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    CreateTextures(bar, options.height)

    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(options.iconSize, options.iconSize)
    bar.icon:SetPoint("RIGHT", bar, "LEFT", -ICON_GAP, 0)

    -- the text on a layer of its own: above the fill, the border and the spark
    local textLayer = CreateFrame("Frame", nil, bar)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.text = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- the whole bar, the text in its middle both ways: an outlined font is
    -- taller than its letters, centering the font string alone puts them high
    bar.text:SetPoint("TOPLEFT", 4, 0)
    bar.text:SetPoint("BOTTOMRIGHT", -4, 0)
    bar.text:SetJustifyH("CENTER")
    bar.text:SetJustifyV("MIDDLE")
    bar.text:SetWordWrap(false)
    -- a black outline and shadow: readable over the bright fill. The game's
    -- outlined font object, not SetFont with a file: a font object is a family
    -- with the Cyrillic and Chinese fonts in it, a bare file (FRIZQT__.TTF of an
    -- English client) draws Russian as squares
    local outlineFont = rawget(_G, OUTLINE_FONT_OBJECT)
    if outlineFont then
        bar.text:SetFontObject(outlineFont)
    end
    bar.text:SetShadowColor(0, 0, 0, 1)
    bar.text:SetShadowOffset(1, -1)

    local onHidden = nil
    local finish = bar:CreateAnimationGroup()
    AddAlpha(finish, 1, 0, FINISH_FADE_SECONDS, 1, FINISH_HOLD_SECONDS)
    finish:SetScript("OnFinished", function()
        bar:Hide()
        bar:SetAlpha(1)
        if onHidden then
            onHidden()
        end
    end)
    local flashAnimation = nil
    if bar.flash then
        flashAnimation = bar.flash:CreateAnimationGroup()
        AddAlpha(flashAnimation, 0, 1, FLASH_IN_SECONDS, 1)
        AddAlpha(flashAnimation, 1, 0, FLASH_OUT_SECONDS, 2)
    end

    function bar:SetProgress(done, total)
        local progress = 0
        if total > 0 then
            progress = done / total
        end
        self:SetValue(progress)
        if self.spark then
            self.spark:ClearAllPoints()
            self.spark:SetPoint("CENTER", self, "LEFT", self:GetWidth() * progress, 0)
            self.spark:SetShown(progress > 0 and progress < 1)
        end
    end

    function bar:SetText(text)
        self.text:SetText(text)
    end

    function bar:SetItem(itemID)
        local icon = itemID and C_Item.GetItemIconByID(itemID) or nil
        self.icon:SetTexture(icon or QUESTION_MARK_ICON)
    end

    function bar:SetIcon(texture)
        self.icon:SetTexture(texture)
    end

    -- A new run: the bar is shown at once, a fade still going is dropped.
    function bar:Start()
        finish:Stop()
        self:SetAlpha(1)
        self:Show()
    end

    function bar:PlayFinish(onFinishHidden)
        onHidden = onFinishHidden
        if flashAnimation then
            flashAnimation:Play()
        end
        finish:Play()
    end

    function bar:IsFinishing()
        return finish:IsPlaying()
    end

    bar:Hide()
    return bar
end
end)
