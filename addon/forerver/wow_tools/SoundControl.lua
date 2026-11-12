-- Forever's five independent sound channels and output drivers, in one panel.
local channels = {
    { label = "主音量", volume = "Sound_MasterVolume", enabled = "Sound_EnableAllSound" },
    { label = "音效", volume = "Sound_SFXVolume", enabled = "Sound_EnableSFX" },
    { label = "音乐", volume = "Sound_MusicVolume", enabled = "Sound_EnableMusic" },
    { label = "环境音", volume = "Sound_AmbienceVolume", enabled = "Sound_EnableAmbience" },
    { label = "对话", volume = "Sound_DialogVolume", enabled = "Sound_EnableDialog" },
}
local panel, button, initialized, refreshing, changingDevice
local rows = {}
local Refresh, RefreshDevices

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    if not Readable(value) then return nil end
    if type(value) ~= "string" and type(value) ~= "number" then return nil end
    local number = tonumber(value)
    if number and number == number and number ~= math.huge and number ~= -math.huge then return number end
end

local function Read(key)
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    if not getter then return nil end
    local ok, value = pcall(getter, key)
    if ok then return Number(value) end
end

local function Write(key, value)
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if not setter then return false end
    local ok, result = pcall(setter, key, tostring(value))
    if not ok or not Readable(result) or result == false then return false end
    local actual = Read(key)
    return actual ~= nil and math.abs(actual - value) < 0.000001
end

local function Status(message)
    panel.status:SetText(message or "")
end

local function OutputDevices()
    if type(Sound_GameSystem_GetNumOutputDrivers) ~= "function"
        or type(Sound_GameSystem_GetOutputDriverNameByIndex) ~= "function" then return nil end
    local ok, count = pcall(Sound_GameSystem_GetNumOutputDrivers)
    count = ok and Number(count) or nil
    if not count or count < 0 or count > 256 or count ~= math.floor(count) then return nil end
    local devices = {}
    for index = 0, count - 1 do
        local read, name = pcall(Sound_GameSystem_GetOutputDriverNameByIndex, index)
        if read and Readable(name) and type(name) == "string" and name ~= "" then
            devices[#devices + 1] = { index = index, name = name }
        end
    end
    return devices
end

local function RestartSound()
    if type(Sound_GameSystem_RestartSoundSystem) ~= "function" then return false end
    local ok, result = pcall(Sound_GameSystem_RestartSoundSystem)
    return ok and Readable(result) and result ~= false
end

local function SelectDevice(index, expectedName)
    if changingDevice then return end
    -- Re-enumerate before writing because hotplug can reuse a driver's index.
    local found = false
    for _, device in ipairs(OutputDevices() or {}) do
        if device.index == index and device.name == expectedName then found = true; break end
    end
    local previous = Read("Sound_OutputDriverIndex")
    if not found or previous == nil then
        Status("设备列表已变化，请重新选择。")
        RefreshDevices()
        return
    end
    if previous == index then Status(); return end
    if type(Sound_GameSystem_RestartSoundSystem) ~= "function" then
        Status("客户端的声音设备切换接口不可用。")
        return
    end
    changingDevice = true
    local switched = Write("Sound_OutputDriverIndex", index) and RestartSound()
        and Read("Sound_OutputDriverIndex") == index
    local restored = true
    if not switched then
        restored = Write("Sound_OutputDriverIndex", previous) and RestartSound()
            and Read("Sound_OutputDriverIndex") == previous
    end
    changingDevice = false
    Refresh()
    RefreshDevices()
    if switched then Status("声音输出设备已切换。")
    elseif restored then Status("切换失败，已恢复原输出设备。")
    else Status("切换失败，请检查游戏声音设置中的输出设备。") end
end

Refresh = function()
    if not panel then return end
    refreshing = true
    local masterEnabled = Read("Sound_EnableAllSound")
    for index, channel in ipairs(channels) do
        local row = rows[index]
        local volume, enabled = Read(channel.volume), Read(channel.enabled)
        local available = volume ~= nil and volume >= 0 and volume <= 1
        row.slider:SetEnabled(available)
        row.slider:SetValue(available and math.floor(volume * 100 + 0.5) or 0)
        row.value:SetText(available and (math.floor(volume * 100 + 0.5) .. "%") or "—")
        row.toggle:SetEnabled(enabled == 0 or enabled == 1)
        row.toggle:SetText(enabled == 1 and "禁用" or enabled == 0 and "启用" or "不可用")
        row.label:SetTextColor(1, 1, 1, enabled == 1 and masterEnabled == 1 and 1 or 0.5)
    end
    refreshing = false
end

RefreshDevices = function()
    if not panel or changingDevice then return end
    panel.deviceDropdown:GenerateMenu()
end

local function PositionPanel()
    local x, y = button:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    local buttonScale, parentScale = button:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local right = x * buttonScale >= centerX * parentScale
    local above = y * buttonScale >= centerY * parentScale
    local point = (above and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT")
    local relativePoint = (above and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT")
    panel:ClearAllPoints()
    panel:SetPoint(point, button, relativePoint, right and -4 or 4, above and -4 or 4)
end

local function CreatePanel(parent)
    panel = CreateFrame("Frame", "wowToolsSoundControlPanel", parent or UIParent,
        not parent and "BasicFrameTemplateWithInset" or nil)
    panel:SetSize(344, 240)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    if parent then
        panel:SetMovable(false)
        panel:SetClampedToScreen(false)
        panel:SetScript("OnDragStart", nil)
        panel:SetScript("OnDragStop", nil)
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 12, -12)
        title:SetText("音量与输出设备")
    else
        panel.TitleText:SetText("声音控制")
        UISpecialFrames[#UISpecialFrames + 1] = "wowToolsSoundControlPanel"
    end
    panel:Hide()

    for index, channel in ipairs(channels) do
        local y = -46 - (index - 1) * 26
        local row = {}
        row.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", panel, "TOPLEFT", 12, y)
        row.label:SetText(channel.label)
        row.slider = CreateFrame("Slider", nil, panel)
        row.slider:SetSize(150, 16)
        row.slider:SetPoint("LEFT", panel, "TOPLEFT", 68, y)
        row.slider:SetOrientation("HORIZONTAL")
        row.slider:SetMinMaxValues(0, 100)
        row.slider:SetValueStep(1)
        row.slider:SetObeyStepOnDrag(true)
        local track = row.slider:CreateTexture(nil, "BACKGROUND")
        track:SetHeight(6)
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetColorTexture(0.25, 0.28, 0.32, 1)
        row.slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        row.slider:GetThumbTexture():SetSize(20, 20)
        row.value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("LEFT", row.slider, "RIGHT", 6, 0)
        row.value:SetWidth(40)
        row.value:SetJustifyH("RIGHT")
        row.toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        row.toggle:SetSize(58, 22)
        row.toggle:SetPoint("LEFT", panel, "TOPLEFT", 274, y)
        row.slider:SetScript("OnValueChanged", function(_, value)
            if refreshing then return end
            value = Number(value)
            if not value then return end
            local percent = math.max(0, math.min(100, math.floor(value + 0.5)))
            local current = Read(channel.volume)
            if current == nil or current < 0 or current > 1 then Refresh(); return end
            local ok = math.abs(current - percent / 100) < 0.000001 or Write(channel.volume, percent / 100)
            Refresh()
            Status(ok and "" or "音量设置失败，请重试。")
        end)
        row.slider:EnableMouseWheel(true)
        row.slider:SetScript("OnMouseWheel", function(self, delta)
            if self:IsEnabled() then self:SetValue(self:GetValue() + delta) end
        end)
        row.toggle:SetScript("OnClick", function()
            local enabled = Read(channel.enabled)
            if enabled ~= 0 and enabled ~= 1 then Refresh(); return end
            local ok = Write(channel.enabled, 1 - enabled)
            Refresh()
            Status(ok and "" or "声音开关设置失败，请重试。")
        end)
        rows[index] = row
    end

    local deviceTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deviceTitle:SetPoint("LEFT", panel, "TOPLEFT", 12, -192)
    deviceTitle:SetText("输出设备")
    panel.deviceDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    panel.deviceDropdown:SetSize(256, 25)
    panel.deviceDropdown:SetPoint("TOPLEFT", 76, -180)
    panel.deviceDropdown:SetupMenu(function(dropdown, root)
        -- The native dropdown also calls this on every open, refreshing hotplugged devices.
        local devices = OutputDevices()
        local current = Read("Sound_OutputDriverIndex")
        local available = devices ~= nil and #devices > 0
        dropdown:SetEnabled(available and current ~= nil and type(Sound_GameSystem_RestartSoundSystem) == "function")
        dropdown:SetDefaultText(not devices and "设备列表不可用" or not available and "未找到输出设备" or "请选择输出设备")
        root:SetScrollMode(200)
        for _, device in ipairs(devices or {}) do
            root:CreateRadio(device.name,
                function(data) return Read("Sound_OutputDriverIndex") == data.index end,
                function(data) SelectDevice(data.index, data.name) end, device)
        end
    end)
    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("BOTTOMLEFT", 12, 10)
    panel.status:SetWidth(320)
    panel.status:SetJustifyH("LEFT")
    panel:SetScript("OnShow", function(self)
        if not parent then PositionPanel() end
        Status()
        Refresh()
        RefreshDevices()
        self:RegisterEvent("CVAR_UPDATE")
        self:RegisterEvent("SOUND_DEVICE_UPDATE")
    end)
    panel:SetScript("OnHide", function(self)
        self:UnregisterEvent("CVAR_UPDATE")
        self:UnregisterEvent("SOUND_DEVICE_UPDATE")
        self.deviceDropdown:CloseMenu()
        GameTooltip:Hide()
    end)
    panel:SetScript("OnEvent", function(_, event, key)
        if refreshing or changingDevice then return end
        if event == "SOUND_DEVICE_UPDATE" then RefreshDevices()
        elseif type(key) == "string" and Readable(key) then
            local name = key:lower()
            if name == "sound_outputdriverindex" then RefreshDevices()
            elseif name:match("^sound_") then Refresh() end
        end
    end)
end

local function Toggle()
    if WoWTools.settings then WoWTools.settings.Toggle("sound_control"); return end
    if not initialized then return end
    if not panel then CreatePanel() end
    panel:SetShown(not panel:IsShown())
end

button = CreateFrame("Button", "wowToolsSoundMinimapButton", Minimap)
button:SetSize(32, 32)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER")
icon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function PositionButton()
    local angle = math.rad(wowDetectorDB.soundControl.minimapAngle)
    local x, y = math.cos(angle), math.sin(angle)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        local edge = math.max(math.abs(x), math.abs(y))
        x, y = x / edge, y / edge
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        x * (Minimap:GetWidth() / 2 + 6), y * (Minimap:GetHeight() / 2 + 6))
    if panel and panel:IsShown() and not WoWTools.settings then PositionPanel() end
end

button:SetScript("OnClick", Toggle)
button:SetScript("OnDragStart", function(self)
    if not initialized then return end
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local cx, cy = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        wowDetectorDB.soundControl.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
        PositionButton()
    end)
end)
button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
button:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("声音控制")
    GameTooltip:AddLine("点击：打开 / 关闭声音设置", 1, 1, 1)
    GameTooltip:AddLine("拖动：调整小地图入口位置", 1, 1, 1)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= "wow_tools" then return end
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.soundControl) ~= "table" then wowDetectorDB.soundControl = {} end
    local angle = Number(wowDetectorDB.soundControl.minimapAngle)
    wowDetectorDB.soundControl.minimapAngle = angle and angle % 360 or 315
    initialized = true
    PositionButton()
    self:UnregisterEvent("ADDON_LOADED")
end)

WoWTools.modules.sound_control = {
    Toggle = Toggle,
    IsShown = function()
        if WoWTools.settings then return WoWTools.settings.IsGroupShown("sound_control") end
        return panel and panel:IsShown() or false
    end,
    BuildSettings = function(parent)
        if not panel then CreatePanel(parent) end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", 8, -8)
        panel:Show()
        return panel
    end,
}
SLASH_WOWTOOLSSOUND1 = "/wowsound"
SlashCmdList.WOWTOOLSSOUND = Toggle
