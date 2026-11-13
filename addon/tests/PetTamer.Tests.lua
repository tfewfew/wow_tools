local root = TEST_ROOT or "."
for _, flavor in ipairs({"titan", "forerver"}) do
    local frames, widgets, named = {}, {}, {}
    local guid, targetName, combat, dead, attackable = nil, "稀有野兽", false, false, true
    local unknown, targetDead, ghost = false, false, false
    local secret = setmetatable({}, {__eq=function() error("restricted comparison") end})
    local function widget(name, kind)
        local object = {shown=true, scripts={}, events={}, textures={}, text=""}
        function object:SetScript(event, fn) self.scripts[event]=fn end
        function object:RegisterEvent(event) self.events[event]=true end
        function object:UnregisterEvent(event) self.events[event]=nil end
        function object:CreateTexture() local t=widget(); self.textures[#self.textures+1]=t; return t end
        function object:CreateFontString() return widget(nil, "FontString") end
        function object:SetSize(w,h) self.width,self.height=w,h end
        function object:GetHeight() return self.height or 1080 end
        function object:SetHeight(height) self.height = height end
        function object:SetPoint(...) self.point={...} end
        function object:SetColorTexture(...) self.color={...} end
        function object:SetText(text)
            if self.text == text then return end
            self.text = text
            if kind == "EditBox" and self.scripts.OnTextChanged then
                self.scripts.OnTextChanged(self, false)
            end
        end
        function object:GetText() return self.text end
        if kind == "FontString" then
            function object:GetStringHeight() return 100 end
        end
        if kind == "EditBox" then
            function object:GetFont() return "mock-font", 12, "" end
            function object:GetNumLines()
                local _, newlines = self.text:gsub("\n", "")
                return newlines + 1
            end
            function object:GetSpacing() return self.spacing or 0 end
        end
        function object:Show() self.shown=true end
        function object:Hide()
            local shown=self.shown;self.shown=false
            if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function object:IsShown() return self.shown end
        for _,method in ipairs({"SetAllPoints","SetFrameStrata","SetClampedToScreen","SetMovable","EnableMouse",
            "RegisterForDrag","StartMoving","StopMovingOrSizing","SetWidth","SetMultiLine",
            "SetFontObject","SetAutoFocus","SetMaxLetters","SetScrollChild","ClearFocus","ClearAllPoints"}) do
            object[method]=function() end
        end
        if name then named[name]=object end
        widgets[#widgets+1]=object
        return object
    end
    function CreateFrame(kind,name) local f=widget(name,kind);frames[#frames+1]=f;return f end
    UIParent=widget();SlashCmdList={};wowDetectorDB={petTamer={names={" 稀有野兽 ","稀有野兽",""}}}
    DEFAULT_CHAT_FRAME={AddMessage=function() end}
    function issecretvalue(value) return rawequal(value,secret) end
    function GetPhysicalScreenSize() return 1920,1080 end
    function UnitGUID() return unknown and secret or guid end
    function UnitName() return targetName end
    function UnitExists() return guid~=nil end
    function UnitAffectingCombat() return combat end
    function UnitIsDead(unit) if unit=="player" then return dead end; return targetDead end
    function UnitIsGhost() return ghost end
    function UnitCanAttack() return attackable end
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    dofile(addon.."Init.lua")
    local fish, fight = true, false
    WoWTools.modules.wowDetector={IsEnabled=function() return fish end,IsShown=function() return fish end,Hide=function() fish=false end}
    WoWTools.modules.fight_detector={IsEnabled=function() return fight end,IsShown=function() return fight end,Hide=function() fight=false end}
    dofile(addon.."PetTamer.lua")
    local eventFrame
    for _,frame in ipairs(frames) do if frame.events.ADDON_LOADED then eventFrame=frame end end
    eventFrame.scripts.OnEvent(eventFrame,"ADDON_LOADED","wow_tools")
    local module=WoWTools.modules.pet_tamer
    local signal=named.wowToolsPetTamerSignal
    local input=named.wowToolsPetTamerNames
    local save
    for _,object in ipairs(widgets) do if object.text=="保存名单" then save=object end end
    assert(not module.IsEnabled() and not signal.shown and not eventFrame.scripts.OnUpdate)
    assert(input.text=="稀有野兽","Saved names were not normalized")
    do
        assert(input.GetStringHeight == nil and input:GetHeight() == 182, "Forever EditBox API or minimum height mismatch")
        input.spacing = 3
        input:SetText(string.rep("宠物\n", 29) .. "宠物")
        assert(input:GetHeight() == 467, "Standalone taming text height missed lines or spacing")
        input:SetText("")
        assert(input:GetHeight() == 182, "Clearing the standalone taming list retained its old height")
        input:SetText("稀有野兽")
    end
    SlashCmdList.PETTAMER("on")
    assert(module.IsEnabled() and not fish and signal.shown,"Taming did not exclude fishing")
    local function refresh() eventFrame.scripts.OnUpdate(eventFrame,.1) end
    local function state(expected,isCombat)
        local main,aux=signal.textures[1].color,signal.textures[2].color
        assert(math.abs(main[1]*255-211)<.01)
        assert(math.abs(main[2]*255-(11+24*(expected+(isCombat and 4 or 0))))<.01,"Wrong taming state")
        assert(math.abs(aux[2]*255-223)<.01)
        assert(math.abs(aux[3]*255-(flavor=="titan" and 71 or 79))<.01,"Wrong flavor")
        return math.floor(main[3]*255/4+.5)+64*math.floor((aux[1]*255-3)/4+.5)
    end
    state(0,false)
    guid="beast-one";refresh();local first=state(1,false)
    combat=true;refresh();assert(state(1,true)==first,"Combat changed the target token")
    guid="beast-two";refresh();assert(state(1,true)~=first,"Same-name target retained old token")
    targetName="稀有野兽幼崽";refresh();state(0,true)
    targetName="稀有野兽";unknown=true;refresh();state(2,false)
    unknown=false;targetDead=true;refresh();state(0,true)
    targetDead=false;attackable=false;refresh();state(0,true)
    attackable=true;dead=true;refresh();state(3,false)
    dead=false;ghost=true;refresh();state(3,false)
    ghost=false;combat=false;refresh();state(1,false)
    input:SetText("  新宠物  \n新宠物\r\n\n稀有野兽\n")
    save.scripts.OnClick()
    assert(#wowDetectorDB.petTamer.names==2 and wowDetectorDB.petTamer.names[1]=="新宠物","Names did not persist/deduplicate")
    SlashCmdList.PETTAMER("off")
    assert(not module.IsEnabled() and not signal.shown and not eventFrame.scripts.OnUpdate,"Stop left taming active")
    assert(not eventFrame.events.PLAYER_TARGET_CHANGED and eventFrame.events.ADDON_LOADED,"Stop retained business events")
    SlashCmdList.PETTAMER("on");fight=true;WoWTools.ActivateDetector("fight_detector")
    assert(not module.IsEnabled() and not signal.shown,"Combat did not exclude taming")
    dofile(addon.."PetTamer.lua")
    for _,frame in ipairs(frames) do if frame.events.ADDON_LOADED then eventFrame=frame end end
    eventFrame.scripts.OnEvent(eventFrame,"ADDON_LOADED","wow_tools")
    assert(named.wowToolsPetTamerNames.text=="新宠物\n稀有野兽","Reload lost persisted names")
end
print("PASS: both pet taming addons, exact target names, persistent lists, target tokens, combat/death/restricted values, detector exclusion and shutdown. No game input.")
