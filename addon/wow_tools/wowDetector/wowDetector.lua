local enabled = false
local elapsed = 0
local initialized = false
local state = "disabled"
local freeSlots = nil
local panel = CreateFrame("Frame", "wowDetectorPanel", UIParent)
panel:SetSize(240, 40)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetPoint("LEFT", UIParent, "CENTER", -20, 0)
panel:Hide()

local background = panel:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0.04, 0.04, 0.04, 1)
local indicator = panel:CreateTexture(nil, "ARTWORK")
indicator:SetSize(24, 24)
indicator:SetPoint("TOPLEFT", 8, -8)
local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("LEFT", panel, "LEFT", 42, 0)
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
    else
        indicator:SetColorTexture(0.5, 0.5, 0.5, 1)
        label:SetText(enabled and "背包状态未知" or "已关闭")
    end
    toggle:SetText(enabled and "关闭" or "启动")
end

local function ResetAfterDeath()
    if not initialized then return end
    local wasEnabled = enabled
    enabled = false
    elapsed = 0
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
    if not name then
        name, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
    end
    if not name then return false end
    local fishingName = FishingName()
    return spellID == 7620 or (fishingName ~= nil and name == fishingName)
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

local function Refresh()
    if enabled and UnitIsDeadOrGhost("player") then
        ResetAfterDeath()
        return
    end
    if not enabled then
        if state ~= "disabled" then Paint("disabled") end
        return
    end
    freeSlots = GetFreeSlots()
    local nextState
    if freeSlots == nil then nextState = "unknown"
    elseif freeSlots == 0 then nextState = "full"
    else nextState = IsFishing() and "fishing" or "idle" end
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
    panel:SetPoint("LEFT", UIParent, "CENTER", -20, 0)
    if initialized then SavePosition() end
    Say("色块已移至画面正中心。")
end

local function SetEnabled(value)
    if not initialized then return end
    if value then
        if UnitIsDeadOrGhost("player") then
            ResetAfterDeath()
            Say("角色死亡或处于灵魂状态，无法启动检测。")
            return
        end
        CenterIndicator()
        wowDetectorDB.locked = true
    else
        panel:StopMovingOrSizing()
        wowDetectorDB.locked = false
    end
    enabled = value
    Refresh()
    toggle:SetText(enabled and "关闭" or "启动")
    Say(enabled and "已启动并锁定位置：绿色=钓鱼，红色=未钓鱼，黄色=普通背包已满。" or "已关闭并解锁，可以拖动面板。")
end

panel:SetScript("OnDragStart", function(self)
    if initialized and not enabled and not wowDetectorDB.locked then self:StartMoving() end
end)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if initialized then SavePosition() end
end)
toggle:SetScript("OnClick", function() SetEnabled(not enabled) end)

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

-- Keep state updates active even while the control panel is hidden.
local updates = CreateFrame("Frame")
updates:SetScript("OnUpdate", function(_, delta)
    if not enabled then return end
    elapsed = elapsed + delta
    if elapsed >= 0.1 then
        elapsed = 0
        Refresh()
    end
end)

panel:RegisterEvent("ADDON_LOADED")
panel:RegisterEvent("PLAYER_ENTERING_WORLD")
panel:RegisterEvent("PLAYER_DEAD")
panel:RegisterEvent("PLAYER_ALIVE")
panel:RegisterEvent("PLAYER_UNGHOST")
panel:RegisterEvent("BAG_UPDATE_DELAYED")
panel:RegisterEvent("UNIT_SPELLCAST_START")
panel:RegisterEvent("UNIT_SPELLCAST_STOP")
panel:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
panel:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
panel:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
panel:RegisterEvent("UNIT_SPELLCAST_FAILED")
panel:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit ~= "wow_tools" then return end
        if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
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
    elseif event == "PLAYER_DEAD" then
        ResetAfterDeath()
    elseif event == "PLAYER_ENTERING_WORLD" and UnitIsDeadOrGhost("player") then
        ResetAfterDeath()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST"
        or event == "BAG_UPDATE_DELAYED" or unit == "player" then
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
        Refresh()
        local name, _, _, _, _, _, _, id = UnitChannelInfo("player")
        Say("状态=" .. state .. "；普通背包空格=" .. tostring(freeSlots) .. "；引导=" .. tostring(name) .. "；技能ID=" .. tostring(id))
    else
        Say("命令：/wowdetector on | off | toggle | show | hide | unlock | lock | center | reset | status")
    end
end

Paint("disabled")

WoWTools.modules.wowDetector = {
    Toggle = function() SetPanelVisible(not panel:IsShown()) end,
    Show = function() SetPanelVisible(true) end,
    IsShown = function() return panel:IsShown() end,
}
