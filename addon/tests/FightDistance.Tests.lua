local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local frames,names,edits,buttons={}, {}, {}, {}
    local now,combat,dead,health=0,false,false,100
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
        function o:RegisterEvent(event) self.events[event]=true end
        function o:CreateTexture() local t=widget(); self.textures[#self.textures+1]=t; return t end
        function o:CreateFontString() return widget() end
        function o:SetPoint(...) self.point={...} end
        function o:SetSize(w,h) self.width,self.height=w,h end
        function o:SetColorTexture(...) self.color={...} end
        function o:SetText(text) self.text=text end
        function o:GetText() return self.text end
        function o:GetEffectiveScale() return 1 end
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
    function GetPhysicalScreenSize() return 1920,1080 end
    function GetTime() return now end
    function UnitClass() return "模拟职业","TEST",class end
    function UnitExists(unit) return unit=="player" or mobs[unit]~=nil end
    function UnitIsDeadOrGhost(unit) if unit=="player" then return dead end; return mobs[unit] and mobs[unit].dead or false end
    function UnitIsPlayer() return false end
    function UnitCanAttack(_,unit) return mobs[unit]~=nil end
    function UnitGUID(unit) return mobs[unit] and mobs[unit].guid end
    function UnitAffectingCombat() return combat end
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
        local detector
        for _,f in ipairs(frames) do if #f.textures==10 then detector=f end end
        assert(detector,"Missing V3 nine-cell protocol and recovery point")
        return detector
    end
    local saved={rangeSpells={[1]=78},profiles={[3]={DetectionRangeYards=20}}}
    local signal=setup(1,saved)
    local function color(r,g,b)
        local c=signal.textures[2].color
        assert(c[1]==r/255 and c[2]==g/255 and c[3]==b/255,flavor..": unexpected main state")
    end
    local function epoch() return signal.textures[9].color[1] end
    assert(edits[1].text=="30" and edits[2].text=="5" and warm>0,"Default distances / item-cache warmup failed: "..edits[1].text.." / "..edits[2].text.." / "..warm)
    assert(not WoWTools.FightRange.IsSupported(secret) and not WoWTools.FightRange.IsSupported(12))
    mobs.target={guid="Creature-A",distance=31}
    SlashCmdList.FIGHTDETECTOR("on"); color(0,0,255)
    assert(math.abs(signal.textures[9].point[4]*1080/768-72)<.001
        and math.abs(signal.textures[10].point[4]*1080/768-88)<.001,"Encounter/recovery physical pixels do not match PC reader")
    mobs.target.distance=30; restricted=true; tick(); color(255,96,0) -- 5yd probe must not block opening.
    restricted=false; local first=epoch()
    event("UNIT_SPELLCAST_SUCCEEDED","player",secret,123); color(255,96,0)
    event("UNIT_SPELLCAST_SUCCEEDED","player",secret,secret); color(255,96,0)
    event("UNIT_SPELLCAST_SUCCEEDED","player",secret,2764); color(0,192,192)
    mobs.target.distance=5; tick(); color(255,0,0) -- Success is observed before the combat flag arrives.
    mobs.target.distance=30
    combat=true; tick(); color(0,192,192)
    mobs.target.distance=5; tick(); color(255,0,0)
    mobs.target.distance=6; tick(); color(0,192,192)
    mobs.target.distance=50; tick(); color(0,192,192); assert(epoch()==first,"Retreat changed tracked encounter")
    mobs.nameplate1={guid="Creature-B",distance=3}; event("NAME_PLATE_UNIT_ADDED","nameplate1"); tick()
    color(0,192,192); assert(epoch()==first,"Nearby other monster bypassed target's attack distance")
    mobs.target={guid="Creature-C",distance=5}; tick(); color(255,0,0); assert(epoch()~=first,"Target change did not change encounter")
    mobs.nameplate1=nil; event("NAME_PLATE_UNIT_REMOVED","nameplate1")
    restricted=true; tick(); color(128,128,128)
    restricted=false; failed=true; tick(); color(128,128,128)
    failed=false; missing=true; tick(); color(128,128,128)
    missing=false; conflicting=true; tick(); color(128,128,128)
    conflicting=false; mobs.target.guid=secret; tick(); color(128,128,128)
    mobs.target.guid="Creature-C"; health=20; mobs.target.distance=20; tick(); color(0,192,192)
    local rc=signal.textures[10].color; assert(rc[1]==1 and rc[2]==128/255,"Recovery signal lost during waiting")
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
    dead=true; event("PLAYER_DEAD"); assert(not signal.shown,"Death did not stop detector")
    dead,combat=false,false; mobs={}
    setup(3,saved); assert(edits[1].text=="20" and edits[2].text=="10","Class-specific detection/global attack load failed")
    for _,b in ipairs(buttons) do if b.text=="保存" then save=b end end
    edits[1]:SetText("35"); edits[2]:SetText("15"); save.scripts.OnClick()
    setup(1,saved); assert(edits[1].text=="25" and edits[2].text=="15","Global attack did not apply to another class / detection overwritten")
    print("PASS: "..flavor.." yard probes, 30/5 defaults, exact thresholds, opening/wait/approach/retreat, target identity, unknown/secret/failure/conflict, legacy fallback, settings scope/validation and death. Game APIs mocked.")
end
