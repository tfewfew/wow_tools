-- Native experience text lifecycle only. No real game APIs, input or timers.
local root = TEST_ROOT or "."
local frames, hookCount, reads = {}, 0, 0
local amount, failed = 12345, false
local secret = setmetatable({}, {
    __eq = function() error("Compared restricted XP") end,
    __tostring = function() error("Printed restricted XP") end,
})
function issecretvalue(value) return rawequal(value, secret) end
function GetXPExhaustion()
    reads = reads + 1
    if failed then error("XP read failed") end
    return amount
end
function BreakUpLargeNumbers() error("The rested XP suffix must contain ungrouped digits") end
C_Timer = {After = function() error("Rested XP must update through native events") end}
function CreateFrame()
    local frame = {events = {}, scripts = {}}
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    frames[#frames + 1] = frame
    return frame
end
function hooksecurefunc(target, method, callback)
    assert(method == "SetBarText", "Rested XP hooked an unrelated native method")
    hookCount = hookCount + 1
    local original = target[method]
    target[method] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end
local function Event(event, unit)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event, unit) end
    end
end
local function Bar(nativeText)
    local text = {value = nativeText, shown = false, fontWrites = 0}
    function text:SetText(value) self.value = value end
    function text:GetText() return self.value end
    function text:SetFont() self.fontWrites = self.fontWrites + 1 end
    local bar = {OverlayFrame = {Text = text}, nativeText = nativeText, updates = 0}
    function bar:SetBarText(value) self.OverlayFrame.Text:SetText(value); return 42 end
    function bar:UpdateCurrentText()
        self.updates = self.updates + 1
        self:SetBarText(self.nativeText)
    end
    return bar
end
local function Text(bar) return bar.OverlayFrame.Text:GetText() end
local primary, secondary, unrelated = Bar("经验 100 / 1000"), Bar("100/1000 (10%)"), Bar("声望")
StatusTrackingBarInfo = {BarsEnum = {Experience = 4}}
StatusTrackingBarManager = {barContainers = {
    primary = {bars = {[4] = primary, [5] = unrelated}},
    secondary = {bars = {[4] = secondary}},
    alias = {bars = {[4] = primary}},
}}
WoWTools = {}
wowDetectorDB = {unrelated = 42, displayFonts = {experience = {size = 20, flags = "OUTLINE"}}}
local source = root .. "/addon/forerver/wow_tools/ExperienceText.lua"
dofile(source)
local module, eventFrame = WoWTools.experienceText, frames[#frames]
Event("PLAYER_ENTERING_WORLD")
assert(not module.IsEnabled() and hookCount == 0 and reads == 0 and not next(eventFrame.events),
    "Old settings must default off without hooks, reads or ongoing events")
assert(wowDetectorDB.displayFonts.showRestedXP == nil, "Startup rewrote an old account setting")
assert(module.SetEnabled(true))
assert(Text(primary) == "经验 100 / 1000（12345）" and Text(secondary) == "100/1000 (10%)（12345）",
    "Native text was replaced, or the suffix contains labels/separators")
assert(hookCount == 2 and primary.updates == 1 and secondary.updates == 1,
    "Experience bar aliases installed duplicate hooks or refreshes")
assert(Text(unrelated) == "声望" and unrelated.updates == 0 and wowDetectorDB.unrelated == 42)
assert(primary.OverlayFrame.Text.fontWrites == 0 and not primary.OverlayFrame.Text.shown,
    "The text suffix changed native font or visibility")
assert(wowDetectorDB.displayFonts.experience.size == 20 and wowDetectorDB.displayFonts.showRestedXP)
primary.nativeText = "新经验 200 / 1000"
primary:UpdateCurrentText()
primary:UpdateCurrentText()
assert(Text(primary) == "新经验 200 / 1000（12345）", "Native updates duplicated or removed the suffix")
assert(primary:SetBarText("自定义原文") == 42 and Text(primary) == "自定义原文（12345）",
    "The native setter's text or return value was lost")
amount = 9876
for _, event in ipairs({"PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD"}) do
    Event(event, "player")
    assert(Text(primary) == "新经验 200 / 1000（9876）", "A native XP event left stale rested XP")
end
local previousReads = reads
Event("PLAYER_XP_UPDATE", "pet")
Event("PLAYER_XP_UPDATE", secret)
assert(reads == previousReads, "Pet XP refreshed the player's suffix")
amount = nil
Event("UPDATE_EXHAUSTION")
assert(Text(primary) == "新经验 200 / 1000（0）", "Exhausted rested XP must display zero")
amount = 1000000
Event("UPDATE_EXHAUSTION")
assert(Text(primary) == "新经验 200 / 1000（1000000）", "Large amounts were grouped or abbreviated")
amount = 123.9
Event("UPDATE_EXHAUSTION")
assert(Text(primary) == "新经验 200 / 1000（123）", "Rested XP must contain integer digits only")
for _, invalid in ipairs({secret, "bad", -1, math.huge, 0/0}) do
    amount = invalid
    Event("UPDATE_EXHAUSTION")
    assert(Text(primary) == primary.nativeText, "Unreadable XP was formatted or retained as a stale amount")
end
failed = true
Event("UPDATE_EXHAUSTION")
assert(Text(primary) == primary.nativeText)
failed = false
local getter = GetXPExhaustion
GetXPExhaustion = nil
Event("UPDATE_EXHAUSTION")
assert(Text(primary) == primary.nativeText)
GetXPExhaustion, amount = getter, 500
primary:SetBarText(secret)
assert(rawequal(Text(primary), secret), "Restricted native text was compared or formatted")
primary:SetBarText("")
assert(Text(primary) == "", "Empty native text acquired a standalone suffix")
primary:UpdateCurrentText()
assert(Text(primary) == "新经验 200 / 1000（500）", "A temporary unreadable value did not recover")
local late = Bar("后加载经验")
StatusTrackingBarManager.barContainers.late = {bars = {[4] = late}}
Event("ADDON_LOADED", "Blizzard_StatusTrackingBar")
assert(Text(late) == "后加载经验（500）" and hookCount == 3, "Late native bars did not acquire the suffix")
assert(module.SetEnabled(false))
assert(Text(primary) == primary.nativeText and Text(secondary) == secondary.nativeText and Text(late) == late.nativeText,
    "Disabling did not immediately restore every native text")
assert(not next(eventFrame.events) and not eventFrame.scripts.OnUpdate, "Disabled suffix left events or polling active")
previousReads = reads
primary:UpdateCurrentText()
Event("UPDATE_EXHAUSTION")
assert(reads == previousReads and Text(primary) == primary.nativeText, "A disabled hook still read/restyled XP")
assert(module.SetEnabled(true) and hookCount == 3, "Re-enabling installed duplicate hooks")
-- A real UI reload recreates the native frames, with the same saved account data.
frames = {}
primary = Bar("重载后的经验")
StatusTrackingBarManager.barContainers = {{bars = {[4] = primary}}}
WoWTools = {}
dofile(source)
Event("PLAYER_ENTERING_WORLD")
module = WoWTools.experienceText
assert(module.IsEnabled() and Text(primary) == "重载后的经验（500）", "Enabled account setting did not survive reload")
module.SetEnabled(false)
frames, WoWTools = {}, {}
primary = Bar("再次重载的经验")
StatusTrackingBarManager.barContainers = {{bars = {[4] = primary}}}
dofile(source)
Event("PLAYER_ENTERING_WORLD")
assert(not WoWTools.experienceText.IsEnabled() and Text(primary) == "再次重载的经验",
    "Disabled account setting did not survive reload")
assert(WoWTools.experienceText.SetEnabled(true))
-- Native widgets may not exist yet, even when the saved option is enabled.
frames, WoWTools = {}, {}
StatusTrackingBarManager, StatusTrackingBarInfo = nil, nil
dofile(source)
Event("PLAYER_ENTERING_WORLD")
primary = Bar("延迟经验")
StatusTrackingBarInfo = {BarsEnum = {Experience = 4}}
StatusTrackingBarManager = {barContainers = {{bars = {[4] = primary}}}}
Event("ADDON_LOADED", "Blizzard_StatusTrackingBar")
assert(Text(primary) == "延迟经验（500）", "Saved option missed late-loaded native widgets")
for _, frame in ipairs(frames) do assert(not frame.scripts.OnUpdate) end
print("PASS: Forever rested XP digits-only suffix, native updates/events, aliases/late bars, on/off/account reload, zero/unknown/restricted reads, untouched visibility/fonts and no polling.")
