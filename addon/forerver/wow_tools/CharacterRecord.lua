-- Forever uses its own per-character SavedVariables and namespaced container APIs.
-- Sample/publish at world entry and sample/publish again at logout. No polling.
local events=CreateFrame("Frame")
local initialized=false
local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function Read(getter,...)
    if type(getter)~="function" then return nil end
    local ok,value=pcall(getter,...)
    if ok and Readable(value) then return value end
end
local function Integer(value,minimum,maximum)
    return Readable(value) and type(value)=="number" and value>=minimum and value<=maximum and value==math.floor(value)
end
local function MaximumLevel()
    local maximum=Read(GetMaxPlayerLevel)
    if not Integer(maximum,1,1000) then maximum=Read(GetMaxLevelForLatestExpansion) end
    if Integer(maximum,1,1000) then return maximum end
end
local function FreeSlots()
    local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local free=C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if type(slots)~="function" or type(free)~="function" then return -1 end
    local backpack=Read(slots,0)
    if not Integer(backpack,1,1000) then return -1 end
    local bags=4 -- Backpack + ordinary carried bags; never reagent/bank containers.
    local total=0
    for bag=0,bags do
        local count=Read(slots,bag)
        if not Integer(count,0,1000) then return -1 end
        if count>0 then
            local ok,available,family=pcall(free,bag)
            if not ok or not Integer(available,0,count) or not Readable(family) then return -1 end
            -- The API's optional bagFamily may be nil for a general-purpose bag.
            if family==nil then family=0 end
            if not Integer(family,0,2147483647) then return -1 end
            if family==0 then total=total+available end
        end
    end
    return total
end
-- Flat, versioned skill strings keep SavedVariables safe for the external read-only parser.
local skillGroups={
    [171]="primary",[164]="primary",[333]="primary",[202]="primary",[182]="primary",
    [773]="primary",[755]="primary",[165]="primary",[186]="primary",[393]="primary",[197]="primary",
    [185]="secondary",[356]="secondary",[794]="secondary",
}
local skillIds={164,165,171,182,186,197,202,333,393,755,773,185,356,794}
local skillNames={}
for id,names in pairs({
    [171]={"炼金术","鍊金術","Alchemy"},[164]={"锻造","鍛造","Blacksmithing"},
    [333]={"附魔","Enchanting"},[202]={"工程学","工程學","Engineering"},
    [182]={"草药学","草藥學","Herbalism"},[773]={"铭文","銘文","Inscription"},
    [755]={"珠宝加工","珠寶設計","Jewelcrafting"},[165]={"制皮","製皮","Leatherworking"},
    [186]={"采矿","採礦","Mining"},[393]={"剥皮","剝皮","Skinning"},[197]={"裁缝","裁縫","Tailoring"},
    [185]={"烹饪","烹飪","Cooking"},[356]={"钓鱼","釣魚","Fishing"},[794]={"考古学","考古學","Archaeology"},
}) do for _,name in ipairs(names) do skillNames[name]=id end end
local function SkillLineAPI()
    local api=C_SkillInfo
    if api and type(api.GetNumSkillLines)=="function" and type(api.GetSkillLineInfo)=="function" then
        return api.GetNumSkillLines,function(index)
            local info=api.GetSkillLineInfo(index)
            if not Readable(info) or type(info)~="table" then error("Skill row unavailable") end
            if not Readable(info.isHeader) or not Readable(info.isCollapsed) then error("Skill header unavailable") end
            return info.name,info.isHeader,not info.isCollapsed,info.rank,info.tempPoints,info.modifier,info.maxRank,info.skillID
        end,api.ExpandSkillHeader,api.CollapseSkillHeader
    end
    if type(GetNumSkillLines)=="function" and type(GetSkillLineInfo)=="function" then
        return GetNumSkillLines,function(index)
            local name,header,expanded,rank,temp,modifier,maximum=GetSkillLineInfo(index)
            return name,header,expanded,rank,temp,modifier,maximum
        end,ExpandSkillHeader,CollapseSkillHeader
    end
end
local function CharacterSkills()
    local result={primary={},secondary={}}
    local unknown,seen={},{}
    local function Add(id,name,rank,maximum,group)
        if not Readable(id) or not Readable(name) then unknown[group]=true;return end
        if id==129 then return end
        if not Integer(id,1,100000) then id=type(name)=="string" and skillNames[name] end
        if not id or skillGroups[id]~=group or type(name)~="string" or name=="" or #name>128
            or name:find("[|;{}%c]") or not Integer(rank,0,100000) or not Integer(maximum,1,100000) or rank>maximum then
            unknown[group]=true;return
        end
        if not seen[id] then result[group][#result[group]+1]={id=id,name=name,rank=rank,maximum=maximum};seen[id]=true end
    end
    local countLines,readLine,expand,collapse=SkillLineAPI()
    local byId=C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
    if countLines then
        -- Use the client's skill list before optional profession-index stubs.
        local count=Read(countLines)
        if not Integer(count,1,1000) then return "?","?" end
        local collapsed,collapsedIndices={},{}
        for index=1,count do
            local ok,name,header,expanded=pcall(readLine,index)
            if not ok or not Readable(name) or not Readable(header) or not Readable(expanded) then return "?","?" end
            if header and not expanded then
                if type(name)~="string" then return "?","?" end
                collapsed[name]=true
                collapsedIndices[#collapsedIndices+1]=index
            end
        end
        local expansionOK=true
        if next(collapsed) then
            if type(expand)~="function" or type(collapse)~="function" then return "?","?" end
            for index=#collapsedIndices,1,-1 do
                if not pcall(expand,collapsedIndices[index]) then expansionOK=false;break end
            end
        end
        local ok=expansionOK and pcall(function()
            count=Read(countLines)
            if not Integer(count,1,1000) then error("Skills unavailable") end
            for index=1,count do
                local good,name,header,expanded,rank,temp,modifier,maximum,id=pcall(readLine,index)
                if not good or not Readable(name) or not Readable(header) then error("Skills unavailable") end
                local namedID=type(name)=="string" and skillNames[name]
                local knownID=Readable(id) and skillGroups[id] and id or namedID
                if not header and knownID then
                    if not Readable(id) then unknown[skillGroups[knownID]]=true
                    else Add(id or knownID,name,rank,maximum,skillGroups[knownID]) end
                end
            end
        end)
        if next(collapsed) then
            local restoreCount=Read(countLines)
            if not Integer(restoreCount,0,1000) then return "?","?" end
            for index=restoreCount,1,-1 do
                local good,name,header=pcall(readLine,index)
                if good and Readable(name) and Readable(header) and header and type(name)=="string" and collapsed[name] then
                    if not pcall(collapse,index) then ok=false end
                end
            end
        end
        if not ok then return "?","?" end
    elseif type(byId)=="function" then
        for _,id in ipairs(skillIds) do
            local group=skillGroups[id]
            local ok,info=pcall(byId,id)
            if not ok or not Readable(info) then unknown[group]=true
            elseif info~=nil then
                if type(info)~="table" then unknown[group]=true
                else Add(id,info.name,info.rank,info.maxRank,group) end
            end
        end
    elseif type(GetProfessions)=="function" and type(GetProfessionInfo)=="function" then
        local indices={pcall(GetProfessions)}
        if not indices[1] then return "?","?" end
        for index=2,6 do
            local group=index<=3 and "primary" or "secondary"
            local profession=indices[index]
            if not Readable(profession) then unknown[group]=true
            elseif profession~=nil then
                if not Integer(profession,1,10000) then unknown[group]=true
                else
                    local ok,name,icon,rank,maximum,abilities,offset,id=pcall(GetProfessionInfo,profession)
                    if not ok then unknown[group]=true else Add(id,name,rank,maximum,group) end
                end
            end
        end
    else return "?","?" end
    local function Encode(group)
        if unknown[group] then return "?" end
        table.sort(result[group],function(a,b) return a.id<b.id end)
        local parts={}
        for _,skill in ipairs(result[group]) do
            parts[#parts+1]=string.format("%d|%s|%d|%d",skill.id,skill.name,skill.rank,skill.maximum)
        end
        return table.concat(parts,";")
    end
    return Encode("primary"),Encode("secondary")
end
-- Cache only this login's valid live values. Disk records are not used as fresh data.
local cached, sampling, leavingWorld, enteredSnapshotSaved
local function LogoutIdentity()
    local name,realm=Read(UnitName,"player"),Read(GetRealmName)
    local hasName=type(name)=="string" and name~=""
    local hasRealm=type(realm)=="string" and realm~=""
    if hasName and hasRealm then return name,realm end
    -- The player object can be cleared before PLAYER_LOGOUT. Only reuse this
    -- login's sampled identity; a readable conflicting value must never be filled.
    if cached and (not hasName or name==cached.name) and (not hasRealm or realm==cached.realm) then
        return cached.name,cached.realm
    end
end
local function BindLocation()
    local location=Read(GetBindLocation)
    if type(location)=="string" and location:match("%S") and #location<=256
        and not location:find("[{}%c]") and location~="?" then return location end
end
local classIDs={WARRIOR=1,PALADIN=2,HUNTER=3,ROGUE=4,PRIEST=5,SHAMAN=7,MAGE=8,WARLOCK=9,DRUID=11}
local function CharacterClass()
    if type(UnitClass)~="function" then return end
    local ok,_,token,id=pcall(UnitClass,"player")
    if not ok or not Readable(token) or not Readable(id) then return end
    local mapped=type(token)=="string" and classIDs[token]
    if mapped and (id==nil or id==mapped) then return mapped end
end
local function Sample(bags,skills,bind,forLogout)
    if not initialized or sampling then return end
    local name,realm
    if forLogout then name,realm=LogoutIdentity()
    else name,realm=Read(UnitName,"player"),Read(GetRealmName) end
    if type(name)~="string" or name=="" or type(realm)~="string" or realm=="" then return end
    if not cached or cached.name~=name or cached.realm~=realm then
        cached={name=name,realm=realm};enteredSnapshotSaved=false
    end
    sampling=true
    local level=Read(UnitLevel,"player")
    if Integer(level,1,1000) then cached.level=level end
    if bags and skills and bind then
        local classID=CharacterClass()
        if classID then cached.classId=classID end
        local maximum,recordedAt=MaximumLevel(),Read(time)
        if maximum and Integer(recordedAt,1,253402300799) then
            -- Account SavedVariables, keyed by realm, shared by every character.
            wowToolsRealmLevels[realm]={maxLevel=maximum,recordedAt=recordedAt}
        end
    end
    if bind then
        local location=BindLocation()
        if location then cached.bindLocation=location end
    end
    if bags then
        local free=FreeSlots()
        if Integer(free,0,11000) then cached.freeBagSlots=free end
    end
    if skills then
        local ok,primary,secondary=pcall(CharacterSkills)
        -- Empty skill APIs during teardown are ambiguous, unlike a valid new
        -- nonempty reading. Live unlearning events still clear known skills.
        if ok and type(primary)=="string" and primary~="?"
            and (not forLogout or not leavingWorld or primary~="") then cached.professions=primary end
        if ok and type(secondary)=="string" and secondary~="?"
            and (not forLogout or not leavingWorld or secondary~="") then cached.secondarySkills=secondary end
    end
    sampling=false
    return true
end
local function SaveSnapshot()
    local recordedAt=Read(time)
    if not cached or not Integer(recordedAt,1,253402300799) then return false end
    -- SavedVariables are updated in memory here. The client flushes them to disk
    -- on logout/reload; addons cannot force an online disk write.
    wowToolsCharacterRecord={version=6,name=cached.name,realm=cached.realm,classId=cached.classId or 0,
        level=cached.level or 0,freeBagSlots=cached.freeBagSlots or -1,recordedAt=recordedAt,
        professions=cached.professions or "?",secondarySkills=cached.secondarySkills or "?",
        bindLocation=cached.bindLocation or "?"}
    return true
end
local liveEvents={"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","BAG_UPDATE_DELAYED","SKILL_LINES_CHANGED","PLAYER_LEVEL_UP","HEARTHSTONE_BOUND"}
local function StartRecording()
    if initialized then return end
    initialized=true
    if not Readable(wowToolsRealmLevels) or type(wowToolsRealmLevels)~="table" then wowToolsRealmLevels={} end
    events:RegisterEvent("PLAYER_LOGOUT")
    for _,event in ipairs(liveEvents) do events:RegisterEvent(event) end
    Sample(true,true,true)
end
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(_,event,addon)
    if event=="ADDON_LOADED" then
        if addon~="wow_tools" then return end
        events:UnregisterEvent("ADDON_LOADED")
        StartRecording()
        return
    end
    if not initialized then return end
    if event~="PLAYER_LOGOUT" then
        if event=="PLAYER_LEAVING_WORLD" then leavingWorld=true;return end
        if event=="PLAYER_ENTERING_WORLD" then
            leavingWorld=false
            local sampled=Sample(true,true,true)
            if sampled and not enteredSnapshotSaved then enteredSnapshotSaved=SaveSnapshot() end
            return
        end
        if leavingWorld then return end
        if event=="BAG_UPDATE_DELAYED" then Sample(true,false)
        elseif event=="SKILL_LINES_CHANGED" then Sample(false,true)
        elseif event=="HEARTHSTONE_BOUND" then Sample(false,false,true)
        elseif event=="PLAYER_LEVEL_UP" then
            Sample(false,false)
            if cached and Integer(addon,1,1000) then cached.level=addon end
        end
        return
    end
    -- Probe every field again, even after LEAVING_WORLD. Unreadable values retain
    -- only this login's valid samples; readable values refresh the final record.
    if Sample(true,true,true,true) then SaveSnapshot() end
end)
