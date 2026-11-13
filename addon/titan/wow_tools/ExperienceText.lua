-- Titan 38002: append rested XP through each native experience bar's text setter.
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

local function RemainingXP()
    if type(GetXPExhaustion) ~= "function" then return nil end
    local ok, amount = pcall(GetXPExhaustion)
    if not ok or (issecretvalue and issecretvalue(amount)) then return nil end
    -- Blizzard returns nil when the character has no rested XP left.
    if amount == nil then amount = 0 end
    if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount >= math.huge then
        return nil
    end
    return string.format("%.0f", math.floor(amount))
end

local function AppendRemainingXP(bar, nativeText)
    local record = bars[bar]
    record.nativeText, record.decoratedText = nativeText, nil
    if not module.IsEnabled() or (issecretvalue and issecretvalue(nativeText)) then return end
    if type(nativeText) ~= "string" or nativeText == "" then return end
    local remaining = RemainingXP()
    if remaining then
        record.decoratedText = nativeText .. "（" .. remaining .. "）"
        bar.OverlayFrame.Text:SetText(record.decoratedText)
    end
end

local function Refresh()
    if module.IsEnabled() then
        local experience = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
            and StatusTrackingBarInfo.BarsEnum.Experience
        for _, container in pairs(StatusTrackingBarManager and StatusTrackingBarManager.barContainers or {}) do
            local bar = container.bars and container.bars[experience]
            local text = bar and bar.OverlayFrame and bar.OverlayFrame.Text
            if text and type(text.SetText) == "function" and type(bar.SetBarText) == "function"
                and type(bar.UpdateCurrentText) == "function" and not bars[bar] then
                bars[bar] = {}
                hooksecurefunc(bar, "SetBarText", AppendRemainingXP)
            end
        end
    end
    -- Rebuild from native data both on refresh and when removing our suffix.
    for bar, record in pairs(bars) do
        if not module.IsEnabled() and record.decoratedText then
            local text = bar.OverlayFrame.Text
            local current = text:GetText()
            if not (issecretvalue and issecretvalue(current)) and current == record.decoratedText then
                text:SetText(record.nativeText)
            end
            record.decoratedText = nil
        end
        -- Titan skips UpdateCurrentText at maxBar == 0, so remove our own text first.
        bar:UpdateCurrentText()
    end
end

local function UpdateEvents()
    local enabled = module.IsEnabled()
    for _, event in ipairs(refreshEvents) do
        if enabled then events:RegisterEvent(event)
        else events:UnregisterEvent(event) end
    end
end

function module.SetEnabled(enabled)
    if type(wowDetectorDB) ~= "table" then return false, "插件尚未初始化。" end
    if type(wowDetectorDB.displayFonts) ~= "table" then wowDetectorDB.displayFonts = {} end
    wowDetectorDB.displayFonts.showRestedXP = enabled == true
    UpdateEvents()
    Refresh()
    return true, enabled and "已开启并自动保存。" or "已关闭并自动保存。"
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_XP_UPDATE" and ((issecretvalue and issecretvalue(unit)) or unit ~= "player") then return end
    if event == "PLAYER_ENTERING_WORLD" then UpdateEvents() end
    Refresh()
end)
