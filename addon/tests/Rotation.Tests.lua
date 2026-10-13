-- Each client's own Rotation.lua, Lua 5.1. No game operations or account files.
local root = TEST_ROOT or "."
for _, flavor in ipairs({"titan", "forerver"}) do
    local frames, combat, dead, secret, width, height, uiHeight = {}, false, false, {}, 1920, 1080, 768
    local function widget()
        local o = {shown = true, scripts = {}, textures = {}}
        function o:SetScript(event, fn) self.scripts[event] = fn end
        function o:CreateTexture() local t = widget(); self.textures[#self.textures+1] = t; return t end
        function o:SetColorTexture(...) self.color = {...} end
        function o:SetSize(w,h) self.width,self.height = w,h end
        function o:Show() self.shown = true end
        function o:Hide() self.shown = false end
        function o:GetHeight() return uiHeight end
        function o:SetPoint(...) self.point = {...} end
        function o:SetFrameStrata() end
        function o:SetAllPoints() end
        function o:RegisterEvent() end
        return o
    end
    UIParent = widget()
    function CreateFrame() local f = widget(); frames[#frames+1] = f; return f end
    function UnitGUID() return "Player-mock" end
    function UnitIsDeadOrGhost() return dead end
    function UnitAffectingCombat() return combat end
    function GetPhysicalScreenSize() return width,height end
    function issecretvalue(v) return v == secret end
    SlashCmdList, wowRotationDB = {}, nil
    dofile(root .. "/addon/" .. flavor .. "/wow_tools/Init.lua")
    local stops = 0
    for _, name in ipairs({"wowDetector", "fight_detector"}) do
        WoWTools.modules[name] = {Hide=function() stops=stops+1 end, IsEnabled=function() return false end, IsShown=function() return false end}
    end
    dofile(root .. "/addon/" .. flavor .. "/wow_tools/Rotation.lua")
    local marker, watcher = frames[2], frames[3]
    assert(not marker.shown, "Marker shown before entering world")
    marker.scripts.OnEvent(marker, "PLAYER_ENTERING_WORLD")
    local color = marker.textures[1].color
    assert(marker.shown and math.floor(color[1]*255+0.5)==20 and color[2]*255==231 and color[3]*255==157, "World-ready marker token 0 invalid")
    SlashCmdList.WOWROTATE("arm 77")
    assert(stops==2 and wowRotationDB.Token==77 and marker.shown, "Arm did not close both detectors")
    combat=true; watcher.scripts.OnUpdate(watcher,0.1)
    assert(marker.textures[1].color[3]*255==181, "Combat falsely reported ready for logout")
    combat=false; marker.scripts.OnEvent(marker,"PLAYER_LEAVING_WORLD")
    assert(not marker.shown and wowRotationDB.Token==77, "Logout did not hide/preserve token")
    marker.scripts.OnEvent(marker,"PLAYER_ENTERING_WORLD")
    assert(marker.shown and marker.textures[1].color[1]*255==97, "Relog lost armed token")
    for _, size in ipairs({{1280,720,768},{2560,1440,960},{800,600,720}}) do
        width,height,uiHeight = unpack(size); watcher.scripts.OnUpdate(watcher,0.1)
        assert(math.abs(marker.width*height/uiHeight-32)<0.001 and marker.point[2]==WoWTools.detectorAnchor,"Resize did not keep marker at shared center/32 physical pixels")
    end
    dead=true; watcher.scripts.OnUpdate(watcher,0.1); assert(not marker.shown,"Dead character reported world ready")
    dead=false; combat=secret; watcher.scripts.OnUpdate(watcher,0.1); assert(not marker.shown,"Restricted combat value accepted")
    combat=false; height=secret; watcher.scripts.OnUpdate(watcher,0.1); assert(not marker.shown,"Restricted screen height accepted")
    height=1080; watcher.scripts.OnUpdate(watcher,0.1); assert(marker.shown,"Hidden marker could not recover through visible watcher")
    SlashCmdList.WOWROTATE("arm 201"); assert(wowRotationDB.Token==77,"Invalid command changed token")
    WoWTools.ActivateDetector("wowDetector")
    assert(not marker.shown and wowRotationDB.Token==nil,"Detector activation did not remove shared marker")
    marker.scripts.OnEvent(marker,"PLAYER_ENTERING_WORLD"); SlashCmdList.WOWROTATE("clear")
    assert(not marker.shown,"Clear did not hide marker")
    print("PASS: " .. flavor .. " world-entry token, combat/death/restricted-data gates, logout/login persistence, physical scaling, hidden recovery and detector cleanup. APIs mocked.")
end
