local root=TEST_ROOT or "."
local output=TEST_PIXEL_OUTPUT and assert(io.open(TEST_PIXEL_OUTPUT,"w"))
for _,flavor in ipairs({"titan","forerver"}) do
    local frames,names,edits,buttons={}, {}, {}, {}
    local now,combat,dead,health=0,false,false,100
    local uiScale,screenWidth,screenHeight=1,1920,1080
    local mobs, class={}, nil
    local secret=setmetatable({}, {__eq=function() error("Compared secret") end,__tostring=function() error("Printed secret") end})
    local restricted,failed,missing,conflicting=false,false,false,false
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
    function UnitCastingInfo() return nil end
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
        for _,f in ipairs(frames) do if #f.textures==3 then detector=f end end
        assert(detector,"Expected two V5 cells with an inset inside the main cell")
        return detector
    end
    local saved={rangeSpells={[1]=78},profiles={[3]={DetectionRangeYards=20}}}
    local signal=setup(1,saved)
    local function centerCell()
        return signal.textures[3].shown and signal.textures[3] or signal.textures[1]
    end
    local function color(r,g,b)
        local expected={ ["128,128,128"]=0,["0,0,255"]=1,["255,96,0"]=2,["0,192,192"]=3,["255,0,0"]=4}
        local code=math.floor((signal.textures[3].color[1]*255-16)/8/4)
        assert(code==expected[r..","..g..","..b],flavor..": unexpected main state code "..code)
        local visual=signal.textures[1].color
        if not combat and code~=0 then
            assert(visual[1]==1 and visual[2]==0 and visual[3]==0 and signal.textures[3].shown,
                "Known noncombat state is not fishing waiting red")
        else
            assert(not signal.textures[3].shown,"Noncombat inset covered combat or unknown state")
            for i=1,3 do assert(visual[i]==signal.textures[3].color[i],"Combat center no longer matches data") end
        end
        if output then
            local function pixel(cell)
                local c=cell.color
                return math.floor(c[1]*255+.5)+256*math.floor(c[2]*255+.5)+65536*math.floor(c[3]*255+.5)
            end
            output:write(flavor," ",({[0]="unknown","idle","opening","waiting","combat"})[code]," ",
                tostring(pixel(centerCell()))," ",tostring(pixel(signal.textures[2])),"\n")
        end
    end
    local function epoch() return ((signal.textures[3].color[3]*255-2)/4)%32 end
    assert(edits[1].text=="30" and edits[2].text=="5" and warm==0,"Inactive detector warmed item cache")
    assert(not WoWTools.FightRange.IsSupported(secret) and not WoWTools.FightRange.IsSupported(12))
    mobs.target={guid="Creature-A",distance=31}
    SlashCmdList.FIGHTDETECTOR("on"); color(0,0,255)
    assert(warm>0,"Starting detector did not warm item cache")
    assert(WoWTools.modules.fight_detector.IsEnabled(),"Running combat flag disables loot")
    local function geometry()
        for i,cell in ipairs(signal.textures) do
            local unit=UIParent:GetHeight()/screenHeight
            assert(math.abs(cell.point[4]/unit-(i==2 and 32 or 0))<.001
                and math.abs(cell.point[5]/unit)<.001 and math.abs(cell.width/unit-(i==1 and 32 or (i==2 and 12 or 2)))<.001,
                "Physical geometry did not survive window/UI scaling")
        end
        local sampleX,sampleY=math.floor(screenWidth/2)+.5,math.floor(screenHeight/2)+.5
        assert(math.abs(sampleX-screenWidth/2)<1 and math.abs(sampleY-screenHeight/2)<1,
            "Script center sample falls outside the two-pixel inset")
    end
    local stable={unpack(signal.textures[3].color)}
    tick()
    for i=1,3 do assert(signal.textures[3].color[i]==stable[i],"Unchanged state still depends on heartbeat") end
    geometry()
    for _,size in ipairs({{1280,720,.5},{2560,1440,1.25},{1279,719,.85},{1920,1080,1}}) do
        screenWidth,screenHeight,uiScale=unpack(size)
        event("DISPLAY_SIZE_CHANGED"); event("UI_SCALE_CHANGED"); geometry()
    end
    for _,b in ipairs(buttons) do assert(b.text~="前" and b.text~="停止移动","Plugin still creates movement buttons") end
    mobs.target.distance=30; restricted=true; tick(); color(255,96,0) -- 5yd probe must not block opening.
    assert(not names.wowToolsFightTargetButton and not names.wowToolsFightTargetKeyInput,
        "Plugin still creates a target binding or key setting")
    restricted=false; local first=epoch()
    event("UNIT_SPELLCAST_SUCCEEDED","player",secret,123); color(255,96,0)
    event("UNIT_SPELLCAST_SUCCEEDED","player",secret,secret); color(255,96,0)
    event("UNIT_SPELLCAST_SUCCEEDED","player",secret,2764); color(255,96,0)
    mobs.target.distance=5; tick(); color(255,96,0) -- A successful spell alone does not end the opener retry phase.
    mobs.target.distance=30
    combat=true; tick(); color(0,192,192)
    mobs.target.distance=5; tick(); color(255,0,0)
    mobs.target.distance=6; tick(); color(0,192,192)
    mobs.target.distance=50; tick(); color(0,192,192); assert(epoch()==first,"Retreat changed tracked encounter")
    mobs.nameplate1={guid="Creature-B",distance=3}; event("NAME_PLATE_UNIT_ADDED","nameplate1"); tick()
    color(0,192,192); assert(epoch()==first,"Nearby other monster bypassed target's attack distance")
    mobs.nameplate2=mobs.target; event("NAME_PLATE_UNIT_ADDED","nameplate2")
    mobs.target={guid="Creature-C",distance=5}; tick()
    assert(math.floor(signal.textures[3].color[1]*255+.5)==240 and epoch()==first,"Combat target switch replaced locked encounter")
    mobs.target=mobs.nameplate2; mobs.nameplate2=nil; event("NAME_PLATE_UNIT_REMOVED","nameplate2"); tick(); color(0,192,192)
    mobs.target.distance=5; tick(); color(255,0,0)
    mobs.nameplate1=nil; event("NAME_PLATE_UNIT_REMOVED","nameplate1")
    restricted=true; tick(); color(128,128,128)
    restricted=false; failed=true; tick(); color(128,128,128)
    failed=false; missing=true; tick(); color(128,128,128)
    missing=false; conflicting=true; tick(); color(128,128,128)
    conflicting=false; mobs.target.guid=secret; tick(); color(128,128,128)
    mobs.target.guid="Creature-A"; health=20; mobs.target.distance=20; tick(); color(0,192,192)
    local recover=((signal.textures[3].color[1]*255-16)/8)%4; assert(recover==2,"Recovery signal lost during waiting")
    health=100; mobs.target.dead=true; combat=false; tick(); color(0,0,255)
    mobs.target={guid="Creature-D",distance=29}; tick(); color(255,96,0)
    local save
    for _,b in ipairs(buttons) do if b.text=="保存" then save=b end end
    edits[1]:SetText("12"); edits[2]:SetText("10"); save.scripts.OnClick()
    assert(saved.AttackRangeYards==nil and saved.profiles[1]==nil,"Invalid draft partially applied")
    edits[1]:SetText("25"); save.scripts.OnClick()
    assert(saved.AttackRangeYards==10 and saved.profiles[1].DetectionRangeYards==25 and saved.profiles[3].DetectionRangeYards==20 and saved.rangeSpells[1]==78,"Range scope / legacy settings isolation failed")
    mobs.target.distance=24; tick(); color(255,96,0)
    combat=true; mobs.target.distance=11; tick(); color(0,192,192)
    mobs.target.distance=10; tick(); color(255,0,0)
    C_Item.IsItemInRange=nil; IsItemInRange=function(item,unit) return check(item,unit) and 1 or 0 end
    tick(); color(255,0,0); C_Item.IsItemInRange=check; IsItemInRange=nil
    combat=false
    mobs={softinteract={guid="Creature-CORPSE-A",dead=true,interactable=true,loot=true,canLoot=true,skinnable=true}}
    tick(); assert(math.floor((signal.textures[3].color[1]*255-16)/8/4)==5,"Lootable corpse not detected")
    local corpseEpoch=epoch()
    mobs.softinteract.loot=false; mobs.softinteract.interactable=false; event("LOOT_CLOSED"); tick()
    color(0,0,255)
    mobs.softinteract.interactable=true; mobs.softinteract.skinnable=false; tick(); color(0,0,255)
    mobs.softinteract.skinnable=true; tick()
    assert(math.floor((signal.textures[3].color[1]*255-16)/8/4)==6 and epoch()==corpseEpoch,
        "Looted interactable corpse did not retain identity for skinning")
    mobs.softinteract=nil; tick()
    mobs.softinteract={guid="Creature-CORPSE-A",dead=true,interactable=true,loot=false,canLoot=true,skinnable=true}
    tick(); assert(epoch()==corpseEpoch,"Temporarily lost corpse gained a new interaction identity")
    mobs.softinteract={guid="Creature-CORPSE-B",dead=true,interactable=true,loot=true,canLoot=true,skinnable=true}
    tick(); assert(epoch()~=corpseEpoch,"Second corpse inherited the first corpse's interaction identity")
    mobs.softinteract.canLoot=false; tick(); color(0,0,255)
    dead=true; event("PLAYER_DEAD"); assert(not signal.shown,"Death did not stop detector")
    assert(not WoWTools.modules.fight_detector.IsEnabled(),"Combat death leaves loot enabled")
    dead,combat=false,false; mobs={}
    setup(3,saved); assert(edits[1].text=="20" and edits[2].text=="10","Class-specific detection/global attack load failed")
    for _,b in ipairs(buttons) do if b.text=="保存" then save=b end end
    edits[1]:SetText("35"); edits[2]:SetText("15"); save.scripts.OnClick()
    setup(1,saved); assert(edits[1].text=="25" and edits[2].text=="15","Global attack did not apply to another class / detection overwritten")
    -- Unselected nearby nameplate must request selection before opening.
    mobs={nameplate1={guid="Creature-NEW",distance=10}}
    signal=setup(1,saved)
    SlashCmdList.FIGHTDETECTOR("on")
    event("NAME_PLATE_UNIT_ADDED","nameplate1"); tick()
    assert(math.floor(signal.textures[3].color[1]*255+.5)==240,"Unselected nameplate opened without a target")
    assert(not names.wowToolsFightTargetButton,"Detector still created a secure target button")
    local selectedEpoch=epoch()
    mobs.target=mobs.nameplate1; tick(); color(255,96,0)
    assert(epoch()==selectedEpoch,"Confirming selection changed encounter")
    combat=true; mobs.target=nil; tick()
    assert(math.floor(signal.textures[3].color[1]*255+.5)==240 and epoch()==selectedEpoch,"Lost target did not request reselection")
    mobs.nameplate1=nil; event("NAME_PLATE_UNIT_REMOVED","nameplate1"); tick(); color(128,128,128)
    SlashCmdList.FIGHTDETECTOR("off")
    assert(not WoWTools.modules.fight_detector.IsEnabled(),"Combat close leaves loot enabled")
    combat=false; event("PLAYER_REGEN_ENABLED")
    mobs={}; health=70; SlashCmdList.FIGHTDETECTOR("on"); color(0,0,255)
    assert(((centerCell().color[1]*255-16)/8)%4==1
        and signal.textures[2].color[3]==1,"Red noncombat body lost recovery data or hint")
    health=secret; tick(); color(128,128,128)
    health=100; tick(); color(0,0,255)
    SlashCmdList.FIGHTDETECTOR("off")
    saved.TargetKey="Ctrl+Tab" -- Legacy SavedVariables must not restore a plugin binding.
    mobs.target={guid="Creature-KEY",distance=5}
    signal=setup(3,saved)
    SlashCmdList.FIGHTDETECTOR("on"); color(255,96,0)
    assert(not names.wowToolsFightTargetKeyInput and not names.wowToolsFightTargetButton,
        "Legacy target key restored a plugin setting or binding")
    print("PASS: "..flavor.." yard probes, selected-target opening without focus, no plugin key override, encounter tracking, unknown/secret/failure/conflict, legacy fallback, settings scope/validation and death. Game APIs mocked.")
end
if output then output:close() end
