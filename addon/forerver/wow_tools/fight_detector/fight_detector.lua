-- Independent, read-only detector. No targeting, casting, movement or input APIs.
local FLAVOR = "forerver"
local enabled, initialized, elapsed = false, false, 0
local nameplates = {}
local classID, rangeSpell = nil, nil
local state, combat, skin = "disabled", false, false
local defaults = { [1]=78, [2]=20271, [3]=75, [4]=1752, [5]=585, [6]=45462,
    [7]=403, [8]=133, [9]=686, [10]=100780, [11]=5176, [12]=162243, [13]=361469 }
local colors = { disabled={128,128,128}, unknown={128,128,128}, idle={0,0,255},
    fight={255,0,0}, busy={255,255,0}, skin={255,0,255}, loot={0,255,0} }
local descriptions = { disabled="已关闭", unknown="数据未知，暂停指令", idle="等待范围内目标",
    fight="范围内有怪", busy="施法 / 交互中", skin="可以剥皮", loot="可以拾取" }

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
panel:SetSize(370, 108)
panel:SetPoint("TOP", UIParent, "TOP", 0, -160)
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
title:SetText("fight_detector · 永恒服 / 无限服")
local status = panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
status:SetPoint("TOPLEFT",12,-32)
local rangeLabel = panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
rangeLabel:SetPoint("TOPLEFT",12,-56)
rangeLabel:SetText("测距法术 ID")
local input = CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
input:SetSize(90,22)
input:SetPoint("TOPLEFT",100,-52)
input:SetAutoFocus(false)
input:SetNumeric(true)
input:SetMaxLetters(9)
input:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
local save = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
save:SetSize(54,22)
save:SetPoint("LEFT",input,"RIGHT",6,0)
save:SetText("保存")
local start = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
start:SetSize(64,22)
start:SetPoint("BOTTOMLEFT",12,8)
start:SetText("启动")
local close = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
close:SetSize(64,22)
close:SetPoint("BOTTOMRIGHT",-12,8)
close:SetText("关闭")
panel:Hide()

-- Eight 10px cells, 16px apart, at y=-64 relative to the client center.
-- Independent from wowDetector's center and +32px lure points.
local signal = CreateFrame("Frame",nil,UIParent)
signal:SetAllPoints(UIParent)
signal:SetFrameStrata("TOOLTIP")
signal:EnableMouse(false)
local cells = {}
for i=1,8 do cells[i]=signal:CreateTexture(nil,"OVERLAY") end
local function PaintCell(index,r,g,b)
    cells[index]:SetColorTexture(r/255,g/255,b/255,1)
end
local function PositionSignal()
    local height, ok
    local width
    if type(GetPhysicalScreenSize)=="function" then
        ok, width, height = pcall(GetPhysicalScreenSize)
    end
    local scale = signal:GetEffectiveScale()
    if not ok or not Readable(height) or type(height)~="number" or height<=0
        or not Readable(scale) or type(scale)~="number" or scale<=0 then
        signal:Hide()
        return false
    end
    local unit = 768/height/scale
    for i=1,8 do
        cells[i]:ClearAllPoints()
        cells[i]:SetPoint("CENTER",UIParent,"CENTER",(-56+(i-1)*16)*unit,64*unit)
        cells[i]:SetSize(10*unit,10*unit)
    end
    if enabled and panel:IsShown() then signal:Show() else signal:Hide() end
    return true
end
local function Paint()
    for i=1,8 do PaintCell(i,128,128,128) end
    if enabled and classID and PositionSignal() then
        PaintCell(1,0,255,255) -- protocol v1 header
        PaintCell(2,unpack(colors[state] or colors.unknown))
        if combat~=nil then PaintCell(3,combat and 255 or 0,combat and 0 or 255,0) end
        if skin~=nil then PaintCell(4,skin and 255 or 0,0,255) end
        PaintCell(5,classID*16,255-classID*16,85)
        if FLAVOR=="titan" then PaintCell(6,255,128,0) else PaintCell(6,128,0,255) end
        local beat=math.floor(GetTime()*10)%256
        PaintCell(7,beat,255-beat,170)
        PaintCell(8,255,255,255) -- protocol trailer
    else
        signal:Hide()
    end
    status:SetText((descriptions[state] or descriptions.unknown).." · 战斗："..
        (combat==nil and "未知" or (combat and "是" or "否")))
    if enabled then start:Disable() else start:Enable() end
end

local function InRange(unit)
    if C_Spell and C_Spell.IsSpellInRange then
        local value,ok=Read(C_Spell.IsSpellInRange,rangeSpell,unit)
        if ok and (value==true or value==1) then return true end
        if ok and (value==false or value==0) then return false end
        return nil
    end
    local name, ok=Read(GetSpellInfo,rangeSpell)
    if not ok or type(name)~="string" then return nil end
    local value,valid=Read(IsSpellInRange,name,unit)
    if valid and (value==true or value==1) then return true end
    if valid and (value==false or value==0) then return false end
    return nil
end
local function Enemy(unit)
    local exists=Bool(UnitExists,unit)
    if exists==false then return false end
    if exists==nil then return nil end
    local dead, player, attack=Bool(UnitIsDeadOrGhost,unit),Bool(UnitIsPlayer,unit),Bool(UnitCanAttack,"player",unit)
    if dead==nil or player==nil or attack==nil then return nil end
    return not dead and not player and attack
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
    local hasLoot,lootOK=Read(CanLootUnit,guid)
    if lootOK and (hasLoot==true or hasLoot==1) then return "loot" end
    local canSkin=SkinTooltip("softinteract")
    if canSkin==nil then return "unknown" end
    if canSkin then return "skin" end
end
local function Stop()
    enabled,elapsed,state,combat,skin=false,0,"disabled",false,false
    signal:Hide()
    Paint()
end
local function Refresh()
    if not enabled then return end
    local dead=Bool(UnitIsDeadOrGhost,"player")
    if dead==true then Stop(); Say("角色死亡，检测已关闭；复活后请手动启动。"); return end
    combat=Bool(UnitAffectingCombat,"player")
    skin=false
    if dead==nil or combat==nil then state="unknown"; Paint(); return end
    local cast,castOK=Read(UnitCastingInfo,"player")
    local channel,channelOK=Read(UnitChannelInfo,"player")
    if not castOK or not channelOK then state="unknown"; Paint(); return end
    if cast or channel or (LootFrame and LootFrame:IsShown()) then state="busy"; Paint(); return end
    if not combat then
        local interaction=Interaction()
        if interaction then state=interaction; skin=interaction=="skin"; Paint(); return end
    end
    local targetEnemy=Enemy("target")
    local candidates={"target"}
    if targetEnemy==false then candidates[#candidates+1]="softenemy" end
    -- Do not replace a live hostile target with some unrelated visible nameplate.
    if targetEnemy==false then for unit in pairs(nameplates) do candidates[#candidates+1]=unit end end
    local unknown=false
    for _,unit in ipairs(candidates) do
        local enemy=Enemy(unit)
        if enemy then
            local inRange=InRange(unit)
            if inRange then state="fight"; Paint(); return end
            if inRange==nil then unknown=true end
        elseif enemy==nil then unknown=true end
    end
    state=unknown and "unknown" or "idle"
    Paint()
end
local function SafeRefresh()
    local ok=pcall(Refresh)
    if not ok then state,combat,skin="unknown",nil,nil; Paint() end
end
local function Start()
    if not initialized then return end
    if Bool(UnitIsDeadOrGhost,"player")~=false then Say("死亡或存活状态未知，无法启动。"); return end
    panel:Show()
    enabled,elapsed=true,0
    SafeRefresh()
end
save:SetScript("OnClick",function()
    if not initialized then return end
    local value=tonumber(input:GetText())
    if not value or value<1 or value~=math.floor(value) then Say("请输入已学会的伤害技能 ID。"); return end
    rangeSpell=value
    fightDetectorDB.rangeSpells[classID]=value
    input:ClearFocus()
    SafeRefresh()
end)
start:SetScript("OnClick",Start)
close:SetScript("OnClick",function() Stop(); panel:Hide() end)
panel:SetScript("OnHide",function() Stop() end)
signal:Hide()
WoWTools.modules.fight_detector={
    IsShown=function() return panel:IsShown() end,
    Show=Start,
    Hide=function() Stop(); panel:Hide() end,
    Toggle=function() if panel:IsShown() then Stop(); panel:Hide() else Start() end end,
}
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_DEAD","PLAYER_LOGOUT",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","PLAYER_SOFT_ENEMY_CHANGED",
    "PLAYER_SOFT_INTERACT_CHANGED","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED",
    "LOOT_OPENED","LOOT_CLOSED","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event,arg)
    if event=="ADDON_LOADED" then
        if arg~="wow_tools" then return end
        if type(fightDetectorDB)~="table" then fightDetectorDB={} end
        if type(fightDetectorDB.rangeSpells)~="table" then fightDetectorDB.rangeSpells={} end
        local ok,_,_,id=pcall(UnitClass,"player")
        if not ok or not Readable(id) or type(id)~="number" or id<1 or id>13 then return end
        classID=id
        rangeSpell=fightDetectorDB.rangeSpells[id] or defaults[id]
        input:SetText(tostring(rangeSpell))
        initialized=true
        Stop()
    elseif event=="NAME_PLATE_UNIT_ADDED" then
        if Readable(arg) and type(arg)=="string" then nameplates[arg]=true end
    elseif event=="NAME_PLATE_UNIT_REMOVED" then
        if Readable(arg) and type(arg)=="string" then nameplates[arg]=nil end
    elseif event=="PLAYER_ENTERING_WORLD" then
        nameplates={}
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
    elseif event=="PLAYER_DEAD" or event=="PLAYER_LOGOUT" then Stop()
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
    elseif command=="status" then Say((descriptions[state] or state).." · rangeSpell="..tostring(rangeSpell).." · class="..tostring(classID))
    else Start() end
end
