-- UnitClass metadata only; never invokes game input or opens a client.
local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local frames={}
    function CreateFrame()
        local f={events={},scripts={}}
        function f:RegisterEvent(e) self.events[e]=true end
        function f:UnregisterEvent(e) self.events[e]=nil end
        function f:SetScript(e,fn) self.scripts[e]=fn end
        frames[#frames+1]=f;return f
    end
    local secret=setmetatable({},{__eq=function() error("Secret compared") end})
    function issecretvalue(value) return rawequal(value,secret) end
    function UnitName() return "角色甲" end
    function GetRealmName() return "服务器甲" end
    function UnitLevel() return 50 end
    function time() return 1792300000 end
    local token,id,failed="MAGE",8,false
    function UnitClass() if failed then error("Unavailable") end;return "localized",token,id end
    local function Load()
        dofile(root.."/addon/"..flavor.."/wow_tools/CharacterRecord.lua")
        local f=frames[#frames]
        f.scripts.OnEvent(f,"ADDON_LOADED","wow_tools")
        f.scripts.OnEvent(f,"PLAYER_ENTERING_WORLD",true,false)
        return f
    end
    local frame=Load()
    assert(wowToolsCharacterRecord.version==6 and wowToolsCharacterRecord.classId==8,"World-entry snapshot lost class")
    token,id="WARRIOR",1;frame.scripts.OnEvent(frame,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.classId==1,"Logout did not refresh class")
    token,id=secret,secret;frame.scripts.OnEvent(frame,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.classId==1,"Restricted logout class discarded current-login cache")
    failed=true;Load()
    assert(wowToolsCharacterRecord.classId==0,"New login borrowed an old character class")
    failed=false
    local classes={WARRIOR=1,PALADIN=2,HUNTER=3,ROGUE=4,PRIEST=5,SHAMAN=7,MAGE=8,WARLOCK=9,DRUID=11}
    if flavor=="titan" then classes.DEATHKNIGHT=6 end
    for classToken,classID in pairs(classes) do
        token,id=classToken,classID;Load()
        assert(wowToolsCharacterRecord.classId==classID,"Class identity was not preserved")
        id=nil;Load()
        assert(wowToolsCharacterRecord.classId==classID,"Legacy UnitClass tuple did not use the stable token")
    end
    token,id="MAGE",1;Load()
    assert(wowToolsCharacterRecord.classId==0,"Conflicting class token/id accepted")
    token,id="MONK",10;Load()
    assert(wowToolsCharacterRecord.classId==0,"Unsupported class accepted")
    if flavor=="forerver" then
        token,id="DEATHKNIGHT",6;Load()
        assert(wowToolsCharacterRecord.classId==0,"Forever accepted an unavailable class")
    end
    print("PASS: "..flavor.." v6 class sampling on world-entry/logout, token compatibility, restricted/failed values, cache isolation and supported classes; no game actions.")
end
