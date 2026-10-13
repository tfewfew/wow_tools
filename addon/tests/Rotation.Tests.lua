-- Login and character navigation have no addon marker or saved request state.
local root = TEST_ROOT or "."
for _, flavor in ipairs({"titan", "forerver"}) do
    local file = assert(io.open(root .. "/addon/" .. flavor .. "/wow_tools/wow_tools.toc", "r"))
    local toc = file:read("*a"); file:close()
    assert(not toc:find("Rotation.lua", 1, true), "TOC still loads login marker")
    assert(not toc:find("wowRotationDB", 1, true), "TOC still saves login marker requests")
    local frames = 0
    UIParent = {}
    function CreateFrame()
        frames = frames + 1
        return {SetSize=function() end, SetPoint=function() end}
    end
    dofile(root .. "/addon/" .. flavor .. "/wow_tools/Init.lua")
    assert(frames == 1 and WoWTools.Rotation == nil, "Initialization created a login marker")
    local stopped = 0
    WoWTools.modules.wowDetector = {IsEnabled=function() return true end, Hide=function() stopped=stopped+1 end}
    WoWTools.modules.fight_detector = {IsEnabled=function() return false end, IsShown=function() return false end}
    WoWTools.ActivateDetector("fight_detector")
    assert(stopped == 1, "Removing rotation marker broke detector exclusion")
    print("PASS: " .. flavor .. " has no login marker/module/saved request and preserves detector exclusion.")
end
