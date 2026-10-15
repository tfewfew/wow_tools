-- Independent detector: observe selected targets; all targeting keys belong to the script/game.
local FLAVOR = "titan"
local enabled, initialized, elapsed = false, false, 0
local nameplates = {}
local lootOpen = false
local classID = nil
local range=WoWTools.FightRange
local encounterGUID, encounterSerial = nil, 0
local interactionGUID = nil
local state, combat, busy = "disabled", false, false
local health, settings = nil, nil
local events, SetActiveEvents
local recovery="none"
local recoveryDescriptions={none="无需恢复", recover="需要恢复", unknown="恢复状态未知"}
local defaultRecoveryThreshold=80
-- V9 adds a terminal death signal; health stays auxiliary.
-- The main cell also carries client/class, busy, combat and encounter metadata.
local actionCodes={unknown=0,idle=1,opening=2,combat=4,interact=5,dead=7}
local descriptions={disabled="已关闭",unknown="数据未知，暂停指令",idle="等待目标",
    opening="范围内有怪物，选中并开怪",combat="战斗中，持续攻击",
    interact="尸体可交互",dead="角色死亡，等待脚本移出编排"}

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, ...)
    if not ok or not Readable(value) then return nil, false end
    return value, true
end
local function Bool(fn, ...)
    local value, ok = Read(fn, ...)
    if not ok then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 or value == nil then return false end
    return nil
end
local function Say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccfffight_detector:|r " .. message)
end

local panel = CreateFrame("Frame", "wowToolsFightDetectorPanel", UIParent)
panel:SetSize(560, 230)
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
background:SetColorTexture(.04,.04,.04,1)
local title = panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
title:SetPoint("TOPLEFT",12,-10)
title:SetText("fight_detector · 时光服")
local status = panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
status:SetPoint("TOPLEFT",12,-30)
status:SetWidth(534)
status:SetHeight(32)
status:SetJustifyH("LEFT")
local rangeLabel = panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
rangeLabel:SetPoint("TOPLEFT",12,-78)
rangeLabel:SetText("检测 / 开怪距离（本职业，码）")
local input = CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
input:SetSize(64,22)
input:SetPoint("TOPLEFT",250,-74)
input:SetAutoFocus(false)
input:SetNumeric(true)
input:SetMaxLetters(2)
input:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
local save = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
save:SetSize(54,22)
save:SetPoint("LEFT",input,"RIGHT",6,0)
save:SetText("保存")
local rangeHint=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
rangeHint:SetPoint("TOPLEFT",12,-108)
rangeHint:SetText("开怪距离：5 / 10 / 15 / 20 / 25 / 30 / 35 / 40 码。")
local thresholdLabel=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
thresholdLabel:SetPoint("TOPLEFT",12,-138);thresholdLabel:SetText("恢复生命阈值（本职业，%）")
local thresholdInput=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
thresholdInput:SetSize(64,22);thresholdInput:SetPoint("TOPLEFT",250,-134)
thresholdInput:SetAutoFocus(false);thresholdInput:SetNumeric(true);thresholdInput:SetMaxLetters(3)
thresholdInput:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
local start = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
start:SetSize(64,22)
start:SetPoint("BOTTOMLEFT",12,8)
start:SetText("启动")
local close = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
close:SetSize(64,22)
close:SetPoint("BOTTOMRIGHT",-12,8)
close:SetText("关闭")
panel:Hide()

-- Exactly two opaque cells, fixed in physical client pixels despite UI/window scaling.
local signal=CreateFrame("Frame",nil,UIParent)
signal:SetAllPoints(UIParent)
signal:SetFrameStrata("TOOLTIP")
signal:EnableMouse(false)
local cells={signal:CreateTexture(nil,"OVERLAY"),signal:CreateTexture(nil,"OVERLAY")}
for _,cell in ipairs(cells) do
    if cell.SetSnapToPixelGrid then cell:SetSnapToPixelGrid(false) end
    if cell.SetTexelSnappingBias then cell:SetTexelSnappingBias(0) end
end
local function PositionSignal()
    local width,height,ok
    if type(GetPhysicalScreenSize)=="function" then ok,width,height=pcall(GetPhysicalScreenSize) end
    local logicalHeight=UIParent:GetHeight()
    if not ok or not Readable(height) or not Readable(width) or type(height)~="number"
        or type(width)~="number" or height<160 or width<160 or not Readable(logicalHeight)
        or type(logicalHeight)~="number" or logicalHeight<=0 then signal:Hide(); return false end
    local unit=logicalHeight/height
    for i,cell in ipairs(cells) do
        cell:ClearAllPoints()
        cell:SetPoint("CENTER",WoWTools.detectorAnchor,"CENTER",(i==1 and 0 or 32)*unit,0)
        local size=(i==1 and 32 or 12)*unit
        cell:SetSize(size,size)
    end
    if (enabled or state=="dead") and panel:IsShown() then signal:Show() else signal:Hide() end
    return true
end
local function Paint()
    if (enabled or state=="dead") and classID and PositionSignal() then
        local action=actionCodes[state] or 0
        local identity=(FLAVOR=="titan" and 0 or 13)+classID-1
        local encounter=encounterSerial%32
        local red=7+20*action
        local r,g,b=red/255,(4*(identity+(busy and 26 or 0)))/255,
            (4*(encounter+(combat and 32 or 0)))/255
        cells[1]:SetColorTexture(r,g,b,1)
        local hints={none={.15,.15,.15},recover={0,.4,1},unknown={.5,.5,.5}}
        local hint=hints[recovery] or hints.unknown
        cells[2]:SetColorTexture(hint[1],hint[2],hint[3],1)
    else signal:Hide() end
    status:SetText((descriptions[state] or descriptions.unknown).." · 战斗："..
        (combat==nil and "未知" or (combat and "是" or "否"))..
        "\n"..(recoveryDescriptions[recovery] or "恢复状态未知").." · HP "..(health and math.floor(health).."%" or "?")..
        " / 阈值 "..(settings and settings.RecoveryThreshold or defaultRecoveryThreshold).."%"..(busy and " · 忙碌" or ""))
    if enabled then start:Disable() else start:Enable() end
end

local function Enemy(unit)
    local exists=Bool(UnitExists,unit)
    if exists==false then return false end
    if exists==nil then return nil end
    local dead, player, attack=Bool(UnitIsDeadOrGhost,unit),Bool(UnitIsPlayer,unit),Bool(UnitCanAttack,"player",unit)
    if dead==nil or player==nil or attack==nil then return nil end
    return not dead and not player and attack
end
local function SetEncounter(guid)
    if encounterGUID~=guid then
        encounterGUID=guid; encounterSerial=(encounterSerial+1)%256
    end
end
local function FindEnemy()
    local candidates={"target","softenemy"}
    local plates={}
    for unit in pairs(nameplates) do plates[#plates+1]=unit end
    table.sort(plates)
    for _,unit in ipairs(plates) do candidates[#candidates+1]=unit end
    local unknown=false
    if encounterGUID then
        for _,unit in ipairs(candidates) do
            local guid,ok=Read(UnitGUID,unit)
            if ok and guid==encounterGUID and Enemy(unit)==true then return unit,guid end
        end
    elseif combat and Enemy("target")==true then
        -- Starting the detector mid-combat has no prior encounter to follow.
        local guid,ok=Read(UnitGUID,"target")
        if ok and type(guid)=="string" and guid~="" then return "target",guid end
    end
    for _,unit in ipairs(candidates) do
        local enemy=Enemy(unit)
        if enemy then
            local guid,ok=Read(UnitGUID,unit)
            if ok and type(guid)=="string" and guid~="" then
                -- Keep following the pulled monster, even if it retreats beyond detection range.
                -- Combat target changes must not replace the locked encounter.
                if guid==encounterGUID then return unit,guid end
                if not combat then
                    local detected=range.Check(unit,settings.DetectionRangeYards)
                    if detected then return unit,guid end
                    if detected==nil then unknown=true end
                end
            else unknown=true end
        elseif enemy==nil then unknown=true end
    end
    return nil,nil,unknown
end
local function Interaction()
    -- Looting and skinning share one hint; loot data and tooltip text cannot
    -- choose a separate color. Only a dead, interactable creature qualifies.
    local guid, ok=Read(UnitGUID,"softinteract")
    if not ok then return "unknown" end
    if guid==nil or guid=="" then return nil end
    if type(guid)~="string" then return "unknown" end
    if not guid:match("^Creature%-") then return nil end
    local dead=Bool(UnitIsDeadOrGhost,"softinteract")
    if dead==false then return nil end
    if dead==nil then return "unknown" end
    local ready=Bool(UnitIsInteractable,"softinteract")
    if ready==false then return nil end
    if ready==nil then return "unknown" end
    return "interact",guid
end
local function Percentage(currentFn, maximumFn, power)
    local current,ok,maximum,valid
    if power==nil then
        current,ok=Read(currentFn,"player")
        maximum,valid=Read(maximumFn,"player")
    else
        current,ok=Read(currentFn,"player",power)
        maximum,valid=Read(maximumFn,"player",power)
    end
    if not ok or not valid or type(current)~="number" or type(maximum)~="number"
        or maximum<=0 or current<0 or current>maximum then return nil end
    return current*100/maximum
end
local function Vitals()
    health=Percentage(UnitHealth,UnitHealthMax)
    return health~=nil
end
local function SetState(value)
    state=value
    Paint()
end
local function Stop(death)
    enabled,elapsed,state,combat,busy=false,0,death and "dead" or "disabled",false,false
    if SetActiveEvents then SetActiveEvents(false) end
    if death and events then
        events:RegisterEvent("DISPLAY_SIZE_CHANGED");events:RegisterEvent("UI_SCALE_CHANGED")
    end
    health,recovery=nil,"none"
    SetEncounter(nil)
    interactionGUID=nil
    signal:Hide()
    Paint()
end
local function Refresh()
    if not enabled then return end
    if Bool(UnitIsGhost,"player")==true then Stop();Say("灵魂状态，检测已停止，不移出角色。");return end
    local dead=Bool(UnitIsDead,"player")
    if dead==true then Stop(true); Say("角色死亡，检测已关闭；复活后请手动启动。"); return end
    combat=Bool(UnitAffectingCombat,"player")
    busy=false
    if combat==nil then recovery="unknown"; SetState("unknown"); return end
    local vitalsKnown=Vitals()
    local cast,castOK=Read(UnitCastingInfo,"player")
    local channel,channelOK=Read(UnitChannelInfo,"player")
    if not castOK or not channelOK then
        recovery,busy="unknown",true
        SetState(combat and "combat" or "unknown"); return
    end
    busy=not not (cast or channel or lootOpen or (LootFrame and LootFrame:IsShown()))
    recovery=not vitalsKnown and "unknown" or (health<settings.RecoveryThreshold and "recover" or "none")
    -- Combat alone drives the attack state; target and distance do not gate it.
    if combat then SetState("combat"); return end
    if dead==nil then SetState("unknown"); return end
    if busy and state=="interact" then
        SetState(state); return
    end
    -- An uncertain corpse cannot hide a known attackable enemy nearby.
    local interactionUnknown=false
    if not busy then
        local interaction,guid=Interaction()
        if interaction=="interact" then
            SetEncounter(nil)
            if guid and guid~=interactionGUID then
                interactionGUID=guid; encounterSerial=(encounterSerial+1)%256
            end
            SetState(interaction); return
        end
        interactionUnknown=interaction=="unknown"
    end
    local unit,guid,unknown=FindEnemy()
    if unit then
        SetEncounter(guid)
        local detected=range.Check(unit,settings.DetectionRangeYards)
        if detected==nil then SetState("unknown"); return end
        SetState(detected and "opening" or "idle"); return
    end
    if unknown or interactionUnknown then SetState("unknown"); return end
    SetEncounter(nil)
    SetState("idle")
end
local function SafeRefresh()
    if not enabled then return end
    local ok=pcall(Refresh)
    if not ok then
        busy,recovery=true,"unknown"
        if combat==true then state="combat" else state,combat="unknown",nil end
        Paint()
    end
end
local function ResetWorldState()
    lootOpen=false
    nameplates={}
    range.WarmCache()
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok,plates=pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates)=="table" then
            for _,plate in ipairs(plates) do
                local token=plate.namePlateUnitToken
                if Readable(token) and type(token)=="string" then nameplates[token]=true end
            end
        end
    end
end
local function Start()
    if not initialized then return end
    if Bool(UnitIsGhost,"player")==true then Stop();Say("灵魂状态无法启动检测，不移出角色。");return end
    local dead=Bool(UnitIsDead,"player")
    if dead~=false then
        local fish=WoWTools.modules.wowDetector
        if dead==true and not (fish and fish.IsEnabled()) then panel:Show(); Stop(true) end
        Say("死亡或存活状态未知，无法启动。"); return
    end
    enabled=true
    WoWTools.ActivateDetector("fight_detector")
    panel:Show()
    enabled,elapsed=true,0
    ResetWorldState()
    SetActiveEvents(true)
    SafeRefresh()
end
save:SetScript("OnClick",function()
    if not initialized then return end
    local value=tonumber(input:GetText())
    if not range.IsSupported(value) then
        Say("距离请选择 5、10、15、20、25、30、35 或 40 码。"); return
    end
    local threshold=tonumber(thresholdInput:GetText())
    if not threshold or threshold<1 or threshold>100 or threshold~=math.floor(threshold) then
        Say("恢复生命阈值须为 1–100 的整数。"); return
    end
    local draft={DetectionRangeYards=value,RecoveryThreshold=threshold}
    settings=draft
    fightDetectorDB.profiles[classID]=draft
    input:ClearFocus(); thresholdInput:ClearFocus()
    SafeRefresh()
end)
start:SetScript("OnClick",Start)
close:SetScript("OnClick",function() Stop(); panel:Hide() end)
panel:SetScript("OnHide",function() Stop() end)
signal:Hide()
WoWTools.modules.fight_detector={
    IsEnabled=function() return enabled end,
    IsShown=function() return panel:IsShown() end,
    Show=Start,
    Hide=function() Stop(); panel:Hide() end,
    Toggle=function() if panel:IsShown() then Stop(); panel:Hide() else Start() end end,
}
events=CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
local activeEvents={"PLAYER_ENTERING_WORLD","PLAYER_DEAD","PLAYER_LOGOUT",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","PLAYER_SOFT_ENEMY_CHANGED",
    "PLAYER_SOFT_INTERACT_CHANGED","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED",
    "LOOT_OPENED","LOOT_CLOSED","LOOT_READY","LOOT_SLOT_CLEARED",
    "UNIT_HEALTH","UNIT_MAXHEALTH","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED","GET_ITEM_INFO_RECEIVED"}
events:SetScript("OnEvent",function(_,event,arg)
    if event=="ADDON_LOADED" then
        if arg~="wow_tools" then return end
        if type(fightDetectorDB)~="table" then fightDetectorDB={} end
        if type(fightDetectorDB.rangeSpells)~="table" then fightDetectorDB.rangeSpells={} end
        if type(fightDetectorDB.profiles)~="table" then fightDetectorDB.profiles={} end
        local ok,_,_,id=pcall(UnitClass,"player")
        if not ok or not Readable(id) or type(id)~="number" or id<1 or id>13 then return end
        classID=id
        local stored=fightDetectorDB.profiles[id]
        settings={DetectionRangeYards=range.DefaultDetection,RecoveryThreshold=defaultRecoveryThreshold}
        if type(stored)=="table" then
            if range.IsSupported(stored.DetectionRangeYards) then settings.DetectionRangeYards=stored.DetectionRangeYards end
            local threshold=stored.RecoveryThreshold or stored.HealthEnter
            if type(threshold)=="number" and threshold>=1 and threshold<=100
                and threshold==math.floor(threshold) then settings.RecoveryThreshold=threshold end
        end
        input:SetText(tostring(settings.DetectionRangeYards))
        thresholdInput:SetText(tostring(settings.RecoveryThreshold))
        initialized=true
        Stop()
    elseif not enabled then
        if state=="dead" and (event=="DISPLAY_SIZE_CHANGED" or event=="UI_SCALE_CHANGED") then Paint() end
        return
    elseif event=="LOOT_OPENED" then
        lootOpen=true
        SafeRefresh()
    elseif event=="LOOT_CLOSED" then
        lootOpen=false
        SafeRefresh()
    elseif event=="NAME_PLATE_UNIT_ADDED" then
        if Readable(arg) and type(arg)=="string" then nameplates[arg]=true end
    elseif event=="NAME_PLATE_UNIT_REMOVED" then
        if Readable(arg) and type(arg)=="string" then nameplates[arg]=nil end
    elseif event=="PLAYER_ENTERING_WORLD" then
        ResetWorldState()
        SafeRefresh()
    elseif event=="PLAYER_DEAD" or event=="PLAYER_LOGOUT" then lootOpen=false; Stop(event=="PLAYER_DEAD" and Bool(UnitIsGhost,"player")~=true)
    else SafeRefresh() end
end)
local function Poll(_,delta)
    if not enabled then return end
    elapsed=elapsed+delta
    if elapsed>=.1 then elapsed=0; SafeRefresh() end
end
SetActiveEvents=function(active)
    for _,event in ipairs(activeEvents) do
        if active then pcall(events.RegisterEvent,events,event)
        else pcall(events.UnregisterEvent,events,event) end
    end
    events:SetScript("OnUpdate",active and Poll or nil)
    if WoWTools.UpdateLootActivation then WoWTools.UpdateLootActivation() end
end
SLASH_FIGHTDETECTOR1="/fightdetector"
SlashCmdList.FIGHTDETECTOR=function(message)
    local command=(message or ""):lower():match("^%s*(.-)%s*$")
    if command=="off" or command=="hide" then Stop(); panel:Hide()
    elseif command=="status" then Say((descriptions[state] or state).." · 检测="..(settings and settings.DetectionRangeYards or "?").."码 / encounter="..encounterSerial.." · class="..tostring(classID))
    else Start() end
end
