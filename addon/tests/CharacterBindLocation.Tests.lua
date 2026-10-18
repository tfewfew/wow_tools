-- Hearthstone snapshots use native metadata/events only. No game input or polling.
local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local frames={}
    function CreateFrame()
        local frame={events={},scripts={}}
        function frame:SetSize() end
        function frame:SetPoint() end
        function frame:RegisterEvent(event) self.events[event]=true end
        function frame:UnregisterEvent(event) self.events[event]=nil end
        function frame:SetScript(event,fn) self.scripts[event]=fn end
        frames[#frames+1]=frame;return frame
    end
    UIParent={}
    local secret=setmetatable({},{__eq=function() error("Secret compared") end,
        __tostring=function() error("Secret printed") end})
    function issecretvalue(value) return rawequal(value,secret) end
    function UnitName() return "测试角色" end
    function GetRealmName() return "服务器甲" end
    function UnitLevel() return 80 end
    function time() return 1792200000 end
    C_Container={GetContainerNumSlots=function(bag) return bag==0 and 16 or 0 end,
        GetContainerNumFreeSlots=function() return 12,0 end}
    C_SkillInfo,GetProfessions,GetNumSkillLines=nil,nil,nil
    local location,reads,fail="达拉然",0,false
    local function ReadLocation()
        reads=reads+1
        if fail then error("Binding API unavailable") end
        return location
    end
    GetBindLocation=ReadLocation
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    dofile(addon.."Init.lua")
    local frame
    local function Event(event,...)
        if frame.events[event] then frame.scripts.OnEvent(frame,event,...) end
    end
    local function Load()
        dofile(addon.."CharacterRecord.lua");frame=frames[#frames]
        Event("ADDON_LOADED","wow_tools")
    end
    wowToolsCharacterRecord=nil;Load()
    assert(reads==1 and frame.events.HEARTHSTONE_BOUND and not frame.scripts.OnUpdate
        and wowToolsCharacterRecord==nil,"Automatic recording did not sample once, persisted early, or introduced polling")
    Event("BAG_UPDATE_DELAYED");Event("SKILL_LINES_CHANGED");Event("PLAYER_LEVEL_UP",81)
    assert(reads==1,"Unrelated bag/skill events resampled the hearthstone")
    location="狮王之傲旅店";Event("HEARTHSTONE_BOUND")
    assert(reads==2 and wowToolsCharacterRecord==nil,"Rebinding did not update only the live cache")
    location=secret;Event("HEARTHSTONE_BOUND")
    Event("PLAYER_LEAVING_WORLD")
    local before=reads
    location="退出中的无效地点";Event("HEARTHSTONE_BOUND")
    assert(reads==before,"An ordinary rebind event ran while leaving the world")
    location=secret;Event("PLAYER_LOGOUT")
    assert(reads==before+1 and wowToolsCharacterRecord.version==4
        and wowToolsCharacterRecord.bindLocation=="狮王之傲旅店",
        "Logout did not resample binding once, or a restricted read replaced valid cache")
    location="闪金镇";Event("PLAYER_ENTERING_WORLD")
    location="暴风城旅店";Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.bindLocation=="暴风城旅店",
        "Logout did not refresh a changed binding when no event had arrived")
    location=secret;Load();Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.bindLocation=="?","A new login borrowed the old disk binding as fresh data")
    for _,bad in ipairs({"","   ","带\n换行","带{括号}",string.rep("x",257),12,secret}) do
        location=bad;Load();Event("PLAYER_LOGOUT")
        assert(wowToolsCharacterRecord.bindLocation=="?","Invalid binding was stored or compared unsafely")
    end
    fail=true;Load();Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.bindLocation=="?")
    fail=false;GetBindLocation=nil;Load();Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.bindLocation=="?","Missing binding API prevented a valid character snapshot")
    GetBindLocation=ReadLocation;location='Lion\'s Pride "Inn"'
    for _,version in ipairs({1,2,3,4}) do
        wowToolsCharacterRecord={version=version};Load();Event("PLAYER_LOGOUT")
        assert(wowToolsCharacterRecord.version==4 and wowToolsCharacterRecord.bindLocation==location,
            "A legacy or current record prevented automatic recording after the schema upgrade")
    end
    print("PASS: "..flavor.." native hearthstone binding for all characters, rebind/enter events, logout cache/freeze, no stale disk fallback, unknown/restricted/missing APIs and v1-v4 upgrades; no polling or game actions.")
end
