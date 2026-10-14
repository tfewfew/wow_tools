local enabled = false
local elapsed = 0
local initialized = false
local state = "disabled"
local freeSlots = nil
local updates, SetActiveEvents
local panel = CreateFrame("Frame", "wowDetectorPanel", UIParent)
panel:SetSize(280, 40)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetPoint("LEFT", WoWTools.detectorAnchor, "CENTER", -20, 0)
panel:Hide()

local background = panel:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0.04, 0.04, 0.04, 1)
local indicator = panel:CreateTexture(nil, "ARTWORK")
indicator:SetSize(24, 24)
indicator:SetPoint("TOPLEFT", 8, -8)
local lureIndicator = panel:CreateTexture(nil, "ARTWORK")
lureIndicator:SetColorTexture(0.5, 0.5, 0.5, 1)
lureIndicator:SetPoint("CENTER", indicator, "CENTER", 32, 0)
lureIndicator:SetSize(12, 12)
local function PositionLureIndicator()
    -- wowAuto reads exactly 32 physical screen pixels to the right of the main point.
    -- Like Blizzard's PixelUtil, include the viewport's 768-unit reference height.
    local _, physicalHeight
    if GetPhysicalScreenSize then _, physicalHeight = GetPhysicalScreenSize() end
    local scale = panel:GetEffectiveScale()
    if type(physicalHeight) ~= "number" or physicalHeight <= 0
        or type(scale) ~= "number" or scale <= 0 then
        lureIndicator:Hide()
        return false
    end
    local unitsPerPixel = 768 / physicalHeight / scale
    lureIndicator:ClearAllPoints()
    lureIndicator:SetPoint("CENTER", indicator, "CENTER", 32 * unitsPerPixel, 0)
    lureIndicator:SetSize(12 * unitsPerPixel, 12 * unitsPerPixel)
    lureIndicator:Show()
    return true
end
local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("LEFT", lureIndicator, "RIGHT", 10, 0)
local toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
toggle:SetSize(62, 24)
toggle:SetPoint("RIGHT", -8, 0)

local function Say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffwowDetector:|r " .. message)
end

local function Paint(newState)
    state = newState
    if state == "full" then
        indicator:SetColorTexture(1, 1, 0, 1)
        label:SetText("背包已满")
    elseif state == "fishing" then
        indicator:SetColorTexture(0, 1, 0, 1)
        label:SetText("钓鱼中 · 1")
    elseif state == "idle" then
        indicator:SetColorTexture(1, 0, 0, 1)
        label:SetText("未钓鱼 · 0")
    elseif state == "waiting" then
        indicator:SetColorTexture(1, 0, 0, 1)
        label:SetText("等待交互 · 0")
    else
        indicator:SetColorTexture(0.5, 0.5, 0.5, 1)
        label:SetText(not enabled and "已关闭" or (state == "interaction_unknown" and "交互状态未知" or "背包状态未知"))
        if not enabled then lureIndicator:SetColorTexture(0.5, 0.5, 0.5, 1) end
    end
    toggle:SetText(enabled and "关闭" or "启动")
end

local function ResetAfterDeath()
    if not initialized then return end
    local wasEnabled = enabled
    WoWTools.audio.Restore()
    enabled = false
    elapsed = 0
    if SetActiveEvents then SetActiveEvents(false) end
    freeSlots = nil
    panel:StopMovingOrSizing()
    wowDetectorDB.locked = false
    Paint("disabled")
    if wasEnabled then Say("角色已死亡，检测已关闭并解除锁定；复活后请手动启动。") end
end

local function FishingName()
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(7620)
    elseif GetSpellInfo then
        return GetSpellInfo(7620)
    end
end

local function IsFishing()
    local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
    -- The cast itself is not enough: wait until the fishing channel has begun.
    if not name then return false end
    local fishingName = FishingName()
    return spellID == 7620 or (fishingName ~= nil and name == fishingName)
end

local function GetInteractState()
    if type(UnitGUID) ~= "function" or type(UnitIsInteractable) ~= "function" then return "unknown" end
    -- GameObjects such as bobbers need not pass UnitExists; read the soft target's GUID.
    local ok, guid = pcall(UnitGUID, "softinteract")
    if not ok or (issecretvalue and issecretvalue(guid)) then return "unknown" end
    if guid == nil or guid == "" then return "missing" end
    if type(guid) ~= "string" then return "unknown" end
    local readable, interactable = pcall(UnitIsInteractable, "softinteract")
    if not readable or (issecretvalue and issecretvalue(interactable))
        or type(interactable) ~= "boolean" then return "unknown", guid end
    return interactable and "present" or "missing", guid
end

local function GetFreeSlots()
    local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local getFree = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not getSlots or not getFree then return nil end
    -- Count carried general-purpose bags only, not bank/reagent/specialty bags.
    local backpackSlots = getSlots(0)
    if not backpackSlots or backpackSlots <= 0 then return nil end
    local total = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = getSlots(bag)
        if slots == nil then return nil end
        if slots > 0 then
            local free, family = getFree(bag)
            if free == nil or family == nil then return nil end
            if family == 0 then total = total + free end
        end
    end
    return total
end

local function GetLureState()
    if UnitIsDeadOrGhost("player") then return "unknown" end
    local link = GetInventoryItemLink("player", 16)
    local getInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not link or not getInfo or not GetWeaponEnchantInfo then return "unknown" end
    local _, _, _, _, _, classID, subclassID = getInfo(link)
    -- Only a fishing pole's temporary enchant counts; permanent fishing-line enchants do not.
    if classID == nil or subclassID == nil or classID ~= 2 or subclassID ~= 20 then return "unknown" end
    local hasEnchant, expiration = GetWeaponEnchantInfo()
    if not hasEnchant then return "missing" end
    if type(expiration) ~= "number" then return "unknown" end
    return expiration > 0 and "present" or "missing"
end

local function PaintLure()
    local positioned = PositionLureIndicator()
    local lure = enabled and positioned and GetLureState() or "unknown"
    if lure == "present" then lureIndicator:SetColorTexture(0, 0, 1, 1)
    elseif lure == "missing" then lureIndicator:SetColorTexture(1, 0, 1, 1)
    else lureIndicator:SetColorTexture(0.5, 0.5, 0.5, 1) end
end

local function Refresh()
    if enabled and UnitIsDeadOrGhost("player") then
        ResetAfterDeath()
        return
    end
    if not enabled then
        return
    end
    PaintLure()
    freeSlots = GetFreeSlots()
    local nextState
    if freeSlots == nil then nextState = "unknown"
    elseif freeSlots == 0 then nextState = "full"
    elseif not IsFishing() then nextState = "idle"
    else
        local interaction = GetInteractState()
        if interaction == "present" then nextState = "fishing"
        elseif interaction == "missing" then nextState = "waiting"
        else nextState = "interaction_unknown" end
    end
    if nextState ~= state then Paint(nextState) end
end

local function SavePosition()
    local point, _, relativePoint, x, y = panel:GetPoint()
    wowDetectorDB.position = { point, relativePoint, x, y }
end

local function CenterIndicator()
    panel:StopMovingOrSizing()
    panel:ClearAllPoints()
    -- The indicator center is 20 UI units from the panel's left edge.
    panel:SetPoint("LEFT", WoWTools.detectorAnchor, "CENTER", -20, 0)
    if initialized then SavePosition() end
    Say("色块已移至画面正中心。")
end

local function SetEnabled(value)
    if not initialized then return end
    local wasEnabled = enabled
    if value then
        if UnitIsDeadOrGhost("player") then
            ResetAfterDeath()
            Say("角色死亡或处于灵魂状态，无法启动检测。")
            return
        end
        enabled = true
        WoWTools.ActivateDetector("wowDetector")
        if not wasEnabled then
            local ok, reason = WoWTools.audio.Start()
            if not ok then Say(reason) end
        end
        CenterIndicator()
        wowDetectorDB.locked = true
    else
        if not WoWTools.audio.Restore() then Say("部分音频设置未恢复，将在关闭或重载时重试。") end
        panel:StopMovingOrSizing()
        wowDetectorDB.locked = false
    end
    if value ~= wasEnabled then elapsed = 0 end
    enabled = value
    SetActiveEvents(value)
    if value then Refresh() else Paint("disabled") end
    toggle:SetText(enabled and "关闭" or "启动")
    Say(enabled and "已启动并锁定位置：绿色=钓鱼引导且有可交互目标，红色=未钓鱼或等待交互，黄色=普通背包已满。请启用游戏交互键。" or "已关闭并解锁，可以拖动面板。")
end

panel:SetScript("OnDragStart", function(self)
    if initialized and not enabled and not wowDetectorDB.locked then self:StartMoving() end
end)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if initialized then SavePosition() end
end)

local function SetPanelVisible(visible)
    if not initialized then return end
    panel:StopMovingOrSizing()
    SavePosition()
    wowDetectorDB.panelHidden = not visible
    if visible then
        Refresh()
        panel:Show()
    else
        panel:Hide()
    end
end

local function OpenMonitor()
    SetPanelVisible(true)
    SetEnabled(true)
end

local function CloseMonitor()
    SetEnabled(false)
    SetPanelVisible(false)
end

toggle:SetScript("OnClick", function()
    if enabled then CloseMonitor() else OpenMonitor() end
end)

-- Keep state updates active even while the control panel is hidden.
updates = CreateFrame("Frame")
local function Poll(_, delta)
    if not enabled then return end
    elapsed = elapsed + delta
    if elapsed >= 0.1 then
        elapsed = 0
        Refresh()
    end
end

panel:RegisterEvent("ADDON_LOADED")
panel:RegisterEvent("PLAYER_LOGOUT")
local activeEvents = {"PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED"}
SetActiveEvents = function(active)
    for _, event in ipairs(activeEvents) do
        if active then panel:RegisterEvent(event) else panel:UnregisterEvent(event) end
    end
    updates:SetScript("OnUpdate", active and Poll or nil)
    if WoWTools.UpdateLootActivation then WoWTools.UpdateLootActivation() end
end
panel:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit ~= "wow_tools" then return end
        if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
        WoWTools.audio.Restore()
        wowDetectorDB.locked = false
        local pos = wowDetectorDB.position
        if type(pos) == "table" and type(pos[1]) == "string"
            and type(pos[2]) == "string" and type(pos[3]) == "number"
            and type(pos[4]) == "number" then
            panel:ClearAllPoints()
            panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end
        initialized = true
        enabled = false
        Paint("disabled")
        wowDetectorDB.panelHidden = true
        panel:Hide()
        Say("已加载，默认隐藏且检测关闭。小地图入口打开界面，或输入 /wowdetector on。")
    elseif not enabled and event ~= "PLAYER_LOGOUT" then
        return
    elseif event == "PLAYER_LOGOUT" then
        WoWTools.audio.Restore()
        enabled = false
        elapsed = 0
        freeSlots = nil
        wowDetectorDB.locked = false
        SetActiveEvents(false)
        Paint("disabled")
    elseif event == "PLAYER_DEAD" then
        ResetAfterDeath()
    elseif event == "PLAYER_ENTERING_WORLD" and UnitIsDeadOrGhost("player") then
        ResetAfterDeath()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST"
        or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED"
        or event == "PLAYER_SOFT_INTERACT_CHANGED" or unit == "player" then
        Refresh()
    end
end)

SLASH_WOWDETECTOR1 = "/wowdetector"
SLASH_WOWDETECTOR2 = "/fishstate"
SlashCmdList.WOWDETECTOR = function(message)
    local command = (message or ""):match("^%s*(%S*)"):lower()
    if command == "on" then
        SetPanelVisible(true)
        SetEnabled(true)
    elseif command == "show" then
        SetPanelVisible(true)
    elseif command == "hide" then
        SetPanelVisible(false)
    elseif command == "off" then
        SetEnabled(false)
    elseif command == "toggle" or command == "" then
        SetEnabled(not enabled)
    elseif command == "unlock" then
        if enabled then
            Say("检测运行中保持锁定，请先点击“关闭”或输入 /wowdetector off。")
            return
        end
        wowDetectorDB.locked = false
        Say("已解锁，可以拖动面板。定位后输入 /wowdetector lock。")
    elseif command == "lock" then
        panel:StopMovingOrSizing()
        SavePosition()
        wowDetectorDB.locked = true
        Say("已锁定位置。")
    elseif command == "reset" or command == "center" then
        CenterIndicator()
    elseif command == "status" then
        if not enabled then Say("监测=关闭；钓鱼状态读取未启动。") return end
        Refresh()
        local name, _, _, _, _, _, _, id = UnitChannelInfo("player")
        Say("状态=" .. state .. "；普通背包空格=" .. tostring(freeSlots) .. "；鱼饵附魔=" .. GetLureState() .. "；引导=" .. tostring(name) .. "；技能ID=" .. tostring(id))
        local interaction, guid = GetInteractState()
        local targetName, interactCVar
        if UnitName then
            local ok, value = pcall(UnitName, "softinteract")
            if ok and not (issecretvalue and issecretvalue(value)) then targetName = value end
        end
        local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
        if getCVar then
            local ok, value = pcall(getCVar, "softTargetInteract")
            if ok then interactCVar = value end
        end
        Say("交互目标=" .. interaction .. "；名称=" .. tostring(targetName) .. "；GUID=" .. tostring(guid)
            .. "；softTargetInteract=" .. tostring(interactCVar))
        local width, height
        if GetPhysicalScreenSize then width, height = GetPhysicalScreenSize() end
        Say("监测=" .. (enabled and "开启" or "关闭") .. "；面板=" .. (panel:IsShown() and "显示" or "隐藏")
            .. "；画面像素=" .. tostring(width) .. "x" .. tostring(height)
            .. "；UI缩放=" .. tostring(panel:GetEffectiveScale())
            .. "；鱼饵点=" .. (PositionLureIndicator() and "中心右侧32px，12x12px" or "无法获取画面尺寸"))
    else
        Say("命令：/wowdetector on | off | toggle | show | hide | unlock | lock | center | reset | status")
    end
end

Paint("disabled")

WoWTools.modules.wowDetector = {
    IsEnabled = function() return enabled end,
    Toggle = function()
        if panel:IsShown() then CloseMonitor() else OpenMonitor() end
    end,
    Show = OpenMonitor,
    Hide = CloseMonitor,
    IsShown = function() return panel:IsShown() end,
    GetLureState = GetLureState,
}
