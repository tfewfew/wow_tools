local root=TEST_ROOT or "."
local output=TEST_PIXEL_OUTPUT and assert(io.open(TEST_PIXEL_OUTPUT,"w"))
for _,flavor in ipairs({"titan","forerver"}) do
    local frames,names,edits,buttons={}, {}, {}, {}
    local now,combat,dead,health=0,false,false,100
    local uiScale,screenWidth,screenHeight=1,1920,1080
    local mobs, class={}, nil
    local secret=setmetatable({}, {__eq=function() error("Compared secret") end,__tostring=function() error("Printed secret") end})
    local restricted,failed,missing,conflicting,castFails=false,false,false,false,false
    local messages,warm={},0
    function issecretvalue(value) return rawequal(value,secret) end
    local distances={[8149]=5,[15826]=5,[16308]=5,[9606]=10,[17626]=10,[17689]=10,[4559]=15,
        [1191]=20,[4388]=20,[10645]=20,[13289]=25,[835]=30,[1404]=30,[2091]=30,[4941]=30,
        [1258]=35,[18904]=35,[4945]=40,[8348]=40}
    local function check(item,unit)
        if failed then error("range unavailable") end
        if missing then return nil end
        if restricted and distances[item]==5 then return secret end
        if conflicting and item==15826 then return false end
        local mob=mobs[unit]
        return mob and mob.distance<=distances[item] or false
    end
    C_Item={IsItemInRange=check,RequestLoadItemDataByID=function() warm=warm+1 end}
    C_Spell={IsSpellHarmful=function(id) return id==2764 end}
    function UnitDistanceSquared() error("Do not infer enemy yards from unavailable coordinates") end
    function UnitPosition() error("Do not read enemy positions") end
    local function widget(name)
        local o={scripts={},events={},textures={},shown=true,text=""}
        function o:SetScript(event,fn) self.scripts[event]=fn end
        function o:RegisterForClicks() end
        function o:SetAttribute(key,value) assert(not combat,"Secure attribute changed during combat"); self[key]=value end
        function o:RegisterEvent(event) self.events[event]=true end
        function o:UnregisterEvent(event) self.events[event]=nil end
        function o:CreateTexture() local t=widget(); self.textures[#self.textures+1]=t; return t end
        function o:CreateFontString() return widget() end
        function o:SetPoint(...) self.point={...} end
        function o:SetSize(w,h) self.width,self.height=w,h end
        function o:SetColorTexture(...) self.color={...} end
        function o:SetText(text) self.text=text end
        function o:GetText() return self.text end
        function o:GetEffectiveScale() return uiScale end
        function o:GetHeight() return 768/uiScale end
        function o:Show() self.shown=true end
        function o:Hide() self.shown=false end
        function o:IsShown() return self.shown end
        for _,method in ipairs({"SetAllPoints","SetFrameStrata","SetClampedToScreen","SetMovable","EnableMouse",
            "RegisterForDrag","StartMoving","StopMovingOrSizing","SetWidth","SetHeight","SetJustifyH",
            "SetAutoFocus","SetNumeric","SetMaxLetters","ClearFocus","ClearAllPoints","Enable","Disable"}) do o[method]=function() end end
        if name then names[name]=o end
        return o
    end
    function CreateFrame(kind,name)
        local o=widget(name); frames[#frames+1]=o
        if kind=="EditBox" then edits[#edits+1]=o elseif kind=="Button" then buttons[#buttons+1]=o end
        return o
    end
    UIParent=widget(); SlashCmdList={}; DEFAULT_CHAT_FRAME={AddMessage=function(_,m) messages[#messages+1]=m end}
    function GetPhysicalScreenSize() return screenWidth,screenHeight end
    function GetTime() return now end
    function UnitClass() return "模拟职业","TEST",class end
    function UnitExists(unit) return unit=="player" or mobs[unit]~=nil end
    function UnitIsDeadOrGhost(unit) if unit=="player" then return dead end; return mobs[unit] and mobs[unit].dead or false end
    function UnitIsPlayer() return false end
    function UnitCanAttack(_,unit) return mobs[unit]~=nil end
    function UnitGUID(unit) assert(unit~="focus", "Detector still reads focus"); local mob=mobs[unit]; return mob and mob.guid end
    function InCombatLockdown() return combat end
    function SetOverrideBindingClick() error("Detector still overrides the targeting key") end
    function ClearOverrideBindings() error("Detector still clears targeting bindings") end
    function UnitAffectingCombat() return combat end
    function UnitIsInteractable(unit)
        assert(unit=="softinteract")
        local mob=mobs[unit]
        return mob and mob.interactable or false
    end
    function CanLootUnit(guid)
        local mob=mobs.softinteract
        assert(mob and mob.guid==guid)
        return mob.loot,mob.canLoot
    end
    UNIT_SKINNABLE="Skinnable"
    C_TooltipInfo={GetUnit=function(unit)
        assert(unit=="softinteract")
        return {lines=mobs.softinteract and mobs.softinteract.skinnable and
            {{leftText=UNIT_SKINNABLE,leftColor={GetRGB=function() return 0,1,0 end}}} or {}}
    end}
    function UnitHealth() return health end
    function UnitHealthMax() return 100 end
    function UnitCastingInfo() if castFails then error("cast API unavailable") end; return nil end
    function UnitChannelInfo() return nil end
    local function event(name,argument,...)
        for _,f in ipairs(frames) do if f.events[name] then f.scripts.OnEvent(f,name,argument,...) end end
    end
    local function tick()
        now=now+.1
        for _,f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,.1) end end
    end
    local function setup(id,db)
        frames,names,edits,buttons={}, {}, {}, {}; class=id; fightDetectorDB=db
        dofile(root.."/addon/"..flavor.."/wow_tools/Init.lua")
        dofile(root.."/addon/"..flavor.."/wow_tools/fight_detector/Range.lua")
        dofile(root.."/addon/"..flavor.."/wow_tools/fight_detector/fight_detector.lua")
        event("ADDON_LOADED","wow_tools")
        assert(not WoWTools.modules.fight_detector.IsEnabled(),"Initial combat flag enables loot")
        local detector
        for _,f in ipairs(frames) do if #f.textures==2 then detector=f end end
        assert(detector,"Expected exactly two V7 cells")
        return detector
    end
    local saved={rangeSpells={[1]=78},profiles={[3]={DetectionRangeYards=20}}}
    local signal=setup(1,saved)
    local codes={unknown=0,idle=1,opening=2,waiting=3,combat=4,loot=5,skin=6}
    local function pixel(cell)
        local c=cell.color
        return math.floor(c[1]*255+.5)+256*math.floor(c[2]*255+.5)+65536*math.floor(c[3]*255+.5)
    end
    local function expect(action)
        local main=signal.textures[1]
        assert(main.color and #signal.textures==2,flavor..": main cell missing")
        local value=math.floor(main.color[1]*255+.5)
        assert(value==5+20*codes[action],flavor..": expected "..action.." but main red="..value)
        assert(main.shown and signal.textures[2].shown,"Active cells hidden")
        if output then output:write(flavor," ",action," ",tostring(pixel(main))," ",tostring(pixel(signal.textures[2])),"\n") end
    end
    local function epoch() return (signal.textures[1].color[3]*255/4)%32 end
    local function geometry()
        for i,cell in ipairs(signal.textures) do
            local unit=UIParent:GetHeight()/screenHeight
            assert(math.abs(cell.point[4]/unit-(i==2 and 32 or 0))<.001
                and math.abs(cell.point[5]/unit)<.001 and math.abs(cell.width/unit-(i==1 and 32 or 12))<.001,
                "Physical geometry did not survive window/UI scaling")
        end
    end
    assert(edits[1].text=="30" and edits[2].text=="5" and warm==0,"Inactive detector warmed item cache")
    assert(not WoWTools.FightRange.IsSupported(secret) and not WoWTools.FightRange.IsSupported(12))
    mobs.target={guid="Creature-A",distance=31}
    SlashCmdList.FIGHTDETECTOR("on"); expect("idle")
    assert(warm>0 and WoWTools.modules.fight_detector.IsEnabled(),"Detector did not start")
    geometry()
    local stable={unpack(signal.textures[1].color)}
    tick()
    for i=1,3 do assert(signal.textures[1].color[i]==stable[i],"Unchanged state depends on heartbeat") end
    for _,size in ipairs({{1280,720,.5},{2560,1440,1.25},{1279,719,.85},{1920,1080,1}}) do
        screenWidth,screenHeight,uiScale=unpack(size)
        event("DISPLAY_SIZE_CHANGED");event("UI_SCALE_CHANGED");geometry()
    end
    mobs.target.distance=30; tick(); expect("opening")
    local first=epoch()
    mobs.target.distance=5; tick(); expect("opening")
    event("UNIT_SPELLCAST_SUCCEEDED","player",secret,2764); expect("opening")
    combat=true;mobs.target.distance=30;tick();expect("waiting")
    mobs.target.distance=5;tick();expect("combat")
    castFails=true;tick();expect("waiting")
    assert(signal.textures[1].color[2]>.4,"Uncertain combat cast did not block input")
    castFails=false;tick();expect("combat")
    health=20;tick();expect("combat")
    assert(signal.textures[2].color[1]==1 and signal.textures[2].color[2]==.15,
        "Emergency recovery hint did not remain in auxiliary cell")
    mobs.target.distance=20;tick();expect("waiting")
    mobs.target.distance=50;tick();expect("waiting")
    assert(epoch()==first,"Retreat changed tracked encounter")
    mobs.target.dead=true;combat=false;health=100;tick();expect("idle")
    mobs.target=nil
    mobs.softinteract={guid="Creature-CORPSE-A",dead=true,interactable=true,loot=true,canLoot=true,skinnable=true}
    tick();expect("loot")
    local corpseEpoch=epoch()
    mobs.softinteract.loot=false;tick();expect("skin")
    assert(epoch()==corpseEpoch,"Loot-to-skin changed corpse identity")
    mobs.softinteract=nil;tick();expect("idle")
    mobs.softinteract={guid="Creature-CORPSE-B",dead=true,interactable=true,loot=true,canLoot=true,skinnable=true}
    tick();expect("loot")
    assert(epoch()~=corpseEpoch,"New corpse inherited previous identity")
    mobs.softinteract.canLoot=false;tick();expect("idle")
    mobs.softinteract=nil
    mobs.nameplate1={guid="Creature-NEW",distance=10}
    event("NAME_PLATE_UNIT_ADDED","nameplate1");tick();expect("opening")
    assert(not names.wowToolsFightTargetButton,"Plugin created a targeting button")
    mobs.target=mobs.nameplate1;mobs.target.distance=5;combat=true;tick();expect("combat")
    mobs.target=nil;tick();expect("waiting")
    mobs.target={guid="Creature-OTHER",distance=5};tick();expect("waiting")
    mobs.target=nil
    combat=false;mobs.nameplate1=nil;event("NAME_PLATE_UNIT_REMOVED","nameplate1");tick();expect("idle")
    health=70;tick();expect("idle")
    assert(signal.textures[2].color[3]==1,"Ordinary recovery hint disappeared")
    health=secret;tick();expect("idle")
    assert(signal.textures[2].color[1]==.5,"Unknown recovery did not stay in auxiliary cell")
    health=100
    mobs.target={guid="Creature-RANGE",distance=5}
    tick();expect("opening")
    combat=true;tick();expect("combat")
    mobs.softinteract={guid="Creature-CORPSE-C",dead=true,interactable=true,loot=true,canLoot=true}
    restricted=true;tick();expect("waiting")
    restricted=false;failed=true;tick();expect("waiting")
    failed=false;missing=true;tick();expect("waiting")
    missing=false;conflicting=true;tick();expect("waiting")
    conflicting=false;tick();expect("combat")
    health=secret;tick();expect("combat")
    assert(signal.textures[2].color[1]==.5,"Unknown recovery changed the combat main state")
    health=100
    dead=secret;tick();expect("waiting")
    dead=false;tick();expect("combat")
    combat=secret;tick();expect("unknown")
    combat=true;tick();expect("combat")
    local originalPaint=signal.textures[1].SetColorTexture
    local failOnce=true
    signal.textures[1].SetColorTexture=function(self,...)
        if failOnce then failOnce=false;error("transient paint error") end
        return originalPaint(self,...)
    end
    tick();expect("waiting")
    tick();expect("combat")
    signal.textures[1].SetColorTexture=originalPaint
    mobs.softinteract=nil
    combat=false;tick();expect("opening")
    failed=true;tick();expect("unknown")
    failed=false;tick();expect("opening")
    dead=true;event("PLAYER_DEAD")
    assert(not signal.shown and not WoWTools.modules.fight_detector.IsEnabled(),"Death did not stop detector")
    dead=false;mobs={};signal=setup(3,saved)
    assert(edits[1].text=="20" and edits[2].text=="5","Class range preference was lost")
    mobs.target={guid="Creature-MID-COMBAT",distance=5};combat=true
    SlashCmdList.FIGHTDETECTOR("on");expect("combat")
    mobs.target=nil;tick();expect("waiting")
    print("PASS: "..flavor.." combat-only waiting/combat priority, mid-combat target acquisition, range uncertainty, six-state V7 colors, recovery hint isolation and scaling. Game APIs mocked.")
end
if output then output:close() end
