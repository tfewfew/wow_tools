-- Read-only login readiness point and detector exclusion; no game input.
local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local file=assert(io.open(root.."/addon/"..flavor.."/wow_tools/wow_tools.toc","r"))
    local toc=file:read("*a"); file:close()
    assert(toc:find("LoginPoint.lua",1,true),"TOC does not load permanent readiness point")
    assert(not toc:find("Rotation.lua",1,true) and not toc:find("wowRotationDB",1,true),"Old request marker returned")
    local frames={}
    local width,height,scale=1280,720,1
    UIParent={}
    local positionReads=0
    function GetPhysicalScreenSize() positionReads=positionReads+1; return width,height end
    function issecretvalue() return false end
    function CreateFrame(_,name)
        local f={scripts={},shown=true}
        function f:SetSize(w,h) self.width,self.height=w,h end
        function f:SetPoint(...) self.point={...} end
        function f:SetFrameStrata() end
        function f:SetFrameLevel() end
        function f:EnableMouse(enabled) self.mouse=enabled end
        function f:SetIgnoreParentAlpha() end
        function f:ClearAllPoints() end
        function f:GetEffectiveScale() return scale end
        function f:Show() self.shown=true end
        function f:Hide() self.shown=false end
        function f:RegisterEvent() end
        function f:SetScript(event,fn) self.scripts[event]=fn end
        function f:CreateTexture()
            local texture={}
            function texture:SetAllPoints() end
            function texture:SetColorTexture(...) self.color={...} end
            self.texture=texture
            return texture
        end
        frames[#frames+1]=f
        return f
    end
    dofile(root.."/addon/"..flavor.."/wow_tools/Init.lua")
    dofile(root.."/addon/"..flavor.."/wow_tools/LoginPoint.lua")
    local point,events=WoWTools.loginPoint,frames[3]
    assert(not point.shown and point.mouse==false,"Point shown before world entry or intercepts clicks")
    for _,size in ipairs({{1280,720},{1920,1080},{3840,2160}}) do
        for _,uiScale in ipairs({.64,1,1.2}) do
            width,height,scale=size[1],size[2],uiScale
            events.scripts.OnEvent(events,"PLAYER_ENTERING_WORLD")
            assert(point.shown,"Point absent with detectors disabled")
            assert(math.abs(point.width*scale*height/768-16)<.0001 and math.abs(point.height*scale*height/768-16)<.0001,"Point is not 16 physical pixels")
            assert(point.point[1]=="BOTTOMRIGHT" and point.point[3]=="BOTTOMRIGHT","Point does not follow client bottom-right")
            assert(math.abs(point.point[4]*scale*height/768+16)<.0001 and math.abs(point.point[5]*scale*height/768-16)<.0001,"Point is not inset 16 physical pixels from rounded corners")
            assert(point.texture.color[1]==1 and point.texture.color[2]==1 and point.texture.color[3]==1,"Point is not white")
        end
    end
    local reads=positionReads
    events.scripts.OnUpdate(events,.5)
    assert(positionReads==reads,"Permanent point recalculated before one second")
    events.scripts.OnUpdate(events,.5)
    assert(positionReads==reads+1,"Permanent point did not recalculate after one second")
    local stopped=0
    WoWTools.modules.wowDetector={IsEnabled=function() return true end,Hide=function() stopped=stopped+1 end}
    WoWTools.modules.fight_detector={IsEnabled=function() return false end,IsShown=function() return false end}
    WoWTools.ActivateDetector("fight_detector")
    assert(stopped==1 and point.shown,"Detector switch hid permanent point or broke exclusion")
    events.scripts.OnEvent(events,"PLAYER_LEAVING_WORLD")
    assert(not point.shown and not events.scripts.OnUpdate,"Point remains visible or polls while loading")
    events.scripts.OnEvent(events,"PLAYER_ENTERING_WORLD")
    events.scripts.OnEvent(events,"PLAYER_LOGOUT")
    assert(not point.shown,"Point remains visible after logout")
    print("PASS: "..flavor.." permanent point scales to physical pixels and remains independent of detectors.")
end
