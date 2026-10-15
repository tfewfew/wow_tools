-- Titan 38002. Known hostile item-range probes, in game yards (not world coordinates).
-- Probe distances cross-checked with WeakAuras/LibRangeCheck-3.0's classic item tables.
local probes = {
    [5]={8149,15826,16308}, [10]={9606,17626,17689}, [15]={4559},
    [20]={1191,4388,10645}, [25]={13289}, [30]={835,1404,2091,4941},
    [35]={1258,18904}, [40]={4945,8348},
}
local range = {Values={5,10,15,20,25,30,35,40}, DefaultDetection=30}
local function Readable(value) return not (issecretvalue and issecretvalue(value)) end

-- Only actual short-range attacks qualify. Auto Attack (6603) has no usable
-- range check on these clients; a 5-yard item probe does not prove melee reach.
local meleeSpells={
    [1]={78,20243}, [2]={35395,85256}, [3]={2973}, [4]={1752,53},
    [5]={}, [6]={49998,49143}, [7]={73899,17364}, [8]={}, [9]={},
    [10]={100780,100784}, [11]={22568,6807}, [12]={162243},
}

local function SpellInfo(id)
    if C_Spell and type(C_Spell.GetSpellInfo)=="function" then
        local ok,info=pcall(C_Spell.GetSpellInfo,id)
        if ok and Readable(info) and type(info)=="table" then
            local name,min,max=info.name,info.minRange,info.maxRange
            if Readable(name) and Readable(min) and Readable(max) then return name,min,max end
        end
    end
    if type(GetSpellInfo)=="function" then
        local ok,name,_,_,_,min,max=pcall(GetSpellInfo,id)
        if ok and Readable(name) and Readable(min) and Readable(max) then return name,min,max end
    end
end

local function Known(id)
    local fn,bank
    if C_SpellBook and type(C_SpellBook.IsSpellKnown)=="function"
        and Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player then
        fn=C_SpellBook.IsSpellKnown
        bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    elseif type(IsPlayerSpell)=="function" then fn=IsPlayerSpell
    elseif type(IsSpellKnown)=="function" then fn=IsSpellKnown end
    if not fn then return false end
    local ok,value=pcall(fn,id,bank)
    return ok and Readable(value) and (value==true or value==1)
end

function range.CheckMelee(unit,classID)
    if unit~="target" then return nil end
    -- This directly asks the client whether its main-hand swing can reach the
    -- selected target. Some clients expose the API but return nil to addons.
    local swing=C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange
    if type(swing)=="function" then
        local kind=Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
        local ok,value=pcall(swing,kind)
        if ok and Readable(value) and type(value)=="boolean" then return value end
    end
    local spellCheck=C_Spell and C_Spell.IsSpellInRange
    local legacy=type(IsSpellInRange)=="function" and IsSpellInRange or nil
    local answer
    for _,id in ipairs(meleeSpells[classID] or {}) do
        local name,min,max=SpellInfo(id)
        if Known(id) and type(name)=="string" and type(min)=="number" and type(max)=="number"
            and min==0 and max>0 and max<=5 then
            local fn=type(spellCheck)=="function" and spellCheck or legacy
            if fn then
                local ok,value=pcall(fn,fn==legacy and name or id,unit)
                if ok and Readable(value) then
                    if value==true or value==1 then
                        if answer==false then return nil end
                        answer=true
                    elseif value==false or value==0 then
                        if answer==true then return nil end
                        answer=false
                    end
                end
            end
        end
    end
    return answer
end
function range.IsSupported(value)
    return Readable(value) and type(value)=="number" and probes[value]~=nil
end
function range.Check(unit, yards)
    if not range.IsSupported(yards) then return nil end
    local fn=C_Item and C_Item.IsItemInRange or IsItemInRange
    if type(fn)~="function" then return nil end
    local answer
    for _,item in ipairs(probes[yards]) do
        local ok,value=pcall(fn,item,unit)
        if ok and Readable(value) then
            if value==true or value==1 then
                if answer==false then return nil end -- Conflicting probes cannot authorize input.
                answer=true
            elseif value==false or value==0 then
                if answer==true then return nil end
                answer=false
            end
        end
    end
    return answer
end
function range.WarmCache()
    local fn=C_Item and C_Item.RequestLoadItemDataByID or GetItemInfo
    if type(fn)~="function" then return end
    for _,items in pairs(probes) do for _,item in ipairs(items) do pcall(fn,item) end end
end
WoWTools.FightRange=range
