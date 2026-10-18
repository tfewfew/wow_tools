-- Reproduce the real logout teardown order without input or game processes.
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
    local name,realm,level,free,bind,now="测试角色","服务器甲",80,12,"达拉然",1792297200
    function UnitName() return name end
    function GetRealmName() return realm end
    function UnitLevel() return level end
    function GetBindLocation() return bind end
    function GetMaxLevelForLatestExpansion() return 80 end
    function GetMaxPlayerLevel() return 80 end
    function time() return now end
    C_Container={GetContainerNumSlots=function(bag) return bag==0 and 16 or 0 end,
        GetContainerNumFreeSlots=function() return free,0 end}
    C_SkillInfo={GetSkillLineInfoByID=function(id)
        if id==356 then return {name="钓鱼",rank=300,maxRank=450} end
    end}
    local frame
    local function Event(event,...)
        if frame.events[event] then frame.scripts.OnEvent(frame,event,...) end
    end
    local function Load()
        dofile(root.."/addon/"..flavor.."/wow_tools/Init.lua")
        dofile(root.."/addon/"..flavor.."/wow_tools/CharacterRecord.lua")
        frame=frames[#frames];Event("ADDON_LOADED","wow_tools")
    end
    for _,missing in ipairs({"name","realm","both","restricted"}) do
        name,realm,level,free,bind="测试角色","服务器甲",80,12,"达拉然"
        wowToolsCharacterRecord=nil;Load()
        assert(wowToolsCharacterRecord==nil and frame.events.PLAYER_LOGOUT)
        Event("PLAYER_LEAVING_WORLD")
        if missing=="name" then name=nil elseif missing=="realm" then realm=nil
        elseif missing=="restricted" then name,realm=secret,secret else name,realm=nil,nil end
        level,free,bind=secret,secret,secret
        Event("PLAYER_LOGOUT")
        local record=wowToolsCharacterRecord
        assert(record and record.name=="测试角色" and record.realm=="服务器甲" and record.level==80
            and record.freeBagSlots==12 and record.bindLocation=="达拉然" and record.maxLevel==nil and wowToolsRealmLevels["服务器甲"].maxLevel==80
            and record.secondarySkills=="356|钓鱼|300|450" and record.recordedAt==now,
            "Cleared logout identity discarded the current login's snapshot: "..missing)
    end
    -- No LEAVING_WORLD event is also safe if live identity temporarily disappears.
    name,realm,level,free,bind="测试角色","服务器甲",80,12,"达拉然"
    wowToolsCharacterRecord=nil;Load();name,realm=nil,nil
    Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord and wowToolsCharacterRecord.name=="测试角色")
    -- Never borrow another login's disk identity or fill a known conflicting name.
    local previous={version=4,name="旧角色",realm="旧服务器",level=80}
    wowToolsCharacterRecord=previous;name,realm=nil,nil;Load();Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord==previous,"Old disk identity was borrowed without a live sample")
    name,realm="测试角色","服务器甲";Load();name,realm="其他角色",nil
    Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord==previous,"A conflicting readable name was combined with the cached realm")
    name,realm="测试角色","服务器甲";Load();name,realm=nil,"其他服务器"
    Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord==previous,"A conflicting readable realm was combined with the cached name")
    print("PASS: "..flavor.." logout name/realm clearing and restricted values retain this login's snapshot without detection; missing live identity and conflicting partial identities never borrow old disk data.")
end
