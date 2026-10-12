-- Forever 16001. Known hostile item-range probes, in game yards (not world coordinates).
-- Probe distances cross-checked with WeakAuras/LibRangeCheck-3.0's Forever item tables.
local probes = {
    [5]={8149,15826,16308}, [10]={9606,17626,17689}, [15]={4559},
    [20]={1191,4388,10645}, [25]={13289}, [30]={835,1404,2091,4941},
    [35]={1258,18904}, [40]={4945,8348},
}
local range = {Values={5,10,15,20,25,30,35,40}, DefaultDetection=30, DefaultAttack=5}
local function Readable(value) return not (issecretvalue and issecretvalue(value)) end
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
