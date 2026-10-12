-- Independent detector with a secure, key-triggered target/focus button. No movement or casting.
local FLAVOR = "titan"
local enabled, initialized, elapsed = false, false, 0
local nameplates = {}
local lootOpen = false
local classID = nil
local range=WoWTools.FightRange
local attackRange=range.DefaultAttack
local encounterGUID, encounterSerial = nil, 0
local pullObserved=false
local state, combat, skin, busy = "disabled", false, false, false
local health, mana, settings = nil, nil, nil
local recovery="none"
local recoveryDescriptions={none="无需恢复", recover="非战斗恢复", emergency="战斗紧急恢复", unknown="恢复未知"}
local recovering, emergency = false, false
local settingDefaults = { HealthEnter=80, HealthExit=95, ManaEnter=0, ManaExit=90,
    EmergencyEnter=30, EmergencyExit=50 }
-- V5: main cell contains action, recovery, client/class, busy, combat and encounter.
-- Auxiliary cell is a visual recovery hint only; there is no heartbeat.
local actionCodes={unknown=0,idle=1,opening=2,waiting=3,combat=4,loot=5,skin=6,target=7}
local recoveryCodes={none=0,recover=1,emergency=2,unknown=3}
local descriptions={disabled="已关闭",unknown="数据未知，暂停指令",idle="等待目标",
    target="选中并锁定本次怪物（F10）",opening="已选中怪物，开怪",waiting="等待怪物接近",combat="进入攻击距离",
    loot="可以拾取",skin="可以剥皮"}

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
-- F10 is a temporary override while detection runs. Only a key click executes it.
-- Attributes and bindings are never changed under combat lockdown.
local targetButton=CreateFrame("Button","wowToolsFightTargetButton",UIParent,"SecureActionButtonTemplate")
targetButton:RegisterForClicks("AnyDown","AnyUp")
targetButton:SetAttribute("type","macro")
targetButton:SetAttribute("macrotext","")
local targetPreparedGUID, targetPreparedUnit, targetBound=nil,nil,false
local function PrepareTarget(unit,guid)
    if InCombatLockdown() then return targetBound and targetPreparedGUID==guid end
    if not enabled then
        ClearOverrideBindings(targetButton)
        targetButton:SetAttribute("macrotext","")
        targetPreparedGUID,targetPreparedUnit,targetBound=nil,nil,false
        return false
    end
    if not unit or not guid then return false end
    if targetPreparedGUID~=guid or targetPreparedUnit~=unit then
        targetButton:SetAttribute("macrotext","/target [combat,@focus,exists,harm,nodead][nocombat,@"..unit..",exists,harm,nodead]\n/focus [nocombat,@target,exists,harm,nodead]")
        targetPreparedGUID,targetPreparedUnit=guid,unit
    end
    if not targetBound then
        SetOverrideBindingClick(targetButton,true,"F10","wowToolsFightTargetButton","LeftButton")
        targetBound=true
    end
    return true
end

local function Say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccfffight_detector:|r " .. message)
end

local panel = CreateFrame("Frame", "wowToolsFightDetectorPanel", UIParent)
panel:SetSize(560, 312)
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
local attackLabel=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
attackLabel:SetPoint("TOPLEFT",12,-108)
attackLabel:SetText("开始战斗距离（全局，码）")
local attackInput=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
attackInput:SetSize(64,22); attackInput:SetPoint("TOPLEFT",250,-104)
attackInput:SetAutoFocus(false); attackInput:SetNumeric(true); attackInput:SetMaxLetters(2)
attackInput:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
local rangeHint=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
rangeHint:SetPoint("TOPLEFT",12,-138)
rangeHint:SetText("可选距离：5 / 10 / 15 / 20 / 25 / 30 / 35 / 40 码。")
local thresholds = {}
local thresholdRows = {
    {"非战斗生命值 %", "HealthEnter", "HealthExit"},
    {"非战斗法力值 %", "ManaEnter", "ManaExit"},
    {"战斗紧急生命值 %", "EmergencyEnter", "EmergencyExit"},
}
for i,row in ipairs(thresholdRows) do
    local y=-166-(i-1)*30
    local label=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    label:SetPoint("TOPLEFT",12,y); label:SetText(row[1])
    for j=2,3 do
        local box=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
        box:SetSize(44,22); box:SetPoint("TOPLEFT",180+(j-2)*126,y+4)
        box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(3)
        box:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        thresholds[row[j]]=box
        local caption=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        caption:SetPoint("LEFT",box,"RIGHT",5,0); caption:SetText(j==2 and "进入" or "退出")
    end
end
local hint=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
hint:SetPoint("TOPLEFT",12,-266)
hint:SetText("进入 0 关闭恢复；检测期间 F10 选目标，焦点保留当前怪物。")
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
    if enabled and panel:IsShown() then signal:Show() else signal:Hide() end
    return true
end
local function Paint()
    if enabled and classID and PositionSignal() then
        local action=actionCodes[state] or 0
        local identity=(FLAVOR=="titan" and 0 or 13)+classID-1
        local encounter=encounterSerial%32
        local recover=recoveryCodes[recovery] or 3
        local red=state=="target" and ({[0]=240,[1]=248,[2]=8,[3]=40})[recover] or (16+8*(action*4+recover))
        cells[1]:SetColorTexture(red/255,
            (2+4*(identity+(busy and 26 or 0)))/255,
            (2+4*(encounter+(combat and 32 or 0)))/255,1)
        local hints={none={.15,.15,.15},recover={0,.4,1},emergency={1,.15,0},unknown={.5,.5,.5}}
        local hint=hints[recovery] or hints.unknown
        cells[2]:SetColorTexture(hint[1],hint[2],hint[3],1)
    else signal:Hide() end
    status:SetText((descriptions[state] or descriptions.unknown).." · 战斗："..
        (combat==nil and "未知" or (combat and "是" or "否"))..
        "\n"..(recoveryDescriptions[recovery] or "恢复未知").." · HP "..(health and math.floor(health).."%" or "?")..
        (mana and (" / MP "..math.floor(mana).."%") or "")..(busy and " · 忙碌" or ""))
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
        encounterGUID=guid; encounterSerial=(encounterSerial+1)%256; pullObserved=false
    end
end
local function FindEnemy()
    local candidates={"focus","target","softenemy"}
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
    end
    for _,unit in ipairs(candidates) do
        local enemy=Enemy(unit)
        if enemy then
            local guid,ok=Read(UnitGUID,unit)
            if ok and type(guid)=="string" and guid~="" then
                -- Keep following the pulled monster, even if it retreats beyond detection range.
                -- Combat target changes must not replace the locked encounter.
                if guid==encounterGUID then return unit,guid end
                if not combat and unit~="focus" then
                    local detected=range.Check(unit,settings.DetectionRangeYards)
                    if detected then return unit,guid end
                    if detected==nil then unknown=true end
                end
            else unknown=true end
        elseif enemy==nil then unknown=true end
    end
    return nil,nil,unknown
end
local scanTooltip
local function SkinTooltip(unit)
    local data, ok
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        data,ok=Read(C_TooltipInfo.GetUnit,unit)
        if not ok or type(data)~="table" or not Readable(data.lines) or type(data.lines)~="table" then return nil end
        for _,line in ipairs(data.lines) do
            if not Readable(line) or type(line)~="table" then return nil end
            local text=line.leftText
            if not Readable(text) then return nil end
            if type(text)=="string" and ((type(UNIT_SKINNABLE)=="string" and text==UNIT_SKINNABLE)
                or (type(SKINNABLE)=="string" and text==SKINNABLE)) then
                local c=line.leftColor
                if not Readable(c) or not c then return nil end
                -- Read both components under pcall; secret colors cannot imply readiness.
                local colorOK,red,green=pcall(function() return c:GetRGB() end)
                if not colorOK or not Readable(red) or not Readable(green) then return nil end
                return not (red>.8 and green<.2)
            end
        end
        return false
    end
    -- Legacy client fallback uses its own invisible tooltip, never GameTooltip.
    if not scanTooltip then scanTooltip=CreateFrame("GameTooltip","wowToolsFightScanTooltip",UIParent,"GameTooltipTemplate") end
    scanTooltip:SetOwner(UIParent,"ANCHOR_NONE")
    scanTooltip:ClearLines()
    local tooltipOK=pcall(scanTooltip.SetUnit,scanTooltip,unit)
    if not tooltipOK then scanTooltip:Hide(); return nil end
    local result=false
    for i=1,scanTooltip:NumLines() do
        local font=_G["wowToolsFightScanTooltipTextLeft"..i]
        local text=font and font:GetText()
        if not Readable(text) then result=nil; break end
        if text and ((UNIT_SKINNABLE and text==UNIT_SKINNABLE) or (SKINNABLE and text==SKINNABLE)) then
            local r,g=font:GetTextColor()
            if not Readable(r) or not Readable(g) then result=nil else result=not (r>.8 and g<.2) end
            break
        end
    end
    scanTooltip:Hide()
    return result
end
local function LootStatus(guid)
    -- CanLootUnit returns both loot presence and this player's permission to loot.
    -- Missing, restricted or partial results cannot authorize an interaction.
    if type(CanLootUnit)~="function" then return nil end
    local ok,hasLoot,canLoot=pcall(CanLootUnit,guid)
    if not ok or not Readable(hasLoot) or not Readable(canLoot) then return nil end
    if hasLoot~=true and hasLoot~=false and hasLoot~=1 and hasLoot~=0 then return nil end
    if canLoot~=true and canLoot~=false and canLoot~=1 and canLoot~=0 then return nil end
    return hasLoot==true or hasLoot==1, canLoot==true or canLoot==1
end
local function Interaction()
    -- Only the soft interaction unit can be acted on by the configured interaction key.
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
    local hasLoot,canLoot=LootStatus(guid)
    if hasLoot==nil then return "unknown" end
    if hasLoot then
        if canLoot then return "loot" end
        return nil -- Do not skin a corpse that still has inaccessible loot.
    end
    local canSkin=SkinTooltip("softinteract")
    if canSkin==nil then return "unknown" end
    if canSkin then return "skin" end
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
    mana=nil
    if health==nil then return false end
    if settings.ManaEnter==0 then return true end
    local powerType,ok=Read(UnitPowerType,"player")
    if not ok or type(powerType)~="number" then return false end
    if powerType==0 then
        mana=Percentage(UnitPower,UnitPowerMax,0)
        if mana==nil then return false end
    end
    return true
end
local function SetState(value)
    state=value
    Paint()
end
local function Stop()
    enabled,elapsed,state,combat,skin,busy=false,0,"disabled",false,false,false
    recovering,emergency=false,false
    health,mana,recovery=nil,nil,"none"
    SetEncounter(nil)
    PrepareTarget(nil,nil)
    signal:Hide()
    Paint()
end
local function Refresh()
    if not enabled then return end
    local dead=Bool(UnitIsDeadOrGhost,"player")
    if dead==true then Stop(); Say("角色死亡，检测已关闭；复活后请手动启动。"); return end
    combat=Bool(UnitAffectingCombat,"player")
    skin,busy=false,false
    if dead==nil or combat==nil or not Vitals() then recovery="unknown"; SetState("unknown"); return end
    local cast,castOK=Read(UnitCastingInfo,"player")
    local channel,channelOK=Read(UnitChannelInfo,"player")
    if not castOK or not channelOK then recovery="unknown"; SetState("unknown"); return end
    busy=not not (cast or channel or lootOpen or (LootFrame and LootFrame:IsShown()))
    if combat then
        recovering=false
        emergency=settings.EmergencyEnter>0 and (health<=settings.EmergencyEnter
            or (emergency and health<settings.EmergencyExit))
        recovery=emergency and "emergency" or "none"
    else
        emergency=false
        if recovering then
            recovering=(settings.HealthEnter>0 and health<settings.HealthExit)
                or (settings.ManaEnter>0 and mana~=nil and mana<settings.ManaExit)
        else
            recovering=(settings.HealthEnter>0 and health<=settings.HealthEnter)
                or (settings.ManaEnter>0 and mana~=nil and mana<=settings.ManaEnter)
        end
        recovery=recovering and "recover" or "none"
    end
    if busy and not combat and (state=="skin" or state=="loot") then
        skin=state=="skin"; SetState(state); return
    end
    if not combat and not recovering and not busy then
        local interaction=Interaction()
        if interaction then SetEncounter(nil); skin=interaction=="skin"; SetState(interaction); return end
    end
    local unit,guid,unknown=FindEnemy()
    if unit then
        SetEncounter(guid)
        local targetGUID,targetOK=Read(UnitGUID,"target")
        local focusGUID,focusOK=Read(UnitGUID,"focus")
        if not targetOK or not focusOK then SetState("unknown"); return end
        if not PrepareTarget(unit,guid) or (combat and focusGUID~=guid) then SetState("unknown"); return end
        if targetGUID~=guid or (not combat and focusGUID~=guid) then SetState("target"); return end
        if combat or pullObserved then
            local closeEnough=range.Check(unit,attackRange)
            if closeEnough==nil then SetState("unknown"); return end
            SetState(closeEnough and "combat" or "waiting"); return
        end
        local detected=range.Check(unit,settings.DetectionRangeYards)
        if detected==nil then SetState("unknown"); return end
        SetState(detected and "opening" or "waiting"); return
    end
    if combat or unknown then SetState("unknown"); return end
    SetEncounter(nil)
    SetState("idle")
end
local function SafeRefresh()
    if not enabled and not InCombatLockdown() then PrepareTarget(nil,nil) end
    local ok=pcall(Refresh)
    if not ok then state,combat,skin,busy,recovery="unknown",nil,nil,false,"unknown"; Paint() end
end
local function Start()
    if not initialized then return end
    if Bool(UnitIsDeadOrGhost,"player")~=false then Say("死亡或存活状态未知，无法启动。"); return end
    WoWTools.ActivateDetector("fight_detector")
    panel:Show()
    enabled,elapsed=true,0
    SafeRefresh()
end
save:SetScript("OnClick",function()
    if not initialized then return end
    local value=tonumber(input:GetText())
    local attack=tonumber(attackInput:GetText())
    if not range.IsSupported(value) or not range.IsSupported(attack) then
        Say("距离请选择 5、10、15、20、25、30、35 或 40 码。"); return
    end
    local draft={DetectionRangeYards=value}
    for _,row in ipairs(thresholdRows) do
        for j=2,3 do
            local number=tonumber(thresholds[row[j]]:GetText())
            if not number or number<0 or number>100 or number~=math.floor(number) then Say("恢复阈值须为 0–100 的整数。"); return end
            draft[row[j]]=number
        end
        if draft[row[2]]>=draft[row[3]] then Say("恢复进入值必须小于退出值。"); return end
    end
    attackRange,settings=attack,draft
    fightDetectorDB.AttackRangeYards=attack
    fightDetectorDB.profiles[classID]=draft
    recovering,emergency=false,false
    input:ClearFocus(); attackInput:ClearFocus()
    for _,box in pairs(thresholds) do box:ClearFocus() end
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
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_DEAD","PLAYER_LOGOUT",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED","PLAYER_SOFT_ENEMY_CHANGED",
    "PLAYER_SOFT_INTERACT_CHANGED","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED",
    "LOOT_OPENED","LOOT_CLOSED","LOOT_READY","LOOT_SLOT_CLEARED",
    "UNIT_HEALTH","UNIT_MAXHEALTH","UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER","UNIT_DISPLAYPOWER","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED","GET_ITEM_INFO_RECEIVED","UNIT_SPELLCAST_SUCCEEDED"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event,arg,castGUID,spellID)
    if event=="ADDON_LOADED" then
        if arg~="wow_tools" then return end
        if type(fightDetectorDB)~="table" then fightDetectorDB={} end
        if type(fightDetectorDB.rangeSpells)~="table" then fightDetectorDB.rangeSpells={} end
        if type(fightDetectorDB.profiles)~="table" then fightDetectorDB.profiles={} end
        local ok,_,_,id=pcall(UnitClass,"player")
        if not ok or not Readable(id) or type(id)~="number" or id<1 or id>13 then return end
        classID=id
        attackRange=range.IsSupported(fightDetectorDB.AttackRangeYards) and fightDetectorDB.AttackRangeYards or range.DefaultAttack
        range.WarmCache()
        local stored=fightDetectorDB.profiles[id]
        settings={DetectionRangeYards=range.DefaultDetection}
        for key,value in pairs(settingDefaults) do settings[key]=value end
        if type(stored)=="table" then
            if range.IsSupported(stored.DetectionRangeYards) then settings.DetectionRangeYards=stored.DetectionRangeYards end
            for _,row in ipairs(thresholdRows) do
                local enter,exit=stored[row[2]],stored[row[3]]
                if type(enter)=="number" and type(exit)=="number" and enter>=0 and exit<=100
                    and enter<exit and enter==math.floor(enter) and exit==math.floor(exit) then
                    settings[row[2]],settings[row[3]]=enter,exit
                end
            end
        end
        input:SetText(tostring(settings.DetectionRangeYards)); attackInput:SetText(tostring(attackRange))
        for field,box in pairs(thresholds) do box:SetText(tostring(settings[field])) end
        initialized=true
        Stop()
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
        if enabled and Readable(arg) and arg=="player" and Readable(spellID) and type(spellID)=="number"
            and Bool(C_Spell and C_Spell.IsSpellHarmful or IsHarmfulSpell,spellID)==true then
            for _,unit in ipairs({"target","softenemy"}) do
                local guid,ok=Read(UnitGUID,unit)
                if ok and type(guid)=="string" and guid==encounterGUID and Enemy(unit)==true then
                    pullObserved=true; break
                end
            end
        end
        SafeRefresh()
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
        SafeRefresh()
    elseif event=="PLAYER_DEAD" or event=="PLAYER_LOGOUT" then lootOpen=false; Stop()
    else SafeRefresh() end
end)
events:SetScript("OnUpdate",function(_,delta)
    if not enabled then return end
    elapsed=elapsed+delta
    if elapsed>=.1 then elapsed=0; SafeRefresh() end
end)
SLASH_FIGHTDETECTOR1="/fightdetector"
SlashCmdList.FIGHTDETECTOR=function(message)
    local command=(message or ""):lower():match("^%s*(.-)%s*$")
    if command=="off" or command=="hide" then Stop(); panel:Hide()
    elseif command=="status" then Say((descriptions[state] or state).." · 检测="..(settings and settings.DetectionRangeYards or "?").."码 / 攻击="..attackRange.."码 / encounter="..encounterSerial.." · class="..tostring(classID))
    else Start() end
end
