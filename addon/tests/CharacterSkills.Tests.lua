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
    UIParent={};NUM_BAG_SLOTS=0
    local secret=setmetatable({},{__eq=function() error("Secret compared") end,__tostring=function() error("Secret printed") end})
    function issecretvalue(v) return rawequal(v,secret) end
    function UnitName() return "测试角色" end
    function GetRealmName() return "服务器甲" end
    function UnitLevel() return 80 end
    function time() return 1792200000 end
    C_Container={GetContainerNumSlots=function() return 16 end,GetContainerNumFreeSlots=function() return 12 end}
    C_SkillInfo=nil;GetProfessions=nil;GetProfessionInfo=nil;GetNumSkillLines=nil;GetSkillLineInfo=nil;ExpandSkillHeader=nil;CollapseSkillHeader=nil
    local reads=0
    local rows={
        {name="专业技能",header=true,expanded=false},
        {name="采矿",rank=450,maxRank=450},{name="剥皮",rank=425,maxRank=450},
        {name="生活技能",header=true,expanded=false},
        {name="钓鱼",rank=450,maxRank=450},{name="烹饪",rank=300,maxRank=450},{name="急救",rank=375,maxRank=450},
        {name="武器技能",header=true,expanded=true},{name="剑",rank=400,maxRank=400},
    }
    local function Visible()
        local visible,expanded={},true
        for _,row in ipairs(rows) do
            if row.header then expanded=row.expanded end
            if row.header or expanded then visible[#visible+1]=row end
        end
        return visible
    end
    local learned={
        [186]={name="采矿",rank=450,maxRank=450},[393]={name="剥皮",rank=425,maxRank=450},
        [185]={name="烹饪",rank=300,maxRank=450},[356]={name="钓鱼",rank=450,maxRank=450},
        [129]={name="急救",rank=375,maxRank=450},
    }
    if flavor=="titan" then
        function GetNumSkillLines() reads=reads+1;return #Visible() end
        function GetSkillLineInfo(index)
            reads=reads+1;local row=Visible()[index]
            return row.name,row.header,row.expanded,row.rank,0,0,row.maxRank
        end
        function ExpandSkillHeader(index) local row=Visible()[index];assert(row.header);row.expanded=true end
        function CollapseSkillHeader(index) local row=Visible()[index];assert(row.header);row.expanded=false end
    else
        C_SkillInfo={GetSkillLineInfoByID=function(id) reads=reads+1;assert(id~=129,"First Aid was queried");return learned[id] end}
    end
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    dofile(addon.."Init.lua");dofile(addon.."CharacterRecord.lua")
    local frame=frames[#frames]
    wowToolsCharacterRecord={version=1} -- Prior records remain enrolled after the schema upgrade.
    frame.scripts.OnEvent(frame,"ADDON_LOADED","wow_tools")
    assert(frame.events.PLAYER_LOGOUT and frame.events.SKILL_LINES_CHANGED and reads>0
        and wowToolsCharacterRecord.version==1 and not frame.scripts.OnUpdate,
        "Live skills were not cached, disk record changed early, or polling was added")
    local function Logout()
        -- Each scenario is a new login, so unknown reads cannot borrow another login's cache.
        dofile(addon.."CharacterRecord.lua")
        frame=frames[#frames]
        frame.scripts.OnEvent(frame,"ADDON_LOADED","wow_tools")
        frame.scripts.OnEvent(frame,"PLAYER_LOGOUT")
        return wowToolsCharacterRecord
    end
    local record=Logout()
    assert(record.version==4 and record.professions=="186|采矿|450|450;393|剥皮|425|450","Gathering skills were missed or misclassified")
    assert(record.secondarySkills=="185|烹饪|300|450;356|钓鱼|450|450","Life skills or First Aid exclusion failed")
    assert(not rows[1].expanded and not rows[4].expanded and rows[8].expanded,"Logout altered collapsed skill categories")
    if flavor=="titan" then
        rows[2].name="炼金术";rows[2].rank=0;rows[2].maxRank=75;rows[3].name="裁缝"
        record=Logout();assert(record.professions=="171|炼金术|0|75;197|裁缝|425|450","Production or valid zero rank was lost")
        rows[2].rank=secret;record=Logout();assert(record.professions=="?" and record.secondarySkills~="?","Restricted rank corrupted another skill group")
        assert(not rows[1].expanded and not rows[4].expanded,"Failure left skill categories expanded")
    else
        learned[171]={name="炼金术",rank=100,maxRank=450};learned[333]={name="附魔",rank=200,maxRank=450}
        record=Logout()
        assert(record.professions:find("171|炼金术|100|450",1,true) and record.professions:find("333|附魔|200|450",1,true)
            and record.professions:find("393|剥皮|425|450",1,true),"Learned primary professions were limited to two")
        learned[171]=nil;learned[333]=nil
        learned[186]={name="炼金术",rank=secret,maxRank=450};record=Logout()
        assert(record.professions=="?" and record.secondarySkills~="?","Restricted rank was compared or damaged life skills")
        learned[186]=secret;record=Logout();assert(record.professions=="?","Restricted skill structure was indexed")
        learned[186]=nil;learned[393]=nil;learned[794]={name="考古学",rank=1,maxRank=75};record=Logout()
        assert(record.professions=="" and record.secondarySkills:find("794|考古学|1|75",1,true),"Empty professions or archaeology was missed")
        C_SkillInfo.GetSkillLineInfoByID=function() error("API unavailable") end
        record=Logout();assert(record.professions=="?" and record.secondarySkills=="?","Failed API was reported as unlearned")
    end
    -- Optional profession-index interface: sparse slots and first-aid's sixth slot.
    C_SkillInfo=nil;GetNumSkillLines=nil;GetSkillLineInfo=nil
    GetProfessions=function() return nil,2,nil,4,5,6 end
    GetProfessionInfo=function(index)
        assert(index~=6,"First Aid was collected")
        if index==2 then return "附魔",0,350,450,0,0,333 end
        if index==4 then return "钓鱼",0,10,75,0,0,356 end
        return "烹饪",0,1,75,0,0,185
    end
    record=Logout()
    assert(record.professions=="333|附魔|350|450" and record.secondarySkills=="185|烹饪|1|75;356|钓鱼|10|75","Sparse profession indexes hid production/life skills")
    GetProfessions=function() return nil,nil,nil,nil,nil,nil end
    record=Logout();assert(record.professions=="" and record.secondarySkills=="","Unlearned professions were marked unknown")
    GetProfessions=function() return secret,nil,nil,nil,nil,nil end
    record=Logout();assert(record.professions=="?" and record.secondarySkills=="","Restricted index was compared or printed")
    GetProfessions=nil;record=Logout();assert(record.professions=="?" and record.secondarySkills=="?","Unavailable skill APIs were marked unlearned")
    print("PASS: "..flavor.." logout-only production/gathering/life ranks, First Aid exclusion, collapsed-header restoration, sparse indices, old-record enrollment and unknown/unlearned/restricted values.")
end
