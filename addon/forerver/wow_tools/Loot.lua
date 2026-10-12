-- Forever 16001: global loot APIs verified against build 1.60.1.70338.
-- Binding confirmation is active while either detector runs; never changes CVars.
local opened, scanPending = false, false
local attempted, confirmations = {}, {}
local frame = CreateFrame("Frame")
local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function DetectionEnabled()
    local modules = WoWTools and WoWTools.modules
    if type(modules) ~= "table" then return false end
    for _, name in ipairs({"wowDetector", "fight_detector"}) do
        local module = modules[name]
        if type(module) == "table" and type(module.IsEnabled) == "function" then
            local ok, enabled = pcall(module.IsEnabled)
            if ok and Readable(enabled) and enabled == true then return true end
        end
    end
    return false
end
local function ValidSlot(value)
    return Readable(value) and type(value) == "number" and value >= 1
        and value <= 1000 and value == math.floor(value)
end
for _, event in ipairs({"LOOT_OPENED", "LOOT_READY", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED",
    "LOOT_BIND_CONFIRM", "LOOT_CLOSED"}) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, slot)
    if event == "LOOT_CLOSED" then
        opened, scanPending, attempted, confirmations = false, false, {}, {}
    elseif event == "LOOT_OPENED" then
        opened, scanPending, attempted = true, true, {}
    elseif event == "LOOT_BIND_CONFIRM" then
        if DetectionEnabled() and ValidSlot(slot) then confirmations[slot] = true end
    elseif event == "LOOT_SLOT_CLEARED" then
        if ValidSlot(slot) then attempted[slot] = true end
        scanPending = opened
    else
        if event == "LOOT_SLOT_CHANGED" and ValidSlot(slot) then attempted[slot] = nil end
        scanPending = opened
    end
end)
frame:SetScript("OnUpdate", function()
    if not scanPending and not next(confirmations) then return end
    -- Defer confirmation until Blizzard's event handler has created the popup.
    local pending = confirmations
    confirmations = {}
    for slot in pairs(pending) do
        if DetectionEnabled() and type(ConfirmLootSlot) == "function" then
            local ok, result = pcall(ConfirmLootSlot, slot)
            if ok and Readable(result) and result ~= false and type(StaticPopup_Hide) == "function" then
                pcall(StaticPopup_Hide, "LOOT_BIND", slot)
            end
        end
    end
    if not opened or not scanPending then return end
    scanPending = false
    if type(GetNumLootItems) ~= "function" or type(GetLootSlotInfo) ~= "function"
        or type(LootSlot) ~= "function" then return end
    local ok, count = pcall(GetNumLootItems)
    if not ok or not Readable(count) or type(count) ~= "number" or count < 0
        or count > 1000 or count ~= math.floor(count) then return end
    for slot = 1, count do
        if not opened then break end
        if not attempted[slot] then
            local infoOK, icon, _, _, _, _, locked = pcall(GetLootSlotInfo, slot)
            if infoOK and Readable(icon) and icon ~= nil and Readable(locked)
                and (locked == false or locked == 0) then
                attempted[slot] = true -- Mark before calling an API that may dispatch more events.
                pcall(LootSlot, slot)
            end
        end
    end
end)
