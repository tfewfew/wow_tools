-- Forever uses its own per-character SavedVariables and namespaced container APIs.
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
            if family==0 then total=total+available end
        end
    end
    return total
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
        if type(wowToolsCharacterRecord)=="table" and wowToolsCharacterRecord.version==1 then WoWTools.MarkCharacterMonitored() end
        return
    end
    if event~="PLAYER_LOGOUT" or not monitored then return end
    local name,realm=Read(UnitName,"player"),Read(GetRealmName)
    local recordedAt=Read(time)
    if type(name)~="string" or name=="" or type(realm)~="string" or realm=="" or not Integer(recordedAt,1,253402300799) then return end
    local level=Read(UnitLevel,"player")
    wowToolsCharacterRecord={version=1,name=name,realm=realm,level=Integer(level,1,1000) and level or 0,
        freeBagSlots=FreeSlots(),recordedAt=recordedAt}
end)
