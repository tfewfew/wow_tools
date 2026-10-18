-- World-entry publication plus a fresh logout probe. All APIs are substitutes.
local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local frames={}
    function CreateFrame()
        local f={events={},scripts={}}
        function f:SetSize() end;function f:SetPoint() end
        function f:RegisterEvent(event) self.events[event]=true end
        function f:UnregisterEvent(event) self.events[event]=nil end
        function f:SetScript(event,fn) self.scripts[event]=fn end
        frames[#frames+1]=f;return f
    end
    UIParent={}
    local secret=setmetatable({},{__eq=function() error("Secret compared") end})
    function issecretvalue(value) return rawequal(value,secret) end
    local name,realm,level,maximum,free,bind,primary,secondary,now,mode
    local reads={level=0,maximum=0,bags=0,skills=0,bind=0}
    local function Reset()
        name,realm,level,maximum,free="测试角色","服务器甲",70,80,10
        bind,primary,secondary,now,mode="暴风城",100,200,1792300000,"live"
    end
    function UnitName() return name end
    function GetRealmName() return realm end
    function UnitLevel() reads.level=reads.level+1;return level end
    function GetMaxLevelForPlayerExpansion() reads.maximum=reads.maximum+1;return maximum end
    GetMaxPlayerLevel=flavor=="forerver" and GetMaxLevelForPlayerExpansion or nil
    function GetBindLocation() reads.bind=reads.bind+1;return bind end
    function time() return now end
    C_Container={
        GetContainerNumSlots=function(bag) reads.bags=reads.bags+1;if mode=="unknown" then return secret end;return bag==0 and 16 or 0 end,
        GetContainerNumFreeSlots=function() return free,0 end,
    }
    C_SkillInfo={GetSkillLineInfoByID=function(id)
        reads.skills=reads.skills+1
        if mode=="empty" then return nil end
        if mode=="unknown" then return secret end
        if id==186 then return {name="采矿",rank=primary,maxRank=450} end
        if id==356 then return {name="钓鱼",rank=secondary,maxRank=450} end
    end}
    GetNumSkillLines,GetSkillLineInfo,GetProfessions=nil,nil,nil
    local frame
    local function Event(event,...)
        if frame.events[event] then frame.scripts.OnEvent(frame,event,...) end
    end
    local function Load()
        dofile(root.."/addon/"..flavor.."/wow_tools/Init.lua")
        dofile(root.."/addon/"..flavor.."/wow_tools/CharacterRecord.lua")
        frame=frames[#frames];Event("ADDON_LOADED","wow_tools")
    end
    Reset();wowToolsCharacterRecord=nil;Load()
    assert(wowToolsCharacterRecord==nil,"Addon loading published before the world was ready")
    free=9;Event("PLAYER_ENTERING_WORLD",true,false)
    local online=wowToolsCharacterRecord
    assert(online and online.level==70 and online.maxLevel==80 and online.freeBagSlots==9
        and online.professions=="186|采矿|100|450" and online.secondarySkills=="356|钓鱼|200|450"
        and online.bindLocation=="暴风城" and online.recordedAt==now and not frame.scripts.OnUpdate,
        "World entry did not immediately publish current character metadata without detection")
    free=8;Event("PLAYER_LEAVING_WORLD");Event("PLAYER_ENTERING_WORLD",false,false)
    assert(wowToolsCharacterRecord==online,"An instance/world transition repeatedly published the login snapshot")
    -- No change events arrive: logout must probe all fields, including already-known skills.
    level,free,bind,primary,secondary,now=71,0,"达拉然",101,201,now+60
    Event("PLAYER_LEAVING_WORLD")
    local before={};for key,value in pairs(reads) do before[key]=value end
    Event("PLAYER_LOGOUT")
    local offline=wowToolsCharacterRecord
    assert(offline~=online and online.freeBagSlots==9 and offline.level==71 and offline.freeBagSlots==0
        and offline.bindLocation=="达拉然" and offline.professions=="186|采矿|101|450"
        and offline.secondarySkills=="356|钓鱼|201|450" and offline.recordedAt==now,
        "Logout reused the login snapshot instead of refreshing all available fields")
    for key,value in pairs(reads) do assert(value>before[key],"Logout did not re-probe "..key) end

    -- Teardown clears identities, values and skill lists: valid online cache survives.
    Reset();Load();Event("PLAYER_ENTERING_WORLD",true,false)
    Event("PLAYER_LEAVING_WORLD")
    name,realm,level,maximum,bind=nil,nil,secret,secret,secret;mode="empty"
    now=now+60;Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.name=="测试角色" and wowToolsCharacterRecord.level==70
        and wowToolsCharacterRecord.freeBagSlots==10 and wowToolsCharacterRecord.professions=="186|采矿|100|450"
        and wowToolsCharacterRecord.secondarySkills=="356|钓鱼|200|450" and wowToolsCharacterRecord.bindLocation=="暴风城",
        "Cleared logout APIs discarded the current login's valid fields")

    -- Actual live unlearning is known empty data and must remain empty on logout.
    Reset();Load();Event("PLAYER_ENTERING_WORLD",true,false)
    mode="empty";Event("SKILL_LINES_CHANGED");Event("PLAYER_LEAVING_WORLD");Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.professions=="" and wowToolsCharacterRecord.secondarySkills=="",
        "Teardown protection restored skills that were actually unlearned while online")

    -- A new login cannot label the previous disk snapshot as a fresh reading.
    Reset();level,maximum,bind=secret,secret,secret;mode="unknown"
    Load();Event("PLAYER_ENTERING_WORLD",true,false)
    assert(wowToolsCharacterRecord.level==0 and wowToolsCharacterRecord.maxLevel==0
        and wowToolsCharacterRecord.freeBagSlots==-1 and wowToolsCharacterRecord.professions=="?"
        and wowToolsCharacterRecord.secondarySkills=="?" and wowToolsCharacterRecord.bindLocation=="?",
        "World-entry publication borrowed previous-login metadata")
    print("PASS: "..flavor.." one world-entry snapshot, fresh full logout probe after leaving, skill refresh without events, partial/cleared API fallback, genuine unlearning and current-login isolation; no polling, input or forced disk writes.")
end
