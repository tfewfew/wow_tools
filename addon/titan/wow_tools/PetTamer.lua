-- Pet taming only observes the current target. Keyboard actions belong to wowAuto.
local FLAVOR = "titan"
local enabled, initialized, elapsed = false, false, 0
local embedded = false
local names, targetGUID, serial = {}, nil, 0
local events = CreateFrame("Frame")
local activeEvents = {"PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "UNIT_NAME_UPDATE",
    "UNIT_HEALTH", "UNIT_FACTION", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED"}
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil, false end
    return value, true
end
local function Bool(fn, ...)
    local value, ok = Read(fn, ...)
    if not ok then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 or value == nil then return false end
end
local panel = CreateFrame("Frame", "wowToolsPetTamerPanel", UIParent)
panel:SetSize(460, 330)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -16)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
local background = panel:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(.04, .04, .04, 1)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -12)
title:SetText("自动抓宠 · 当前目标名称名单")
local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", 12, -38)
hint:SetText("每行一个完整名称，保存后持久化。先选中目标，再由脚本执行。")
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 16, -64)
scroll:SetSize(404, 182)
local input = CreateFrame("EditBox", "wowToolsPetTamerNames", scroll)
input:SetMultiLine(true)
input:SetFontObject("ChatFontNormal")
input:SetSize(400, 182)
input:SetAutoFocus(false)
input:SetMaxLetters(4000)
local function UpdateInputHeight()
    local _, fontHeight = input:GetFont()
    local lines = math.max(1, input:GetNumLines())
    local textHeight = lines * fontHeight + (lines - 1) * input:GetSpacing()
    input:SetHeight(math.max(182, embedded and scroll:GetHeight() or 182, textHeight + 20))
end
input:SetScript("OnTextChanged", UpdateInputHeight)
input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
scroll:SetScrollChild(input)
local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT", 12, -258)
status:SetText("检测已关闭")
local function Button(text, x)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetPoint("BOTTOMLEFT", x, 12)
    button:SetSize(100, 24)
    button:SetText(text)
    return button
end
local save, start, close = Button("保存名单", 12), Button("启动检测", 126), Button("关闭检测", 340)
panel:Hide()
local signal = CreateFrame("Frame", "wowToolsPetTamerSignal", UIParent)
signal:SetAllPoints(UIParent)
signal:SetFrameStrata("TOOLTIP")
signal:EnableMouse(false)
local main, auxiliary = signal:CreateTexture(nil, "OVERLAY"), signal:CreateTexture(nil, "OVERLAY")
for _, cell in ipairs({main, auxiliary}) do
    if cell.SetSnapToPixelGrid then cell:SetSnapToPixelGrid(false) end
    if cell.SetTexelSnappingBias then cell:SetTexelSnappingBias(0) end
end
signal:Hide()
local function Paint(state, combat)
    local _, height = GetPhysicalScreenSize()
    local ratio = UIParent:GetHeight() / height
    main:ClearAllPoints()
    main:SetPoint("CENTER", WoWTools.detectorAnchor, "CENTER", 0, 0)
    main:SetSize(32 * ratio, 32 * ratio)
    auxiliary:ClearAllPoints()
    auxiliary:SetPoint("CENTER", WoWTools.detectorAnchor, "CENTER", 32 * ratio, 0)
    auxiliary:SetSize(12 * ratio, 12 * ratio)
    -- Taming v1. Main red and auxiliary green identify this separate protocol.
    main:SetColorTexture(211/255, (11+24*(state+(combat and 4 or 0)))/255, (serial%64)*4/255, 1)
    auxiliary:SetColorTexture((3+4*math.floor(serial/64))/255, 223/255, (FLAVOR=="titan" and 71 or 79)/255, 1)
    signal:Show()
    status:SetText(({[0]="等待匹配目标", "目标名称匹配", "数据未知，暂停", "角色死亡或灵魂状态"})[state])
end
local function Refresh()
    if not enabled then return end
    local guid, readable = Read(UnitGUID, "target")
    if not readable or (guid ~= nil and type(guid) ~= "string") then Paint(2, false); return end
    if guid ~= targetGUID then targetGUID = guid; serial = (serial+1)%4096 end
    local combat = Bool(UnitAffectingCombat, "player")
    local dead, ghost = Bool(UnitIsDead, "player"), Bool(UnitIsGhost, "player")
    if dead == true or ghost == true then Paint(3, false); return end
    if dead == nil or ghost == nil or combat == nil then Paint(2, false); return end
    local exists = Bool(UnitExists, "target")
    if exists == false then Paint(0, combat); return end
    if exists == nil then Paint(2, combat); return end
    local name, known = Read(UnitName, "target")
    local targetDead, attackable = Bool(UnitIsDead, "target"), Bool(UnitCanAttack, "player", "target")
    if not known or type(name) ~= "string" or targetDead == nil or attackable == nil then Paint(2, combat); return end
    Paint((names[name] and not targetDead and attackable) and 1 or 0, combat)
end
local function SafeRefresh()
    if enabled and not pcall(Refresh) then Paint(2, false) end
end
local function Stop()
    enabled = false
    for _, event in ipairs(activeEvents) do pcall(events.UnregisterEvent, events, event) end
    events:SetScript("OnUpdate", nil)
    signal:Hide()
    status:SetText("检测已关闭")
end
local function Start()
    if not initialized then return end
    WoWTools.ActivateDetector("pet_tamer")
    enabled, elapsed = true, 0
    panel:Show()
    for _, event in ipairs(activeEvents) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= .1 then elapsed = 0; SafeRefresh() end
    end)
    SafeRefresh()
end
local function LoadNames(stored)
    names = {}
    local list = {}
    for _, name in ipairs(stored) do
        if type(name) == "string" then
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" and not names[name] then names[name] = true; list[#list+1] = name end
        end
    end
    return list
end
save:SetScript("OnClick", function()
    if not initialized then return end
    local list = {}
    for name in (input:GetText().."\n"):gmatch("([^\r\n]+)") do list[#list+1] = name end
    list = LoadNames(list)
    wowDetectorDB.petTamer = {names=list}
    serial = (serial+1)%4096
    input:SetText(table.concat(list, "\n"))
    input:ClearFocus()
    SafeRefresh()
    DEFAULT_CHAT_FRAME:AddMessage("wow_tools：已保存抓宠名单，共 "..#list.." 个名称。")
end)
start:SetScript("OnClick", Start)
local function Close()
    Stop()
    if not embedded then panel:Hide() end
end
close:SetScript("OnClick", Close)
panel:SetScript("OnHide", function() if not embedded then Stop() end end)
WoWTools.modules.pet_tamer = {
    IsEnabled=function() return enabled end,
    IsShown=function() return embedded and panel:IsVisible() or (not embedded and panel:IsShown()) end,
    Show=Start,
    Hide=Close,
    Toggle=function() if enabled or (not embedded and panel:IsShown()) then Close() else Start() end end,
    BuildSettings=function(parent)
        embedded = true
        panel:SetParent(parent)
        panel:ClearAllPoints()
        panel:SetAllPoints(parent)
        panel:SetFrameStrata("DIALOG")
        panel:SetFrameLevel(parent:GetFrameLevel() + 1)
        panel:SetMovable(false)
        panel:SetClampedToScreen(false)
        panel:SetScript("OnDragStart", nil)
        panel:SetScript("OnDragStop", nil)
        background:Hide()
        close:SetText("停止检测")
        hint:SetJustifyH("LEFT")
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 16, -72)
        scroll:SetPoint("BOTTOMRIGHT", -40, 104)
        status:ClearAllPoints()
        status:SetPoint("BOTTOMLEFT", 16, 56)
        status:SetJustifyH("LEFT")
        save:ClearAllPoints()
        save:SetPoint("BOTTOMLEFT", 16, 16)
        start:ClearAllPoints()
        start:SetPoint("BOTTOMLEFT", 154, 16)
        close:ClearAllPoints()
        close:SetPoint("BOTTOMRIGHT", -16, 16)
        for _, button in ipairs({save, start, close}) do button:SetWidth(122) end
        local function Layout()
            local width = math.max(420, panel:GetWidth())
            hint:SetWidth(width - 32)
            status:SetWidth(width - 32)
            input:SetWidth(math.max(320, scroll:GetWidth() - 4))
            UpdateInputHeight()
        end
        panel:SetScript("OnSizeChanged", Layout)
        Layout()
        parent:SetScript("OnShow", function() panel:Show() end)
        panel:Show()
        return panel
    end,
}
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= "wow_tools" then return end
        if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
        local saved = wowDetectorDB.petTamer
        local list = LoadNames(type(saved)=="table" and type(saved.names)=="table" and saved.names or {})
        input:SetText(table.concat(list, "\n"))
        initialized = true
        Stop()
    else SafeRefresh() end
end)
SLASH_PETTAMER1 = "/pettamer"
SlashCmdList.PETTAMER = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "off" or command == "hide" then Close() else Start() end
end
