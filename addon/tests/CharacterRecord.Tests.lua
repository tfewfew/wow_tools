-- Normal logout only, with both client API shapes and restricted/failed values.
local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local frames={}
    function CreateFrame()
        local f={events={},scripts={}}
        function f:SetSize() end
        function f:SetPoint() end
        function f:RegisterEvent(event) self.events[event]=true end
        function f:UnregisterEvent(event) self.events[event]=nil end
        function f:SetScript(event,fn) self.scripts[event]=fn end
        frames[#frames+1]=f;return f
    end
    UIParent={}
    local secret=setmetatable({},{__eq=function() error("Secret compared") end,__tostring=function() error("Secret printed") end})
    function issecretvalue(v) return rawequal(v,secret) end
    local reads,level,now,name,realm=0,80,1792200000,"测试角色","服务器甲"
    local missing,restricted=false,false
    local counts={[0]=16,20,18,0,10}
    local spaces={[0]=2,3,8,0,4}
    local families={[0]=0,0,32,0,0}
    function UnitName() reads=reads+1;return name end
    function GetRealmName() reads=reads+1;return realm end
    function UnitLevel() reads=reads+1;return level end
    function time() return now end
    NUM_BAG_SLOTS=4
    local function slots(bag) reads=reads+1;if missing then error("API failed") end;return counts[bag] end
    local function free(bag) reads=reads+1;if restricted then return secret,secret end;return spaces[bag],families[bag] end
    if flavor=="titan" then C_Container=nil;GetContainerNumSlots=slots;GetContainerNumFreeSlots=free
    else C_Container={GetContainerNumSlots=slots,GetContainerNumFreeSlots=free};GetContainerNumSlots=nil;GetContainerNumFreeSlots=nil end
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    local function load()
        dofile(addon.."Init.lua");dofile(addon.."CharacterRecord.lua")
        local f=frames[#frames];f.scripts.OnEvent(f,"ADDON_LOADED","wow_tools");return f
    end
    wowToolsCharacterRecord=nil
    local f=load()
    wowToolsCharacterRecord={previous=true}
    local previous=wowToolsCharacterRecord
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(reads==0 and wowToolsCharacterRecord==previous and not next(f.events) and not f.scripts.OnUpdate,"Inactive role was read or rewritten")
    WoWTools.ActivateDetector("wowDetector")
    assert(f.events.PLAYER_LOGOUT and reads==0,"Start sampled metadata or missed logout subscription")
    level=81;now=now+60
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    local record=wowToolsCharacterRecord
    assert(record.version==2 and record.name==name and record.realm==realm and record.level==81 and record.freeBagSlots==9 and record.recordedAt==now,"Logout did not use latest general-bag/level data")
    assert(record.professions=="?" and record.secondarySkills=="?","Missing skill APIs were mistaken for unlearned skills")
    -- bagFamily is optional: nil on a valid general bag must not discard the entire snapshot.
    families[0]=nil;families[1]=nil
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.freeBagSlots==9,"Optional general-bag family made the logout snapshot unknown")
    f=load();local before=reads
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(reads>before and wowToolsCharacterRecord~=record and wowToolsCharacterRecord.freeBagSlots==9,"Previously monitored role did not refresh its later logout snapshot")
    WoWTools.ActivateDetector("fight_detector")
    for bag=0,4 do spaces[bag]=0 end
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.freeBagSlots==0,"A full backpack was confused with unknown data")
    missing=true;level=secret
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.freeBagSlots==-1 and wowToolsCharacterRecord.level==0,"Failed/restricted reads were not unknown")
    missing=false;restricted=true
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.freeBagSlots==-1,"Restricted container values were compared or counted")
    restricted=false;families[1]=secret
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.freeBagSlots==-1,"Restricted bag family was treated as a missing optional value")
    families[1]=nil;spaces[0]=nil
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.freeBagSlots==-1,"Missing slot count was treated as an empty bag")
    previous=wowToolsCharacterRecord;name=nil
    f.scripts.OnEvent(f,"PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord==previous,"Missing identity overwrote a character record")
    local file=assert(io.open(addon.."wow_tools.toc","r"));local toc=file:read("*a");file:close()
    assert(toc:find("## SavedVariablesPerCharacter: wowToolsCharacterRecord",1,true) and toc:find("CharacterRecord.lua",1,true),"Per-character persistence is absent")
    print("PASS: "..flavor.." monitor use enrolls logout snapshots, previously recorded role refresh, optional bag family, latest level/general bags, full versus unknown, secret/API failure safety and no unmonitored-role reads.")
end
