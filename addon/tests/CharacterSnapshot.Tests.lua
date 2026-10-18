-- Real API shapes + teardown simulation: no game input or SavedVariables execution.
local root=TEST_ROOT or "."
for _,flavor in ipairs({"titan","forerver"}) do
    local frames={}
    function CreateFrame()
        local f={scripts={},events={}}
        function f:SetSize() end
        function f:SetPoint() end
        function f:SetScript(event,fn) self.scripts[event]=fn end
        function f:RegisterEvent(event) self.events[event]=true end
        function f:UnregisterEvent(event) self.events[event]=nil end
        frames[#frames+1]=f;return f
    end
    UIParent={}
    local reads,leaving,rank,free,level,now=0,false,450,11,80,1792200000
    local failExpand
    local secret=setmetatable({},{__eq=function() error("Secret compared") end,__tostring=function() error("Secret printed") end})
    function issecretvalue(value) return rawequal(value,secret) end
    function UnitName() reads=reads+1;return "测试角色" end
    function GetRealmName() return "服务器甲" end
    function UnitLevel() return leaving and secret or level end
    function time() return now end
    NUM_BAG_SLOTS=10 -- Must never enumerate reagent or bank bags.
    C_Container={
        GetContainerNumSlots=function(bag)
            reads=reads+1;assert(bag<=4,"Reagent or bank bag queried")
            if leaving then return 0 end
            return bag==0 and 20 or 0
        end,
        GetContainerNumFreeSlots=function(bag) assert(bag==0 and not leaving);return free,nil end,
    }
    GetContainerNumSlots,GetContainerNumFreeSlots=nil,nil
    local rows={
        {name="专业技能",header=true,expanded=false},
        {name="采矿",id=186},{name="剥皮",id=393},
        {name="生活技能",header=true,expanded=false},
        {name="钓鱼",id=356},{name="烹饪",id=185},{name="急救",id=129},
    }
    local learned=true
    local function Visible()
        reads=reads+1
        if leaving then return {} end
        local visible,expanded={},false
        for _,row in ipairs(rows) do
            if row.header then expanded=row.expanded end
            if row.header or (expanded and learned) then visible[#visible+1]=row end
        end
        return visible
    end
    local frame
    local function Event(event,...)
        if frame and frame.events[event] then frame.scripts.OnEvent(frame,event,...) end
    end
    local function Count() return #Visible() end
    local function Expand(index)
        if failExpand and index==1 then error("Cannot expand this header") end
        local row=Visible()[index];assert(row and row.header and index>0)
        row.expanded=true
        Event("SKILL_LINES_CHANGED") -- Native folding events may be synchronous.
    end
    local function Collapse(index)
        local row=Visible()[index];assert(row and row.header)
        row.expanded=false
        Event("SKILL_LINES_CHANGED")
    end
    -- Available legacy stubs returning no professions must not hide real learned skill rows.
    GetProfessions=function() return nil,nil,nil,nil,nil,nil end
    GetProfessionInfo=function() error("The profession-index stub should not be used") end
    if flavor=="titan" then
        C_SkillInfo=nil
        GetNumSkillLines=Count
        GetSkillLineInfo=function(index)
            local row=Visible()[index]
            return row.name,row.header,row.expanded,row.header and 0 or rank,0,0,row.header and 0 or 450
        end
        ExpandSkillHeader,CollapseSkillHeader=Expand,Collapse
    else
        GetNumSkillLines,GetSkillLineInfo,ExpandSkillHeader,CollapseSkillHeader=nil,nil,nil,nil
        C_SkillInfo={
            GetNumSkillLines=Count,ExpandSkillHeader=Expand,CollapseSkillHeader=Collapse,
            GetSkillLineInfo=function(index)
                local row=Visible()[index]
                return {name=row.name,skillID=row.id,isHeader=row.header or false,isCollapsed=not row.expanded,
                    rank=row.header and 0 or rank,maxRank=row.header and 0 or 450}
            end,
            GetSkillLineInfoByID=function() return nil end, -- Full enumeration is authoritative.
        }
    end
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    dofile(addon.."Init.lua")
    dofile(addon.."CharacterRecord.lua")
    frame=frames[#frames]
    wowToolsCharacterRecord=nil
    Event("ADDON_LOADED","wow_tools")
    Event("BAG_UPDATE_DELAYED");Event("SKILL_LINES_CHANGED")
    assert(reads>0 and not frame.scripts.OnUpdate,"Character cache still requires detector enrollment or polls")
    assert(reads>0 and wowToolsCharacterRecord==nil and not rows[1].expanded and not rows[4].expanded,
        "Live capture did not restore UI folding or wrote disk data early")
    free,rank,level=0,449,81
    Event("BAG_UPDATE_DELAYED");Event("SKILL_LINES_CHANGED");Event("PLAYER_LEVEL_UP",81)
    leaving=true;now=now+60
    Event("PLAYER_LEAVING_WORLD")
    Event("BAG_UPDATE_DELAYED");Event("SKILL_LINES_CHANGED") -- Data is being cleared after leaving.
    Event("PLAYER_LOGOUT")
    local record=wowToolsCharacterRecord
    assert(record.freeBagSlots==0 and record.level==81 and record.recordedAt==now,
        "Logout teardown replaced cached zero free slots/level")
    assert(record.professions=="186|采矿|449|450;393|剥皮|449|450"
        and record.secondarySkills=="185|烹饪|449|450;356|钓鱼|449|450",
        "Logout empty/stub APIs discarded live skills or included First Aid")
    leaving=false;Event("PLAYER_ENTERING_WORLD");failExpand=true
    Event("SKILL_LINES_CHANGED")
    assert(not rows[1].expanded and not rows[4].expanded,"Partial expand failure changed the user's folded headers")
    failExpand=false
    -- A genuine skill removal while logged in clears the cache; it is not frozen forever.
    leaving=false;learned=false
    Event("SKILL_LINES_CHANGED")
    leaving=true;Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.professions=="" and wowToolsCharacterRecord.secondarySkills=="",
        "Unlearned skills did not clear the current login cache")
    -- A new login with no readable live data must not re-label previous disk values as current.
    wowToolsCharacterRecord={version=2,name="测试角色",realm="服务器甲",level=80,freeBagSlots=99,
        professions="186|采矿|450|450",secondarySkills="356|钓鱼|450|450"}
    if flavor=="forerver" then C_SkillInfo.GetNumSkillLines=function() error("Not loaded") end
    else GetNumSkillLines=function() error("Not loaded") end end
    dofile(addon.."CharacterRecord.lua")
    frame=frames[#frames]
    Event("ADDON_LOADED","wow_tools");Event("PLAYER_LOGOUT")
    assert(wowToolsCharacterRecord.freeBagSlots==-1 and wowToolsCharacterRecord.level==0
        and wowToolsCharacterRecord.professions=="?" and wowToolsCharacterRecord.secondarySkills=="?",
        "Previous-login disk data was misrepresented as a fresh sample")
    print("PASS: "..flavor.." live bag/skill events, real client skill-list shape, empty profession stubs, synchronous fold events, teardown fallback, zero, unlearning and current-login cache isolation.")
end
