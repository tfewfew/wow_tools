WoWTools.prr.RegisterSource(function(...)
-- gather_recorder.lua -- counts what skinning, mining and herbalism give the
-- character (dataflows/gathering.lua, Gathering.Record): every item of a loot
-- window with its amount, by the source of the loot (a creature by its npc id,
-- a node by its name).
--
-- What makes a loot a gather:
--   * a node: its source is a herb or a vein (a game object the data knows) --
--     no cast is needed; an unknown object counts after a mining / herbalism cast;
--   * skinning: a creature's loot after a skinning cast, or the cast right after
--     the loot window (the game may send the loot first), or a creature looted a
--     second time whose loot is all skinning items of that npc.
-- A loot window counts once (LOOT_READY and LOOT_OPENED both come; LOOT_CLOSED
-- ends it), a skinned creature once. settings.recordGathering turns it off.
-- The last events go to ns.db.gatherLog (a few lines, to see in the saved
-- variables why a loot was or was not counted).

local ADDON, ns = ...
ns.Services = ns.Services or {}

local Gathering = ns.Dataflows.Gathering

local GatherRecorder = {}
ns.Services.GatherRecorder = GatherRecorder

local CAST_WAIT_SECONDS = 5      -- the loot window opens this soon after the cast
local LATE_CAST_SECONDS = 3      -- ...or the cast comes this soon after the loot window
local LOG_LINES = 40

-- the spells of the professions (their ranks); a cast is matched by its name too
-- (another rank, another client)
local GATHER_SPELLS = {
    [8613] = "skinning", [8617] = "skinning", [8618] = "skinning", [10768] = "skinning",
    [2575] = "mining", [2576] = "mining", [3564] = "mining", [10248] = "mining",
    [2366] = "herbalism", [2368] = "herbalism", [3570] = "herbalism", [11993] = "herbalism",
}

local kindByName = nil
local pending = nil              -- { kind, time } of the last gathering cast
local isLootCounted = false      -- the open loot window is already counted
local held = nil                 -- { guid, npcID, loot, time }: a creature's loot waiting for a skinning cast
local lootedGuids = {}           -- [creature guid] = true: its loot was seen
local skinnedGuids = {}          -- [creature guid] = true: counted as skinned

local function IsSecret(value)
    return ns.Utilities.IsSecret(value)
end

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    return nil
end

local function Log(text)
    if not ns.db then return end
    local log = ns.db.gatherLog
    if type(log) ~= "table" then
        log = {}
        ns.db.gatherLog = log
    end
    table.insert(log, string.format("%.1f %s", GetTime(), text))
    while #log > LOG_LINES do
        table.remove(log, 1)
    end
end

-- "skinning" | "mining" | "herbalism" for a gathering spell, else nil.
function GatherRecorder.KindOf(spellID)
    if type(spellID) ~= "number" or IsSecret(spellID) then return nil end
    if GATHER_SPELLS[spellID] then return GATHER_SPELLS[spellID] end
    if not kindByName then
        kindByName = {}
        for id, kind in pairs(GATHER_SPELLS) do
            local name = SpellName(id)
            if name then kindByName[name] = kind end
        end
    end
    local name = SpellName(spellID)
    return name and kindByName[name] or nil
end

local function RecordSkin(guid, npcID, loot, why)
    skinnedGuids[guid] = true
    Gathering.Record("npc", npcID, loot)
    Log("skin npc " .. npcID .. " counted (" .. why .. ")")
end

function GatherRecorder.OnCast(spellID)
    local kind = GatherRecorder.KindOf(spellID)
    if not kind then return end
    Log("cast " .. tostring(spellID) .. " " .. tostring(SpellName(spellID)) .. " -> " .. kind)
    -- the loot window came first: the skinning cast right after it
    if kind == "skinning" and held and GetTime() - held.time <= LATE_CAST_SECONDS
        and not skinnedGuids[held.guid] and held.isSkinningLoot and ns.db.settings.recordGathering then
        RecordSkin(held.guid, held.npcID, held.loot, "cast after the loot")
        held = nil
        return
    end
    pending = { kind = kind, time = GetTime() }
    isLootCounted = false
end

-- kind ("Creature" | "GameObject" | ...), id of a loot source GUID.
local function ParseGuid(guid)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return kind, tonumber(id)
end

local function ItemOf(slot)
    local link = GetLootSlotLink(slot)
    if not link or IsSecret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Whether every item of the loot is one the npc gives by skinning (its list).
local function IsSkinningLoot(npcID, loot)
    local source = Gathering.WowheadNpc(npcID)
    if not source then return false end
    local known = {}
    for _, entry in ipairs(source.items) do known[entry.item] = true end
    for item in pairs(loot) do
        if not known[item] then return false end
    end
    return next(loot) ~= nil
end

local function CountNode(id, loot, cast)
    local node = Gathering.NodeByObject(id)
    if node then
        Gathering.Record("node", node.name, loot)
        Log("node " .. node.name .. " (" .. id .. ") counted")
    elseif Gathering.WowheadObject(id) or (cast and cast.kind ~= "skinning") then
        Gathering.Record("node", "object " .. id, loot)
        Log("node object " .. id .. " counted")
    else
        Log("object " .. id .. " not a node: skipped")
    end
end

local function CountCreature(guid, npcID, loot, cast)
    if skinnedGuids[guid] then
        Log("npc " .. npcID .. " already skinned: skipped")
    elseif cast and cast.kind == "skinning" then
        RecordSkin(guid, npcID, loot, "cast")
    elseif lootedGuids[guid] and IsSkinningLoot(npcID, loot) then
        RecordSkin(guid, npcID, loot, "second loot, skinning items")
    else
        -- the corpse's own loot, or the skin before its cast: only skinning items can be the skin
        held = { guid = guid, npcID = npcID, loot = loot, time = GetTime(), isSkinningLoot = IsSkinningLoot(npcID, loot) }
        Log("npc " .. npcID .. " loot held for a skinning cast")
    end
    lootedGuids[guid] = true
end

-- LOOT_READY / LOOT_OPENED: the loot window, counted once.
function GatherRecorder.OnLootOpened()
    if isLootCounted then return end
    isLootCounted = true
    local cast = pending
    pending = nil
    if cast and GetTime() - cast.time > CAST_WAIT_SECONDS then
        cast = nil
    end
    if not ns.db.settings.recordGathering then return end
    local bySource = {}
    local sources = 0
    for slot = 1, GetNumLootItems() do
        local item = ItemOf(slot)
        local _, _, amount = GetLootSlotInfo(slot)
        local guid = GetLootSourceInfo and ns.Utilities.Open(GetLootSourceInfo(slot))
        if item and guid then
            local loot = bySource[guid]
            if not loot then
                loot = {}
                bySource[guid] = loot
                sources = sources + 1
            end
            loot[item] = (loot[item] or 0) + (tonumber(ns.Utilities.Open(amount)) or 1)
        end
    end
    Log("loot: " .. GetNumLootItems() .. " slots, " .. sources .. " sources, cast " .. (cast and cast.kind or "none"))
    for guid, loot in pairs(bySource) do
        local kind, id = ParseGuid(guid)
        if kind == "GameObject" and id then
            CountNode(id, loot, cast)
        elseif (kind == "Creature" or kind == "Vehicle") and id then
            CountCreature(guid, id, loot, cast)
        end
    end
end

-- LOOT_CLOSED: the next loot window is a new one.
function GatherRecorder.OnLootClosed()
    isLootCounted = false
end
end)
