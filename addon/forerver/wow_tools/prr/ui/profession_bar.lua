WoWTools.prr.RegisterSource(function(...)
-- profession_bar.lua -- the skill bar of the game's profession window:
--
--   [==== Tailoring 75/150 ====          ]
--
-- The game's own one when it can be had: ProfessionsRankBarTemplate of
-- Blizzard_Professions (loaded on demand) -- the same frame, fill and text as
-- in the profession window. It follows the open profession window by itself
-- (its events); here it shows the profession it is given, so those are off.
-- Without the template: one of our own from the same art (the frame,
-- Skillbar_Fill_Flipbook_<profession> -- DefaultBlue for one without its own),
-- the fill cut to the skill by a clipping frame.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local GAME_TEMPLATE = "ProfessionsRankBarTemplate"
local WIDTH = 453
local HEIGHT = 18                -- the frame of the bar overhangs it below, as in the game
local FILL_WIDTH = 441
local FILL_HEIGHT = 18
local FILL_LEFT = 5
local FILL_TOP = -3
local FLARE_WIDTH = 53
local FLARE_HEIGHT = 16
local TEXT_OFFSET_Y = -2
local TEXT_LEVEL = 5             -- above the frame of the bar
local FILL_ATLAS = "Skillbar_Fill_Flipbook_%s"
local FLARE_ATLAS = "Skillbar_Flare_%s"
local DEFAULT_KIT = "DefaultBlue"
local FLIPBOOK_FRAME_HEIGHT = 34
local FLIPBOOK_COLUMNS = 2
local FLIPBOOK_SECONDS = 2

-- the names of the professions in the atlases (the keys of Enum.Profession),
-- for a client that does not give them
local KITS = {
    [129] = "FirstAid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [185] = "Cooking", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
    [182] = "Herbalism", [186] = "Mining", [393] = "Skinning", [356] = "Fishing",
}

local function HasAtlas(name)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
end

-- The profession (Enum.Profession) of a skill line, as the game gives it.
local function ProfessionEnum(skillLineID)
    local api = C_TradeSkillUI
    if not (api and api.GetProfessionInfoBySkillLineID) then return nil end
    local ok, info = pcall(api.GetProfessionInfoBySkillLineID, skillLineID)
    if ok and type(info) == "table" then
        return info.profession
    end
    return nil
end

-- The name of a profession in the atlases: the key of Enum.Profession, else KITS.
local function KitOf(skillLineID)
    local profession = ProfessionEnum(skillLineID)
    if profession and Enum and Enum.Profession then
        for name, value in pairs(Enum.Profession) do
            if value == profession then
                return name
            end
        end
    end
    return KITS[skillLineID]
end

local function Atlas(format, kit)
    local name = kit and format:format(kit)
    if name and HasAtlas(name) then
        return name
    end
    return nil
end

-- The game's bar, or nil when the client has no such template.
local function CreateGameBar(parent)
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Professions")
    end
    if not rawget(_G, "ProfessionsRankBarMixin") then return nil end
    local ok, bar = pcall(CreateFrame, "Frame", nil, parent, GAME_TEMPLATE)
    if not (ok and bar and bar.Update) then return nil end
    -- the template sits in the BACKGROUND strata: in the window here instead
    bar:SetFrameStrata(parent:GetFrameStrata())
    bar:SetFrameLevel(parent:GetFrameLevel() + 1)
    if bar.Rank then
        bar.Rank:SetFrameLevel(bar:GetFrameLevel() + TEXT_LEVEL)
    end
    -- not the open profession window: the profession given here
    bar:UnregisterAllEvents()
    bar:SetScript("OnShow", nil)
    bar:SetScript("OnHide", nil)
    bar:SetScript("OnEvent", nil)
    if bar.ExpansionDropdownButton then
        bar.ExpansionDropdownButton:Hide()
    end

    function bar:SetSkill(skillLineID, name, skill, maxSkill)
        local info = {
            profession = ProfessionEnum(skillLineID),
            professionName = name or "",
            skillLevel = skill,
            maxSkillLevel = maxSkill,
            skillModifier = 0,
        }
        pcall(self.Update, self, info)
    end
    return bar
end

-- Our own bar from the same art.
local function CreateOwnBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(WIDTH, HEIGHT)

    bar.background = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.background:SetPoint("TOPLEFT")
    bar.background:SetAtlas("Professions-skillbar-bg", true)

    -- the fill is as wide as the whole bar inside a frame as wide as the skill:
    -- the frame cuts it
    bar.clip = CreateFrame("Frame", nil, bar)
    bar.clip:SetPoint("TOPLEFT", FILL_LEFT, FILL_TOP)
    bar.clip:SetSize(FILL_WIDTH, FILL_HEIGHT)
    bar.clip:SetClipsChildren(true)
    local fillHolder = CreateFrame("Frame", nil, bar.clip)
    fillHolder:SetPoint("TOPLEFT")
    fillHolder:SetSize(FILL_WIDTH, FILL_HEIGHT)
    bar.fill = fillHolder:CreateTexture(nil, "ARTWORK")
    bar.fill:SetAllPoints()

    bar.flare = fillHolder:CreateTexture(nil, "OVERLAY")
    bar.flare:SetSize(FLARE_WIDTH, FLARE_HEIGHT)
    bar.flare:SetBlendMode("ADD")
    bar.flare:SetPoint("RIGHT", bar.clip, "RIGHT", 0, 0)

    local front = CreateFrame("Frame", nil, bar)
    front:SetAllPoints()
    front:SetFrameLevel(bar:GetFrameLevel() + TEXT_LEVEL)
    bar.border = front:CreateTexture(nil, "ARTWORK")
    bar.border:SetPoint("TOPLEFT")
    bar.border:SetAtlas("Professions-skillbar-frame", true)
    bar.text = front:CreateFontString(nil, "OVERLAY", "Number12FontOutline")
    bar.text:SetPoint("CENTER", 0, TEXT_OFFSET_Y)

    -- the fill moves once, as in the game, when the skill or the profession changes
    local animation = fillHolder:CreateAnimationGroup()
    local flipbook = animation:CreateAnimation("FlipBook")
    flipbook:SetTarget(bar.fill)
    flipbook:SetDuration(FLIPBOOK_SECONDS)
    flipbook:SetFlipBookColumns(FLIPBOOK_COLUMNS)

    local shownProfession = nil
    local shownRatio = nil

    local function SetArt(skillLineID)
        local kit = KitOf(skillLineID)
        local fillAtlas = Atlas(FILL_ATLAS, kit) or Atlas(FILL_ATLAS, DEFAULT_KIT)
        if fillAtlas then
            bar.fill:SetAtlas(fillAtlas, false)
            local info = C_Texture.GetAtlasInfo(fillAtlas)
            local rows = math.max(1, math.floor(info.height / FLIPBOOK_FRAME_HEIGHT))
            flipbook:SetFlipBookRows(rows)
            flipbook:SetFlipBookFrames(rows * FLIPBOOK_COLUMNS)
        end
        local flareAtlas = Atlas(FLARE_ATLAS, kit)
        bar.flare:SetShown(flareAtlas ~= nil)
        if flareAtlas then
            bar.flare:SetAtlas(flareAtlas, false)
        end
    end

    function bar:SetSkill(skillLineID, name, skill, maxSkill)
        self.text:SetText(string.format("%s %d/%d", name or "", skill, maxSkill))
        local isNewProfession = shownProfession ~= skillLineID
        if isNewProfession then
            shownProfession = skillLineID
            SetArt(skillLineID)
        end
        local ratio = 0
        if maxSkill > 0 then
            ratio = math.min(skill / maxSkill, 1)
        end
        if isNewProfession or ratio ~= shownRatio then
            self.clip:SetWidth(math.max(FILL_WIDTH * ratio, 0.01))
            self.flare:SetAlpha(ratio >= 1 and 0 or 1)
            animation:Restart()
        end
        shownRatio = ratio
    end
    return bar
end

-- bar:SetSkill(skillLineID, name, skill, maxSkill).
function ns.UI.ProfessionBar(parent)
    return CreateGameBar(parent) or CreateOwnBar(parent)
end
end)
