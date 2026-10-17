-- Both real detector modules run in each client's own Lua 5.1 simulation.
local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local frames,names={},{}
    local dead,combat=false,false
    local width,height,scale=1920,1080,1
    local binding=false
    local sound={Sound_EnableAllSound="0",Sound_MasterVolume="0.37",Sound_EnableSFX="0"}
    local original={}
    for key,value in pairs(sound) do original[key]=value end
    local function widget(parent,name)
        local o={parent=parent,scripts={},events={},textures={},shown=true,text="",attributes={}}
        function o:SetScript(event,fn) self.scripts[event]=fn end
        function o:RegisterEvent(event) self.events[event]=true end
        function o:UnregisterEvent(event) self.events[event]=nil end
        function o:CreateTexture() local t=widget(self); self.textures[#self.textures+1]=t; return t end
        function o:CreateFontString() return widget(self) end
        function o:SetPoint(...) self.point={...} end
        function o:GetPoint() return unpack(self.point) end
        function o:SetSize(w,h) self.width,self.height=w,h end
        function o:GetHeight() return self==UIParent and 768/scale or self.height end
        function o:GetEffectiveScale() return scale end
        function o:SetColorTexture(...) self.color={...} end
        function o:SetText(value) self.text=value end
        function o:GetText() return self.text end
        function o:Show() self.shown=true end
        function o:Hide()
            local shown=self.shown; self.shown=false
            if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function o:IsShown() return self.shown end
        function o:SetAttribute(key,value)
            assert(not combat,"Secure targeting changed during combat")
            self.attributes[key]=value
        end
        for _,method in ipairs({"SetAllPoints","SetFrameStrata","SetClampedToScreen","SetMovable",
            "EnableMouse","RegisterForDrag","RegisterForClicks","StartMoving","StopMovingOrSizing",
            "SetWidth","SetHeight","SetJustifyH","SetAutoFocus","SetNumeric","SetMaxLetters",
            "ClearFocus","ClearAllPoints","Enable","Disable","SetSnapToPixelGrid","SetTexelSnappingBias"}) do
            o[method]=function() end
        end
        if name then names[name]=o end
        return o
    end
    function CreateFrame(_,name,parent) local o=widget(parent,name); frames[#frames+1]=o; return o end
    UIParent=widget(); SlashCmdList={}; wowDetectorDB=nil; fightDetectorDB=nil
    DEFAULT_CHAT_FRAME={AddMessage=function() end}
    function issecretvalue() return false end
    function GetPhysicalScreenSize() return width,height end
    function UnitIsDeadOrGhost(unit) return unit=="player" and dead or false end
    local ghost=false
    UnitIsDead=UnitIsDeadOrGhost
    function UnitIsGhost() return ghost end
    function UnitAffectingCombat() return combat end
    function InCombatLockdown() return combat end
    function UnitClass() return "战士","WARRIOR",1 end
    function UnitExists(unit) return unit=="player" end
    function UnitIsPlayer() return false end
    function UnitCanAttack() return false end
    function UnitGUID() return nil end
    function UnitHealth() return 100 end
    function UnitHealthMax() return 100 end
    function UnitCastingInfo() return nil end
    function UnitChannelInfo() return nil end
    function GetInventoryItemLink() return nil end
    function GetContainerNumSlots(bag) return bag==0 and 16 or 0 end
    function GetContainerNumFreeSlots() return 10,0 end
    NUM_BAG_SLOTS=4
    C_Item={IsItemInRange=function() return false end,RequestLoadItemDataByID=function() end}
    C_Spell={GetSpellName=function() return "钓鱼" end}
    C_Container={GetContainerNumSlots=GetContainerNumSlots,GetContainerNumFreeSlots=GetContainerNumFreeSlots}
    C_CVar={GetCVar=function(key) return sound[key] end,SetCVar=function(key,value)
        assert(original[key]~=nil,"Changed an unrelated CVar"); sound[key]=value
    end}
    function SetOverrideBindingClick() assert(not combat); binding=true end
    function ClearOverrideBindings() assert(not combat); binding=false end
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    dofile(addon.."Init.lua")
    dofile(addon.."CharacterRecord.lua")
    local recordFrame=frames[#frames]
    local recordReads=0
    function UnitName() recordReads=recordReads+1;return "测试角色" end
    function UnitLevel() recordReads=recordReads+1;return 80 end
    function GetRealmName() return "测试服务器" end
    function time() return 1792200000 end
    wowToolsCharacterRecord=nil
    if flavor=="forerver" then dofile(addon.."Compatibility.lua") end
    dofile(addon.."Loot.lua")
    local lootFrame=frames[#frames]
    dofile(addon.."wowDetector/Audio.lua")
    dofile(addon.."wowDetector/wowDetector.lua")
    dofile(addon.."fight_detector/Range.lua")
    dofile(addon.."fight_detector/fight_detector.lua")
    local function event(name,...)
        for _,frame in ipairs(frames) do
            if frame.events[name] then frame.scripts.OnEvent(frame,name,...) end
        end
    end
    local function tick()
        for _,frame in ipairs(frames) do if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame,.1) end end
    end
    event("ADDON_LOADED","wow_tools")
    local fish,fight=WoWTools.modules.wowDetector,WoWTools.modules.fight_detector
    local fishPanel,fightPanel=names.wowDetectorPanel,names.wowToolsFightDetectorPanel
    local fightEvents
    for _,frame in ipairs(frames) do
        if frame~=fishPanel and frame.events.ADDON_LOADED then fightEvents=frame end
    end
    assert(fightEvents,"Missing combat lifecycle frame")
    local signal
    for _,frame in ipairs(frames) do if #frame.textures==2 and frame~=fishPanel then signal=frame end end
    assert(signal,"Missing combat signal")
    local function state(fishing,fighting)
        assert(fish.IsEnabled()==fishing and fight.IsEnabled()==fighting,flavor..": mutually exclusive state failed")
        assert(not not fishPanel.events.BAG_UPDATE_DELAYED==fishing and
            not not fightEvents.events.NAME_PLATE_UNIT_ADDED==fighting,
            flavor..": inactive detector retained business event subscriptions")
        assert((not not lootFrame.events.LOOT_OPENED)==(fishing or fighting) and
            (not not lootFrame.scripts.OnUpdate)==(fishing or fighting),
            flavor..": loot subscription did not follow the active detector")
        if not fishing and not fighting then
            for _,frame in ipairs(frames) do
                assert(not frame.scripts.OnUpdate,flavor..": inactive detector retained polling")
            end
        end
        if fishing then assert(not fight.IsShown() and not signal:IsShown(),"Inactive combat pixels remained visible") end
        if fighting then assert(not fish.IsShown() and signal:IsShown(),"Inactive fishing pixels remained visible") end
    end
    local function restored()
        for key,value in pairs(original) do assert(sound[key]==value,"Switch failed to restore fishing audio: "..key) end
    end
    local function geometry()
        local anchor=WoWTools.detectorAnchor
        assert(anchor.point[2]==UIParent and anchor.point[3]=="CENTER" and anchor.point[4]==0 and anchor.point[5]==0)
        assert(fishPanel.point[2]==anchor and fishPanel.point[3]=="CENTER")
        -- Fish indicator's center is (8+24/2,40/2-8-24/2) from panel LEFT.
        assert(fishPanel.point[4]+8+24/2==0 and fishPanel.point[5]+40/2-8-24/2==0)
        assert(signal.textures[1].point[2]==anchor and signal.textures[1].point[4]==0 and signal.textures[1].point[5]==0)
        local fishAux=fishPanel.textures[3]
        local unit=768/height/scale
        assert(math.abs(signal.textures[1].width/unit-32)<.001,"Main cell scaled incorrectly")
        assert(fishAux.point[2]==fishPanel.textures[2] and math.abs(fishAux.point[4]/unit-32)<.001)
        assert(signal.textures[2].point[2]==anchor and math.abs(signal.textures[2].point[4]/unit-32)<.001)
        assert(math.abs(fishAux.width/unit-12)<.001 and math.abs(signal.textures[2].width/unit-12)<.001)
    end
    state(false,false)
    assert(not recordFrame.events.PLAYER_LOGOUT and recordReads==0,"Inactive character record is subscribed or reading")
    SlashCmdList.WOWDETECTOR("on"); state(true,false)
    local lootStops=0
    local oldUnregister=lootFrame.UnregisterEvent
    lootFrame.UnregisterEvent=function(self,name) lootStops=lootStops+1; oldUnregister(self,name) end
    assert(wowDetectorDB.audioSnapshot and sound.Sound_MasterVolume=="1")
    SlashCmdList.FIGHTDETECTOR("on"); state(false,true); restored(); geometry()
    assert(lootStops==0,"Switching detectors briefly disabled loot processing")
    assert(not wowDetectorDB.locked and wowDetectorDB.panelHidden,"Fishing switch did not unlock/hide")
    assert(#signal.textures==2 and signal.textures[1].shown and signal.textures[2].shown,
        "V7 combat signal did not retain exactly two visible cells")
    SlashCmdList.FIGHTDETECTOR("on"); state(false,true)
    SlashCmdList.WOWDETECTOR("on"); state(true,false)
    SlashCmdList.WOWDETECTOR("hide"); assert(fish.IsEnabled() and not fish.IsShown())
    fight.Show(); state(false,true); restored()
    fish.Show(); state(true,false)
    fight.Toggle(); state(false,true)
    fish.Toggle(); state(true,false)
    -- Showing the inactive fishing panel without enabling it must not steal ownership.
    fight.Show(); SlashCmdList.WOWDETECTOR("show")
    assert(not fish.IsEnabled() and fight.IsEnabled() and signal:IsShown(),"Visibility-only command changed detector")
    -- A panel button start routes through the same exclusive transition.
    local fishButton
    for _,frame in ipairs(frames) do if frame.parent==fishPanel and frame.text=="启动" then fishButton=frame end end
    assert(fishButton); fishButton.scripts.OnClick(); state(true,false)
    local fightButton
    for _,frame in ipairs(frames) do if frame.parent==fightPanel and frame.text=="启动" then fightButton=frame end end
    assert(fightButton); fightButton.scripts.OnClick(); state(false,true)
    -- Blocked starts leave the other detector and its visible signal intact.
    dead=true; SlashCmdList.WOWDETECTOR("on")
    assert(not fish.IsEnabled() and fight.IsEnabled() and signal:IsShown(),"Rejected fishing start stopped combat")
    dead=false; fish.Show(); dead=true; fight.Show(); state(true,false)
    dead=false
    for _,viewport in ipairs({{1280,720,.5},{2560,1440,1.25},{1279,719,.85},{1920,1080,1}}) do
        width,height,scale=unpack(viewport)
        fish.Show(); event("DISPLAY_SIZE_CHANGED"); tick()
        fight.Show(); event("UI_SCALE_CHANGED"); tick(); state(false,true); geometry()
    end
    -- Switching detectors must never create or touch a combat target binding.
    combat=true; fish.Show(); state(true,false); assert(not binding,"Detector changed a target binding")
    combat=false; event("PLAYER_REGEN_ENABLED"); assert(not binding,"Deferred target binding survived")
    fish.Hide(); state(false,false); restored()
    assert(recordReads==0 and recordFrame.events.PLAYER_LOGOUT,"Stopping detection lost used-this-login flag or introduced background metadata reads")
    event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord and wowToolsCharacterRecord.level==80 and wowToolsCharacterRecord.freeBagSlots==10,"Real detector starts did not persist the logout record")
    event("ADDON_LOADED","wow_tools"); state(false,false)
    print("PASS: "..flavor.." real detector mutual exclusion via commands/buttons/module menu entries, hidden fishing, blocked starts, audio restoration, shared main/aux pixels across resize/UI scale and no target binding. No game actions.")
end
