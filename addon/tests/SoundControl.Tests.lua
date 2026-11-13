-- Lua 5.1 simulated Forever client. No real sound settings or devices are changed.
local flavor = TEST_FLAVOR or "forerver"
local root = TEST_ROOT or "."
local addon = root .. "/addon/"..flavor.."/wow_tools/"
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
    function object:SetAllPoints(target) self.fill = target or self.parent end
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:RegisterEvent(event) self.events[event] = true end
    function object:UnregisterEvent(event) self.events[event] = nil end
    function object:SetSize(width, height) self.width, self.height = width, height end
    function object:SetWidth(width) self.width = width end
    function object:SetHeight(height) self.height = height end
    function object:GetWidth() return self.fill and self.fill:GetWidth() or self.width or 140 end
    function object:GetHeight() return self.fill and self.fill:GetHeight() or self.height or 140 end
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
    function object:SetThumbTexture(path)
        self.thumb = widget("Texture")
        self.thumb:SetTexture(path)
    end
    function object:GetThumbTexture() return self.thumb end
    function object:CreateTexture() return widget("Texture", nil, self) end
    function object:CreateFontString() return widget("FontString", nil, self) end
    function object:GetFrameLevel() return 1 end
    function object:GetCenter() return self.centerX or 100, self.centerY or 100 end
    function object:GetEffectiveScale() return self.scale or 1 end
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
    if kind == "DropdownButton" then
        assert(template == "WowStyle1DropdownTemplate", "Not using Forever's native dropdown")
        function frame:SetDefaultText(text) self.defaultText = text end
        function frame:GenerateMenu()
            local description = { entries = {} }
            function description:SetScrollMode(height) self.scrollHeight = height end
            function description:CreateRadio(text, isSelected, onSelect, data)
                self.entries[#self.entries + 1] = { text = text, isSelected = isSelected, onSelect = onSelect, data = data }
            end
            self.generator(self, description)
            self.description = description
            self.text = self.defaultText
            for _, entry in ipairs(description.entries) do
                if entry.isSelected(entry.data) then self.text = entry.text end
            end
        end
        function frame:SetupMenu(generator) self.generator = generator; self:GenerateMenu() end
        function frame:OpenMenu()
            if self.enabled then self:GenerateMenu(); self.menuOpen = true end
        end
        function frame:CloseMenu() self.menuOpen = false end
    end
    if name then names[name] = frame; _G[name] = frame end
    frames[#frames + 1] = frame
    if kind == "Slider" then sliders[#sliders + 1] = frame end
    return frame
end
UIParent, Minimap, GameTooltip = widget("Frame"), widget("Frame"), widget("Frame")
UIParent.centerX, UIParent.centerY = 960, 540
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
minimap.centerX, minimap.centerY = 1820, 940
assert(not names.wowToolsSoundControlPanel and #writes == 0, "Loading wrote audio or eagerly created the panel")
assert(wowDetectorDB.unrelated == "keep" and wowDetectorDB.soundControl.minimapAngle == 315)
assert(minimap.children[1].texture == "Interface\\Common\\VoiceChat-Speaker", "Minimap icon is not a speaker")
minimap.scripts.OnClick(minimap)
local panel = names.wowToolsSoundControlPanel
assert(panel.shown and #sliders == 5 and #writes == 0, "Click did not show all five channels without writes")
assert(panel.width == 344 and panel.height == 240 and panel.TitleText.text == "声音控制")
assert(panel.point[1] == "TOPRIGHT" and panel.point[2] == minimap and panel.point[3] == "BOTTOMLEFT"
    and panel.point[4] == -4 and panel.point[5] == -4, "Panel did not open beside the top-right icon")
assert(panel.events.CVAR_UPDATE and panel.events.SOUND_DEVICE_UPDATE)
assert(UISpecialFrames[1] == "wowToolsSoundControlPanel", "Escape does not close the panel")
local toggles, labels, percentages = {}, {}, {}
for _, child in ipairs(panel.children) do
    if child.kind == "Button" then toggles[#toggles + 1] = child end
    if child.kind == "FontString" and child.point and child.point[1] == "LEFT" then
        if child.width == 40 then percentages[#percentages + 1] = child
        elseif child.point[5] >= -150 then labels[#labels + 1] = child end
    end
end
assert(#toggles == 5 and #labels == 5 and #percentages == 5)
local channelKeys = { "Master", "SFX", "Music", "Ambience", "Dialog" }
local enableKeys = { "AllSound", "SFX", "Music", "Ambience", "Dialog" }
for index, key in ipairs(channelKeys) do
    assert(sliders[index].minimum == 0 and sliders[index].maximum == 100)
    assert(sliders[index].width == 150 and sliders[index].height == 16)
    assert(sliders[index].point[5] == -46 - (index - 1) * 26, "Volume rows are not compact")
    assert(toggles[index].width == 58 and toggles[index].height == 22)
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

-- The native dropdown displays the current device and generates a flat radio list on open.
local dropdown = panel.deviceDropdown
assert(dropdown.parent == panel and dropdown.kind == "DropdownButton" and dropdown.width == 256)
assert(dropdown.text == "系统默认" and not dropdown.menuOpen)
dropdown:OpenMenu()
local devices = dropdown.description.entries
assert(#devices == 6 and dropdown.description.scrollHeight == 200)
assert(devices[1].isSelected(devices[1].data) and not devices[2].isSelected(devices[2].data))
before = #writes
devices[1].onSelect(devices[1].data)
assert(#writes == before and restarts == 0, "Current device restarted sound")
devices[3].onSelect(devices[3].data)
assert(values.Sound_OutputDriverIndex == "2" and restarts == 1 and dropdown.text == "耳机")
restartFailures = 1
devices[2].onSelect(devices[2].data)
assert(values.Sound_OutputDriverIndex == "2" and restarts == 3 and panel.status.text:find("已恢复"), "Restart failure did not restore original device")
failWrite = "Sound_OutputDriverIndex"
devices[2].onSelect(devices[2].data)
assert(values.Sound_OutputDriverIndex == "2" and panel.status.text:find("失败"))
failWrite = nil
restartFailures = 2
devices[2].onSelect(devices[2].data)
assert(panel.status.text:find("请检查"), "Rollback failure was reported as restored")
restartFailures = nil
before = #writes
deviceNames[2] = "新插入的设备"
devices[2].onSelect(devices[2].data)
assert(#writes == before and dropdown.description.entries[2].text == "新插入的设备", "Stale device index selected a different driver")
deviceNames[4] = "新显示器"
dropdown:CloseMenu()
dropdown:OpenMenu()
assert(dropdown.description.entries[4].text == "新显示器", "Opening the dropdown reused an old device list")
values.Sound_OutputDriverIndex = "3"
panel.scripts.OnEvent(panel, "CVAR_UPDATE", "Sound_OutputDriverIndex")
assert(dropdown.text == "新显示器", "External device selection did not update the dropdown")
Sound_GameSystem_RestartSoundSystem = nil
panel.scripts.OnEvent(panel, "SOUND_DEVICE_UPDATE")
assert(not dropdown.enabled, "Device switching without restart API stayed enabled")
failDevices = true
panel.scripts.OnEvent(panel, "SOUND_DEVICE_UPDATE")
assert(not dropdown.enabled and dropdown.text == "设备列表不可用" and #dropdown.description.entries == 0)
failDevices, deviceNames = nil, {}
panel.scripts.OnEvent(panel, "SOUND_DEVICE_UPDATE")
assert(not dropdown.enabled and dropdown.text == "未找到输出设备")

-- Hidden panels unsubscribe, reopening reflects external settings without writes.
minimap.scripts.OnClick(minimap)
assert(not panel.shown and not panel.events.CVAR_UPDATE and not panel.events.SOUND_DEVICE_UPDATE)
assert(not dropdown.menuOpen, "Hiding the panel left its dropdown open")
values.Sound_MusicVolume = "0.71"
before = #writes
SlashCmdList.WOWTOOLSSOUND()
assert(panel.shown and percentages[3].text == "71%" and #writes == before)
-- Reopening resets the anchor, choosing the inward corner in all four quadrants.
for _, placement in ipairs({
    { x = 100, y = 940, point = "TOPLEFT", relative = "BOTTOMRIGHT", dx = 4, dy = -4 },
    { x = 100, y = 100, point = "BOTTOMLEFT", relative = "TOPRIGHT", dx = 4, dy = 4 },
    { x = 1820, y = 100, point = "BOTTOMRIGHT", relative = "TOPLEFT", dx = -4, dy = 4 },
    { x = 1820, y = 940, point = "TOPRIGHT", relative = "BOTTOMLEFT", dx = -4, dy = -4 },
}) do
    panel:Hide()
    panel:SetPoint("CENTER")
    minimap.centerX, minimap.centerY = placement.x, placement.y
    SlashCmdList.WOWTOOLSSOUND()
    assert(panel.point[1] == placement.point and panel.point[2] == minimap and panel.point[3] == placement.relative
        and panel.point[4] == placement.dx and panel.point[5] == placement.dy, "Reopening did not place the panel beside the moved icon")
end
panel:Hide()
minimap.scale, minimap.centerX, minimap.centerY = 2, 600, 300
SlashCmdList.WOWTOOLSSOUND()
assert(panel.point[1] == "TOPRIGHT", "Anchor ignored the icon's effective scale")
panel:Hide()
UIParent.scale = 2
SlashCmdList.WOWTOOLSSOUND()
assert(panel.point[1] == "BOTTOMLEFT", "Anchor ignored the parent effective scale")
UIParent.scale, minimap.scale = 1, 1
minimap.centerX, minimap.centerY = 1820, 940
minimap.scripts.OnDragStart(minimap)
minimap.scripts.OnUpdate()
assert(wowDetectorDB.soundControl.minimapAngle == 0)
assert(panel.point[2] == minimap and panel.point[1] == "TOPRIGHT", "Visible panel did not follow the dragged icon")
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
local routed
WoWTools.settings={Open=function(group) routed=group end}
minimap=names.wowToolsSoundMinimapButton
panel=names.wowToolsSoundControlPanel
minimap.scripts.OnClick(minimap,"LeftButton")
assert(not panel:IsShown() and not routed, "Left click was redirected into unified settings")
minimap.scripts.OnClick(minimap,"LeftButton")
minimap.scripts.OnClick(minimap,"RightButton")
assert(panel:IsShown() and routed=="sound_control", "Right click did not open unified sound settings independently")
local host=widget("Frame")
host:SetSize(800,600)
local embedded=WoWTools.modules.sound_control.BuildSettings(host)
assert(embedded~=panel and panel.width==344 and panel.height==240)
assert(embedded.rows[1].slider.width==530, "Embedded audio sliders did not use the available width")
before=#writes
embedded.rows[3].slider:SetValue(64)
assert(#writes==before+1 and panel.rows[3].value.text=="64%" and embedded.rows[3].value.text=="64%",
    "Independent and embedded audio views did not share live channel values")
host:SetSize(500,480)
embedded.scripts.OnSizeChanged()
assert(embedded.rows[1].slider.width==230 and panel.width==344)
embedded:Hide()
assert(panel.events.CVAR_UPDATE and not embedded.events.CVAR_UPDATE, "Hiding one audio view disabled the other")
print("PASS: compact "..flavor.." sound control, adjacent four-corner/scaled anchors and reopen/drag placement, five independent sliders/numbers/switches, native device dropdown/open refresh/current selection, hotplug/restart/rollback failures, restricted data, events and reload.")
