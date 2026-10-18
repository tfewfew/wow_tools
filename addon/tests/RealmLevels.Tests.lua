-- One account-wide level cap per realm, never a per-character cap.
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
    local name,realm,now="角色甲","服务器甲",1792300000
    local caps={['服务器甲']=80,['服务器乙']=60}
    function UnitName() return name end
    function GetRealmName() return realm end
    function UnitLevel() return 70 end
    function GetMaxLevelForLatestExpansion() return caps[realm] end
    function GetMaxLevelForPlayerExpansion() error("Player-specific cap API must not be used") end
    GetMaxPlayerLevel=flavor=="forerver" and GetMaxLevelForLatestExpansion or nil
    function time() return now end
    C_Container={GetContainerNumSlots=function(bag) return bag==0 and 16 or 0 end,
        GetContainerNumFreeSlots=function() return 8,0 end}
    C_SkillInfo,GetNumSkillLines,GetProfessions=nil,nil,nil
    wowToolsRealmLevels={['保留服务器']={maxLevel=50,recordedAt=now-60}}
    local frame
    local function Event(event,...)
        if frame.events[event] then frame.scripts.OnEvent(frame,event,...) end
    end
    local function Load()
        dofile(root.."/addon/"..flavor.."/wow_tools/Init.lua")
        dofile(root.."/addon/"..flavor.."/wow_tools/CharacterRecord.lua")
        frame=frames[#frames];Event("ADDON_LOADED","wow_tools");Event("PLAYER_ENTERING_WORLD",true,false)
    end
    wowToolsCharacterRecord={version=4,maxLevel=12};Load()
    assert(wowToolsCharacterRecord.version==6 and wowToolsCharacterRecord.maxLevel==nil
        and wowToolsRealmLevels[realm].maxLevel==80 and wowToolsRealmLevels['保留服务器'].maxLevel==50,
        "Realm cap was not global, or loading one realm erased another")
    local count=0;for _ in pairs(wowToolsCharacterRecord) do count=count+1 end
    assert(count==10,"Character snapshot still carries a server field")
    name="角色乙";now=now+60;Load();Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.name==name and wowToolsCharacterRecord.maxLevel==nil
        and wowToolsRealmLevels[realm].maxLevel==80 and wowToolsRealmLevels[realm].recordedAt==now
        and wowToolsRealmLevels['角色甲']==nil and wowToolsRealmLevels['角色乙']==nil,
        "Characters created separate level-cap records")
    local known=wowToolsRealmLevels[realm]
    caps[realm]=secret;now=now+60;Load();Event("PLAYER_LOGOUT")
    assert(wowToolsRealmLevels[realm]==known,"Unknown cap replaced or refreshed an existing global reading")
    realm="服务器乙";Load();Event("PLAYER_LOGOUT")
    assert(wowToolsRealmLevels[realm].maxLevel==60 and wowToolsRealmLevels['服务器甲'].maxLevel==80,
        "Different realms lost their independent global caps")
    realm="未知服务器";Load();Event("PLAYER_LOGOUT")
    assert(wowToolsRealmLevels[realm]==nil and wowToolsCharacterRecord.maxLevel==nil,
        "Unknown realm was given a guessed or character-specific cap")
    realm="服务器甲";caps[realm]=90;now=now+60;Load()
    assert(wowToolsRealmLevels[realm].maxLevel==90,"A newer API cap did not update the shared realm record")
    local f=assert(io.open(root.."/addon/"..flavor.."/wow_tools/wow_tools.toc","r"))
    local toc=f:read("*a");f:close()
    assert(toc:find("fightDetectorDB, wowToolsRealmLevels",1,true)
        and toc:find("## SavedVariablesPerCharacter: wowToolsCharacterRecord",1,true),
        "Global realm data and per-character data are not separately declared")
    print("PASS: "..flavor.." v5 characters contain no cap; account-wide realm caps survive character/realm switches, reject unknown updates and preserve unrelated realms; no game actions.")
end
