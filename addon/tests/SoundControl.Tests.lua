-- Lua 5.1 simulated Forever client. No real sound settings or devices are changed.
local root = TEST_ROOT or "."
local addon = root .. "/addon/forerver/wow_tools/"
local frames, names, sliders = {}, {}, {}
local values = {
    Sound_MasterVolume = "0.37", Sound_EnableAllSound = "1",
    Sound_SFXVolume = "0.82", Sound_EnableSFX = "1",
    Sound_MusicVolume = "0.25", Sound_EnableMusic = "0",
    Sound_AmbienceVolume = "0.49", Sound_EnableAmbience = "1",
    Sound_DialogVolume = "0.63", Sound_EnableDialog = "1",
    Sound_OutputDriverIndex = "0",
}
local deviceNames = { "系统默认", "扬声器", "耳机", "HDMI", "USB 音箱", "蓝牙耳机" }
local writes, restarts = {}, 0
local failWrite, ignoreWrite, failRead, restartFailures, failDevices
local secret = setmetatable({}, {
    __eq = function() error("Compared a restricted value") end,
    __tostring = function() error("Printed a restricted value") end,
})
function issecretvalue(value) return rawequal(value, secret) end

local function widget(kind, name, parent)
    local object = { kind = kind, name = name, parent = parent, scripts = {}, events = {}, children = {}, shown = true, enabled = true }
    if parent then parent.children[#parent.children + 1] = object end
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:RegisterEvent(event) self.events[event] = true end
    function object:UnregisterEvent(event) self.events[event] = nil end
    function object:SetSize(width, height) self.width, self.height = width, height end
    function object:SetWidth(width) self.width = width end
    function object:SetHeight(height) self.height = height end
    function object:GetWidth() return self.width or 140 end
    function object:GetHeight() return self.height or 140 end
    function object:SetPoint(...) self.point = {...} end
    function object:SetText(text) self.text = text end
    function object:SetTexture(texture) self.texture = texture end
    function object:SetEnabled(enabled) self.enabled = enabled end
    function object:IsEnabled() return self.enabled end
    function object:SetShown(shown)
        if self.shown == shown then return end
        self.shown = shown
        local callback = self.scripts[shown and "OnShow" or "OnHide"]
        if callback then callback(self) end
    end
    function object:Show() self:SetShown(true) end
    function object:Hide() self:SetShown(false) end
    function object:IsShown() return self.shown end
    function object:SetValue(value)
        if self.minimum then value = math.max(self.minimum, math.min(self.maximum, value)) end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function object:GetValue() return self.value end
    function object:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
    function object:SetScrollChild(child) self.scrollChild = child end
    function object:SetThumbTexture(path)
        self.thumb = widget("Texture")
        self.thumb:SetTexture(path)
    end
    function object:GetThumbTexture() return self.thumb end
    function object:CreateTexture() return widget("Texture", nil, self) end
    function object:CreateFontString() return widget("FontString", nil, self) end
    function object:GetFrameLevel() return 1 end
    function object:GetCenter() return 100, 100 end
    function object:GetEffectiveScale() return 1 end
    local harmless = {
        "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetMovable", "EnableMouse",
        "RegisterForDrag", "RegisterForClicks", "SetHighlightTexture", "SetOrientation", "SetValueStep",
        "SetObeyStepOnDrag", "SetColorTexture", "SetTextColor", "SetJustifyH", "EnableMouseWheel",
        "StartMoving", "StopMovingOrSizing", "ClearAllPoints", "SetOwner", "AddLine",
    }
    for _, method in ipairs(harmless) do object[method] = function() end end
    return object
end
function CreateFrame(kind, name, parent, template)
    local frame = widget(kind, name, parent)
    if template == "BasicFrameTemplateWithInset" then frame.TitleText = widget("FontString") end
    if name then names[name] = frame; _G[name] = frame end
    frames[#frames + 1] = frame
    if kind == "Slider" then sliders[#sliders + 1] = frame end
    return frame
end
UIParent, Minimap, GameTooltip = widget("Frame"), widget("Frame"), widget("Frame")
SlashCmdList, UISpecialFrames, wowDetectorDB = {}, {}, { unrelated = "keep" }
function GetCursorPosition() return 180, 100 end
function GetMinimapShape() return "ROUND" end
C_CVar = {
    GetCVar = function(key)
        if key == failRead then error("Mock read failure") end
        return values[key]
    end,
    SetCVar = function(key, value)
        writes[#writes + 1] = { key = key, value = value }
        if key == failWrite then return false end
        if key ~= ignoreWrite then values[key] = value end
        -- Exercise synchronous CVar notifications during slider/device writes.
        local panel = names.wowToolsSoundControlPanel
        if panel and panel.events.CVAR_UPDATE then panel.scripts.OnEvent(panel, "CVAR_UPDATE", key) end
    end,
}
function Sound_GameSystem_GetNumOutputDrivers()
    if failDevices then error("Mock enumeration failure") end
    return #deviceNames
end
function Sound_GameSystem_GetOutputDriverNameByIndex(index) return deviceNames[index + 1] end
function Sound_GameSystem_RestartSoundSystem()
    restarts = restarts + 1
    local panel = names.wowToolsSoundControlPanel
    if panel.events.SOUND_DEVICE_UPDATE then panel.scripts.OnEvent(panel, "SOUND_DEVICE_UPDATE") end
    if restartFailures and restartFailures > 0 then restartFailures = restartFailures - 1; return false end
end
local function load()
    dofile(addon .. "Init.lua")
    dofile(addon .. "SoundControl.lua")
    for _, frame in ipairs(frames) do
        if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "wow_tools") end
    end
end
load()
local minimap = names.wowToolsSoundMinimapButton
assert(not names.wowToolsSoundControlPanel and #writes == 0, "Loading wrote audio or eagerly created the panel")
assert(wowDetectorDB.unrelated == "keep" and wowDetectorDB.soundControl.minimapAngle == 315)
assert(minimap.children[1].texture == "Interface\\Common\\VoiceChat-Speaker", "Minimap icon is not a speaker")
minimap.scripts.OnClick(minimap)
local panel = names.wowToolsSoundControlPanel
assert(panel.shown and #sliders == 5 and #writes == 0, "Click did not show all five channels without writes")
assert(panel.width == 480 and panel.height == 466 and panel.TitleText.text == "声音控制")
assert(panel.events.CVAR_UPDATE and panel.events.SOUND_DEVICE_UPDATE)
assert(UISpecialFrames[1] == "wowToolsSoundControlPanel", "Escape does not close the panel")
local toggles, labels, percentages = {}, {}, {}
for _, child in ipairs(panel.children) do
    if child.kind == "Button" then toggles[#toggles + 1] = child end
    if child.kind == "FontString" and child.point and child.point[1] == "LEFT" then
        if child.width == 44 then percentages[#percentages + 1] = child
        else labels[#labels + 1] = child end
    end
end
assert(#toggles == 5 and #labels == 5 and #percentages == 5)
local channelKeys = { "Master", "SFX", "Music", "Ambience", "Dialog" }
local enableKeys = { "AllSound", "SFX", "Music", "Ambience", "Dialog" }
for index, key in ipairs(channelKeys) do
    assert(sliders[index].minimum == 0 and sliders[index].maximum == 100)
    assert(percentages[index].point[2] == sliders[index] and percentages[index].point[3] == "RIGHT", "Number is not after its slider")
    local before = #writes
    sliders[index]:SetValue(11 + index)
    assert(#writes == before + 1 and writes[#writes].key == "Sound_" .. key .. "Volume", "Slider wrote another channel")
    assert(percentages[index].text == (11 + index) .. "%")
    local enableKey = "Sound_Enable" .. enableKeys[index]
    local volume = values["Sound_" .. key .. "Volume"]
    local expected = values[enableKey] == "1" and "0" or "1"
    before = #writes
    toggles[index].scripts.OnClick()
    assert(#writes == before + 1 and values[enableKey] == expected, "Toggle changed multiple channels")
    assert(values["Sound_" .. key .. "Volume"] == volume, "Disabling lost the channel volume")
    toggles[index].scripts.OnClick()
end
sliders[2]:SetValue(0)
assert(percentages[2].text == "0%" and values.Sound_EnableSFX == "1", "Zero volume changed its switch")
sliders[2]:SetValue(100)
sliders[2].scripts.OnMouseWheel(sliders[2], -1)
assert(values.Sound_SFXVolume == "0.99" and percentages[2].text == "99%")
local before = #writes
sliders[2]:SetValue(99)
assert(#writes == before, "Identical slider value rewrote the CVar")
failWrite = "Sound_SFXVolume"
sliders[2]:SetValue(20)
assert(sliders[2].value == 99 and panel.status.text:find("失败"), "Failed write displayed success")
failWrite, ignoreWrite = nil, "Sound_SFXVolume"
sliders[2]:SetValue(20)
assert(sliders[2].value == 99 and panel.status.text:find("失败"), "Ignored write displayed success")
ignoreWrite = nil
values.Sound_DialogVolume, values.Sound_EnableDialog = secret, secret
panel.scripts.OnEvent(panel, "CVAR_UPDATE", "Sound_DialogVolume")
assert(not sliders[5].enabled and not toggles[5].enabled and percentages[5].text == "—")
for _, value in ipairs({ "nan", "inf", "-0.1", "1.01", "invalid" }) do
    values.Sound_DialogVolume = value
    panel.scripts.OnEvent(panel, "CVAR_UPDATE", "Sound_DialogVolume")
    assert(not sliders[5].enabled, "Invalid volume remained editable")
end
values.Sound_DialogVolume, values.Sound_EnableDialog = "0.63", "1"
failRead = "Sound_DialogVolume"
panel.scripts.OnEvent(panel, "CVAR_UPDATE", "Sound_DialogVolume")
assert(not sliders[5].enabled)
failRead = nil
panel.scripts.OnEvent(panel, "CVAR_UPDATE", "Sound_DialogVolume")
assert(sliders[5].enabled and percentages[5].text == "63%")

-- All output devices live in this panel's scroll content, with no nested menu.
local devices = {}
for _, child in ipairs(panel.deviceContent.children) do
    if child.kind == "Button" then devices[#devices + 1] = child end
end
assert(#devices == 6 and panel.deviceContent.height == 156 and panel.deviceScroll.height == 104)
assert(devices[1].mark.shown and not devices[2].mark.shown)
before = #writes
devices[1].scripts.OnClick(devices[1])
assert(#writes == before and restarts == 0, "Current device restarted sound")
devices[3].scripts.OnClick(devices[3])
assert(values.Sound_OutputDriverIndex == "2" and restarts == 1 and devices[3].mark.shown)
restartFailures = 1
devices[2].scripts.OnClick(devices[2])
assert(values.Sound_OutputDriverIndex == "2" and restarts == 3 and panel.status.text:find("已恢复"), "Restart failure did not restore original device")
failWrite = "Sound_OutputDriverIndex"
devices[2].scripts.OnClick(devices[2])
assert(values.Sound_OutputDriverIndex == "2" and panel.status.text:find("失败"))
failWrite = nil
restartFailures = 2
devices[2].scripts.OnClick(devices[2])
assert(panel.status.text:find("请检查"), "Rollback failure was reported as restored")
restartFailures = nil
before = #writes
deviceNames[2] = "新插入的设备"
devices[2].scripts.OnClick(devices[2])
assert(#writes == before and devices[2].deviceName == "新插入的设备", "Stale device index selected a different driver")
Sound_GameSystem_RestartSoundSystem = nil
panel.scripts.OnEvent(panel, "SOUND_DEVICE_UPDATE")
assert(not devices[2].enabled, "Device switching without restart API stayed enabled")
failDevices = true
panel.scripts.OnEvent(panel, "SOUND_DEVICE_UPDATE")
assert(panel.deviceEmpty.shown and not devices[1].shown)
failDevices, deviceNames = nil, {}
panel.scripts.OnEvent(panel, "SOUND_DEVICE_UPDATE")
assert(panel.deviceEmpty.shown and panel.deviceEmpty.text:find("未找到"))

-- Hidden panels unsubscribe, reopening reflects external settings without writes.
minimap.scripts.OnClick(minimap)
assert(not panel.shown and not panel.events.CVAR_UPDATE and not panel.events.SOUND_DEVICE_UPDATE)
values.Sound_MusicVolume = "0.71"
before = #writes
SlashCmdList.WOWTOOLSSOUND()
assert(panel.shown and percentages[3].text == "71%" and #writes == before)
minimap.scripts.OnDragStart(minimap)
minimap.scripts.OnUpdate()
assert(wowDetectorDB.soundControl.minimapAngle == 0)
minimap.scripts.OnDragStop(minimap)
assert(not minimap.scripts.OnUpdate)
GetMinimapShape = function() return "SQUARE" end
minimap.scripts.OnDragStart(minimap)
minimap.scripts.OnUpdate()
minimap.scripts.OnHide(minimap)
assert(not minimap.scripts.OnUpdate)
for _, frame in ipairs(frames) do assert(not frame.scripts.OnUpdate, "Sound control left a permanent update loop") end
local saved = wowDetectorDB
frames, names, sliders = {}, {}, {}
load()
assert(wowDetectorDB == saved and wowDetectorDB.soundControl.minimapAngle == 0, "Reload lost minimap settings")
before = #writes
SlashCmdList.WOWTOOLSSOUND()
assert(#writes == before and sliders[3].value == 71, "Reload overwrote native sound settings")
print("PASS: Forever sound control, five independent sliders/numbers/switches, inline scrollable devices, current/readback/hotplug/restart/rollback failures, restricted data, events, drag and reload.")
