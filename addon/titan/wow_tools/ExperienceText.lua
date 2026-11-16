-- Titan 38002: append optional XP details through each native experience bar's text setter.
local module = {}
WoWTools.experienceText = module

local bars = {}
local events = CreateFrame("Frame")
local refreshEvents = {
    "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "PLAYER_XP_UPDATE",
    "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING",
}

function module.IsEnabled()
    local config = wowDetectorDB and wowDetectorDB.displayFonts
    return type(config) == "table" and config.showRestedXP == true
end

function module.IsPercentEnabled()
    local config = wowDetectorDB and wowDetectorDB.displayFonts
    return type(config) == "table" and config.showXPPercent == true
end

local function IsActive()
    return module.IsEnabled() or module.IsPercentEnabled()
end

local function RequiredXP()
    if type(UnitXPMax) ~= "function" then return nil end
    local ok, maximum = pcall(UnitXPMax, "player")
    if not ok or (issecretvalue and issecretvalue(maximum)) then return nil end
    if type(maximum) ~= "number" or maximum ~= maximum or maximum <= 0 or maximum >= math.huge then
        return nil
    end
    return maximum
end

local function RemainingXP(maximum)
    if type(GetXPExhaustion) ~= "function" then return nil end
    local ok, amount = pcall(GetXPExhaustion)
    if not ok or (issecretvalue and issecretvalue(amount)) then return nil end
    -- Blizzard returns nil when the character has no rested XP left.
    if amount == nil then amount = 0 end
    if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount >= math.huge then
        return nil
    end
    local text = string.format("%.0f", math.floor(amount))
    if maximum then text = text .. "-" .. string.format("%.1f%%", amount / maximum * 100) end
    return text
end

local function CurrentXPPercent(maximum)
    if not maximum or type(UnitXP) ~= "function" then return nil end
    local currentOK, current = pcall(UnitXP, "player")
    if not currentOK or (issecretvalue and issecretvalue(current)) then return nil end
    if type(current) ~= "number" or current ~= current or current < 0 or current >= math.huge
        or current > maximum then return nil end
    return string.format("%.1f%%", current / maximum * 100)
end

local function AppendExperienceInfo(bar, nativeText)
    local record = bars[bar]
    record.nativeText, record.decoratedText = nativeText, nil
    if not IsActive() or (issecretvalue and issecretvalue(nativeText)) then return end
    if type(nativeText) ~= "string" or nativeText == "" then return end
    local maximum = RequiredXP()
    local suffix = module.IsEnabled() and RemainingXP(maximum) or nil
    local percent = module.IsPercentEnabled() and CurrentXPPercent(maximum) or nil
    if suffix or percent then
        local decoratedText = nativeText
        if percent then decoratedText = decoratedText .. "-" .. percent end
        if suffix then decoratedText = decoratedText .. "（" .. suffix .. "）" end
        record.decoratedText = decoratedText
        bar.OverlayFrame.Text:SetText(record.decoratedText)
    end
end

local function Refresh()
    if IsActive() then
        local experience = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
            and StatusTrackingBarInfo.BarsEnum.Experience
        for _, container in pairs(StatusTrackingBarManager and StatusTrackingBarManager.barContainers or {}) do
            local bar = container.bars and container.bars[experience]
            local text = bar and bar.OverlayFrame and bar.OverlayFrame.Text
            if text and type(text.SetText) == "function" and type(bar.SetBarText) == "function"
                and type(bar.UpdateCurrentText) == "function" and not bars[bar] then
                bars[bar] = {}
                hooksecurefunc(bar, "SetBarText", AppendExperienceInfo)
            end
        end
    end
    -- Rebuild from native data both on refresh and when removing our suffix.
    for bar, record in pairs(bars) do
        if record.decoratedText then
            local text = bar.OverlayFrame.Text
            local current = text:GetText()
            if not (issecretvalue and issecretvalue(current)) and current == record.decoratedText then
                text:SetText(record.nativeText)
            end
            record.decoratedText = nil
        end
        -- Titan skips UpdateCurrentText at maxBar == 0, so remove our own text first.
        bar:UpdateCurrentText()
        if IsActive() and not record.decoratedText then
            AppendExperienceInfo(bar, bar.OverlayFrame.Text:GetText())
        end
    end
end

local function UpdateEvents()
    local enabled = IsActive()
    for _, event in ipairs(refreshEvents) do
        if enabled then events:RegisterEvent(event)
        else events:UnregisterEvent(event) end
    end
end

local function SetOption(key, enabled)
    if type(wowDetectorDB) ~= "table" then return false, "插件尚未初始化。" end
    if type(wowDetectorDB.displayFonts) ~= "table" then wowDetectorDB.displayFonts = {} end
    wowDetectorDB.displayFonts[key] = enabled == true
    UpdateEvents()
    Refresh()
    return true, enabled and "已开启并自动保存。" or "已关闭并自动保存。"
end

function module.SetEnabled(enabled)
    return SetOption("showRestedXP", enabled)
end

function module.SetPercentEnabled(enabled)
    return SetOption("showXPPercent", enabled)
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_XP_UPDATE" and ((issecretvalue and issecretvalue(unit)) or unit ~= "player") then return end
    if event == "PLAYER_ENTERING_WORLD" then UpdateEvents() end
    Refresh()
    if event == "PLAYER_LEVEL_UP" then
        -- Read the new level's XP requirement again after the level-up event finishes.
        C_Timer.After(0, function()
            if IsActive() then Refresh() end
        end)
    end
end)
