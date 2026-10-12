local root = TEST_ROOT or "."
for _, flavor in ipairs({"titan", "forerver"}) do
    local frame, calls, confirms, hidden, items = nil, {}, {}, {}, {}
    local secret = setmetatable({}, {__eq=function() error("restricted comparison") end,
        __tostring=function() error("restricted output") end})
    function issecretvalue(value) return rawequal(value, secret) end
    function CreateFrame()
        frame = {events={}, scripts={}}
        function frame:RegisterEvent(event) self.events[event]=true end
        function frame:SetScript(event, fn) self.scripts[event]=fn end
        return frame
    end
    local function event(name, slot) frame.scripts.OnEvent(frame, name, slot) end
    local function tick() frame.scripts.OnUpdate(frame, .1) end
    local countFailure, infoFailure, lootFailure, bindFailure = false, false, false, false
    local count=4
    function GetNumLootItems() if countFailure then error("count") end; return count end
    function GetLootSlotInfo(slot)
        if infoFailure then error("info") end
        local item=items[slot] or {}
        return item.icon, nil, nil, nil, nil, item.locked
    end
    function LootSlot(slot)
        calls[#calls+1]=slot
        if lootFailure then error("loot") end
        if slot==1 then event("LOOT_BIND_CONFIRM", slot); event("LOOT_BIND_CONFIRM", slot)
        else items[slot]={}; event("LOOT_SLOT_CLEARED",slot) end
    end
    function ConfirmLootSlot(slot)
        if bindFailure then error("binding") end
        confirms[#confirms+1]=slot
        items[slot]={}; event("LOOT_SLOT_CLEARED",slot)
    end
    function StaticPopup_Hide(which, slot)
        assert(which=="LOOT_BIND" and slot==1, "Hid an unrelated popup")
        hidden[#hidden+1]=slot
    end
    function SetCVar() error("Changed CVar") end
    dofile(root.."/addon/"..flavor.."/wow_tools/Loot.lua")
    assert(frame.events.LOOT_BIND_CONFIRM and frame.events.LOOT_SLOT_CHANGED)
    items={{icon="bind",locked=false},{icon="locked",locked=true},{icon="restricted",locked=secret},{icon="money",locked=0}}
    event("LOOT_OPENED"); assert(#calls==0); tick()
    assert(#calls==2 and calls[1]==1 and calls[2]==4 and #confirms==0, flavor..": bad automatic loot / deferred confirmation")
    tick(); assert(#confirms==1 and #hidden==1, flavor..": binding was not confirmed once")
    event("LOOT_READY"); tick(); assert(#calls==2, "Repeated ready retried pending slots")
    items[2].locked=false; event("LOOT_SLOT_CHANGED",2); tick()
    assert(#calls==3 and calls[3]==2, "Unlocked item not looted")
    event("LOOT_BIND_CONFIRM",secret); event("LOOT_BIND_CONFIRM",nil); event("LOOT_BIND_CONFIRM",0)
    tick(); assert(#confirms==1, "Restricted / invalid confirmation accepted")
    bindFailure=true; event("LOOT_BIND_CONFIRM",1); tick()
    assert(#hidden==1, "Failed confirmation hid manual prompt")
    bindFailure=false; event("LOOT_BIND_CONFIRM",1); event("LOOT_CLOSED"); tick()
    assert(#confirms==1, "Stale binding survived close")
    items={{icon="new",locked=false}}; count=1
    event("LOOT_READY"); tick(); assert(#calls==3, "Closed loot window caused automatic loot")
    event("LOOT_OPENED"); countFailure=true; tick(); assert(#calls==3)
    countFailure=false; count=secret; event("LOOT_READY"); tick(); assert(#calls==3)
    count=1; infoFailure=true; event("LOOT_READY"); tick(); assert(#calls==3)
    infoFailure=false; lootFailure=true; event("LOOT_READY"); tick(); assert(#calls==4)
    tick(); assert(#calls==4, "API failure caused per-frame retry loop")
    lootFailure=false; event("LOOT_SLOT_CHANGED",1); tick(); tick()
    assert(#calls==5 and #confirms==2 and #hidden==2, "New available data did not recover loot")
    event("LOOT_CLOSED"); ConfirmLootSlot=nil; event("LOOT_BIND_CONFIRM",1); tick()
    assert(#hidden==2, "Missing confirmation API hid prompt")
    print("PASS: "..flavor.." loot, locked/restricted/API-failure handling, slot updates, deferred binding deduplication, close cancellation and exact popup. APIs mocked.")
end
