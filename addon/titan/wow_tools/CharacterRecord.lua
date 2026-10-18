-- Per-character SavedVariables prevent concurrent clients from overwriting other roles.
-- No polling: enroll on a successful monitor start, then sample at normal logout.
local events=CreateFrame("Frame")
local monitored=false
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
local function FreeSlots()
    local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local free=C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if type(slots)~="function" or type(free)~="function" then return -1 end
    local backpack=Read(slots,0)
    if not Integer(backpack,1,1000) then return -1 end
    local bags=NUM_BAG_SLOTS or 4
    if not Integer(bags,0,10) then return -1 end
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
            -- General-purpose carried bags only; bank, reagent and specialty bags are excluded.
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
local function CharacterSkills()
    local result={primary={},secondary={}}
    local unknown,seen={},{}
    local function Add(id,name,rank,maximum,group)
        if not Readable(id) or not Readable(name) then unknown[group]=true;return end
        if id==129 then return end -- First Aid is intentionally excluded.
        if not Integer(id,1,100000) then id=type(name)=="string" and skillNames[name] end
        if not id or skillGroups[id]~=group or type(name)~="string" or name=="" or #name>128
            or name:find("[|;{}%c]") or not Integer(rank,0,100000) or not Integer(maximum,1,100000) or rank>maximum then
            unknown[group]=true;return
        end
        if not seen[id] then result[group][#result[group]+1]={id=id,name=name,rank=rank,maximum=maximum};seen[id]=true end
    end
    local byId=C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
    if type(byId)=="function" then
        -- Forever: query learned skill IDs directly, independent of collapsed skill headers.
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
        -- Preserve holes: absent first/second professions must not hide fishing or cooking.
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
    elseif type(GetNumSkillLines)=="function" and type(GetSkillLineInfo)=="function" then
        -- Titan's classic tuple API can omit collapsed categories. Expand only for this logout read,
        -- then restore the exact collapsed categories in reverse order before returning.
        local count=Read(GetNumSkillLines)
        if not Integer(count,0,1000) then return "?","?" end
        local collapsed={}
        for index=1,count do
            local ok,name,header,expanded=pcall(GetSkillLineInfo,index)
            if not ok or not Readable(name) or not Readable(header) or not Readable(expanded) then return "?","?" end
            if header and not expanded then
                if type(name)~="string" then return "?","?" end
                collapsed[name]=true
            end
        end
        if next(collapsed) then
            if type(ExpandSkillHeader)~="function" or type(CollapseSkillHeader)~="function" then return "?","?" end
            if not pcall(ExpandSkillHeader,0) then return "?","?" end
        end
        local ok=pcall(function()
            count=Read(GetNumSkillLines)
            if not Integer(count,0,1000) then error("Skills unavailable") end
            for index=1,count do
                local good,name,header,expanded,rank,temp,modifier,maximum=pcall(GetSkillLineInfo,index)
                if not good or not Readable(name) or not Readable(header) then error("Skills unavailable") end
                local id=type(name)=="string" and skillNames[name]
                if not header and id then Add(id,name,rank,maximum,skillGroups[id]) end
            end
        end)
        if next(collapsed) then
            local restoreCount=Read(GetNumSkillLines)
            if not Integer(restoreCount,0,1000) then return "?","?" end
            for index=restoreCount,1,-1 do
                local good,name,header=pcall(GetSkillLineInfo,index)
                if good and Readable(name) and Readable(header) and header and type(name)=="string" and collapsed[name] then
                    if not pcall(CollapseSkillHeader,index) then ok=false end
                end
            end
        end
        if not ok then return "?","?" end
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
function WoWTools.MarkCharacterMonitored()
    if monitored then return end
    monitored=true
    events:RegisterEvent("PLAYER_LOGOUT")
end
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(_,event,addon)
    if event=="ADDON_LOADED" then
        if addon~="wow_tools" then return end
        events:UnregisterEvent("ADDON_LOADED")
        if type(wowToolsCharacterRecord)=="table" and (wowToolsCharacterRecord.version==1 or wowToolsCharacterRecord.version==2) then WoWTools.MarkCharacterMonitored() end
        return
    end
    if event~="PLAYER_LOGOUT" or not monitored then return end
    local name,realm=Read(UnitName,"player"),Read(GetRealmName)
    local recordedAt=Read(time)
    if type(name)~="string" or name=="" or type(realm)~="string" or realm=="" or not Integer(recordedAt,1,253402300799) then return end
    local level=Read(UnitLevel,"player")
    local professions,secondarySkills=CharacterSkills()
    wowToolsCharacterRecord={version=2,name=name,realm=realm,level=Integer(level,1,1000) and level or 0,
        freeBagSlots=FreeSlots(),recordedAt=recordedAt,professions=professions,secondarySkills=secondarySkills}
end)
