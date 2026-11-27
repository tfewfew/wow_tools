WoWTools.prr.RegisterSource(function(...)
-- gathering.lua -- herb and ore nodes and skinning (database/gathering.lua):
-- the skill to gather a node or skin a beast, its skill-up zones and what one
-- gather gives with its chance.
--
-- Zones of a node or a beast (as the game colors them): orange from the skill
-- it needs, yellow from +25, green from +50, gray from +100.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Gathering = {}
ns.Dataflows.Gathering = Gathering

local HERBALISM = 182
local MINING = 186
local SKINNING = 393
Gathering.HERBALISM, Gathering.MINING, Gathering.SKINNING = HERBALISM, MINING, SKINNING

local YELLOW_FROM = 25
local GREEN_FROM = 50
local GRAY_FROM = 100
local OOZE = "Ooze Covered "

local data = ns.Database.Gathering

-- The skill-up levels from the skill something needs: { skill, yellow, green, gray }
-- in the form of a recipe (SkillRange.Levels / Zone take it).
function Gathering.Levels(skill)
    return { skill = skill, yellow = skill + YELLOW_FROM, green = skill + GREEN_FROM, gray = skill + GRAY_FROM }
end

local nodes = {}                 -- [name] = node, parsed once

-- { name, profession, skill, levels } of a node by its English name, or nil.
function Gathering.Node(name)
    if not name then return nil end
    if nodes[name] then return nodes[name] end
    local row = data.Nodes[name]
    if not row then return nil end
    local node = { name = name, profession = row.profession, skill = row.skill, levels = Gathering.Levels(row.skill) }
    nodes[name] = node
    return node
end

-- The node of a game object id (from its GUID), or nil.
function Gathering.NodeByObject(objectID)
    return Gathering.Node(objectID and data.Objects[objectID])
end

local localNames = nil           -- [name in the game's language] = node name; nil until built

-- The item a node gives most (Wowhead's list of its main variant), or nil.
local function MainItem(nodeName)
    local source = Gathering.WowheadObject(Gathering.MainObject(nodeName))
    return source and source.items[1] and source.items[1].item
end

-- The node of a name as the tooltip shows it: English, or in the game's
-- language -- a herb node is named as the herb it gives (the item it gives most).
function Gathering.NodeByName(name)
    if type(name) ~= "string" then return nil end
    local node = Gathering.Node(name)
    if node then return node end
    if not localNames then
        localNames = {}
        local isComplete = true
        for nodeName in pairs(data.Nodes) do
            local item = MainItem(nodeName)
            local itemName = item and ns.Dataflows.ItemNames.ItemPlainName(item)
            if itemName then
                localNames[itemName] = localNames[itemName] or nodeName
            elseif item then
                isComplete = false
            end
        end
        local namesMissing = not isComplete
        if namesMissing then
            local found = localNames[name]
            localNames = nil     -- asked again: the game is still loading item names
            return Gathering.Node(found)
        end
    end
    return Gathering.Node(localNames[name])
end

-- "Ooze Covered Silver Vein" is a Silver Vein for the levels.
function Gathering.BaseName(name)
    return (name:gsub("^" .. OOZE, ""))
end

-- The skinning skill a beast of a level needs (as the game counts it): 1 up to
-- level 10, then 10 per level up to 20, then 5 per level.
function Gathering.SkinningSkill(level)
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end


-- ---------------------------------------------------------------------------
-- Chances: Wowhead Forever (database/gathering_wowhead.lua) and the
-- character's own loot (ns.db.gatherStats, services/gather_recorder.lua).
-- A source = { n = loots, items = { { item, percent, stacks = { { amount, percent }, ... } } } }.

local wowhead = ns.Database.GatheringWowhead
local wowheadParsed = { Npcs = {}, Objects = {} }

-- "1=49.8/2=50.2" -> { { 1, 49.8 }, { 2, 50.2 } }; "" -- always one
local function ParseStacks(text)
    local stacks = {}
    for amount, percent in (text or ""):gmatch("(%d+)=([%d%.]+)") do
        table.insert(stacks, { tonumber(amount), tonumber(percent) })
    end
    if #stacks == 0 then
        stacks = { { 1, 100 } }
    end
    return stacks
end

local function WowheadSource(tableName, id)
    if not id then return nil end
    local parsed = wowheadParsed[tableName][id]
    if parsed ~= nil then return parsed or nil end
    local entry = wowhead[tableName][id]
    if not entry then
        wowheadParsed[tableName][id] = false
        return nil
    end
    parsed = { n = entry.n, level = entry.level, items = {} }
    for item, percent, stacks in entry.loot:gmatch("(%d+):([%d%.]+):([^;]*)") do
        table.insert(parsed.items, { item = tonumber(item), percent = tonumber(percent), stacks = ParseStacks(stacks) })
    end
    wowheadParsed[tableName][id] = parsed
    return parsed
end

-- What Wowhead has for a beast (npc id) or a node object (object id).
function Gathering.WowheadNpc(npcID) return WowheadSource("Npcs", npcID) end
function Gathering.WowheadObject(objectID) return WowheadSource("Objects", objectID) end

-- An own entry: { n = loots ever, history = { "2318:2,783:1", ... } } -- the last
-- settings.gatheringHistory loots (40..1000), oldest first; the chances are by them.
Gathering.HISTORY_MIN, Gathering.HISTORY_MAX = 40, 1000

local function HistoryLimit()
    local limit = tonumber(ns.db.settings.gatheringHistory) or 100
    return math.max(Gathering.HISTORY_MIN, math.min(Gathering.HISTORY_MAX, limit))
end

local function LootText(loot)
    local parts = {}
    for item, amount in pairs(loot) do
        table.insert(parts, item .. ":" .. amount)
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- An entry of the first format ({ n, items = { [item] = { [amount] = times } } },
-- no order of the loots): its loots one item each.
local function Upgrade(entry)
    if entry.history then return entry end
    entry.history = {}
    for item, amounts in pairs(entry.items or {}) do
        for amount, times in pairs(amounts) do
            for _ = 1, times do
                table.insert(entry.history, item .. ":" .. amount)
            end
        end
    end
    entry.items = nil
    entry.n = math.max(entry.n or 0, #entry.history)
    return entry
end

-- Counts one loot of a beast ("npc", npc id) or a node ("node", node name):
-- loot = { [item id] = amount }.
function Gathering.Record(kind, key, loot)
    local all = ns.db.gatherStats[kind]
    local entry = all[key]
    if not entry then
        entry = { n = 0, history = {} }
        all[key] = entry
    end
    Upgrade(entry)
    entry.n = entry.n + 1
    table.insert(entry.history, LootText(loot))
    while #entry.history > HistoryLimit() do
        table.remove(entry.history, 1)
    end
end

-- The character's own chances of a beast or a node by its last loots, or nil
-- when never looted: { n = loots ever, loots = loots the chances stand on, items }.
function Gathering.OwnSource(kind, key)
    local entry = key and ns.db.gatherStats[kind][key]
    if not entry or (entry.n or 0) == 0 then return nil end
    Upgrade(entry)
    -- the setting may have been lowered: the last of the kept ones
    local first = math.max(1, #entry.history - HistoryLimit() + 1)
    local loots = #entry.history - first + 1
    if loots <= 0 then return nil end
    local byItem = {}
    for index = first, #entry.history do
        local text = entry.history[index]
        for item, amount in text:gmatch("(%d+):(%d+)") do
            item, amount = tonumber(item), tonumber(amount)
            local amounts = byItem[item] or {}
            byItem[item] = amounts
            amounts[amount] = (amounts[amount] or 0) + 1
        end
    end
    local source = { n = entry.n, loots = loots, items = {} }
    for item, amounts in pairs(byItem) do
        local times = 0
        for _, count in pairs(amounts) do times = times + count end
        local stacks = {}
        for amount, count in pairs(amounts) do
            table.insert(stacks, { amount, 100 * count / times })
        end
        table.sort(stacks, function(a, b) return a[1] < b[1] end)
        table.insert(source.items, { item = item, percent = 100 * times / loots, stacks = stacks })
    end
    table.sort(source.items, function(a, b) return a.percent > b.percent end)
    return source
end

local mainObjects = nil          -- [node name] = the object id of its main variant

-- The object id of a node's main variant, for a tooltip that knows the node by
-- its name only: the lowest id Wowhead has a list of -- the node of the world;
-- the later ids are variants such as the herbs of Zul'Gurub (they give
-- Bloodvine, the world's do not), whatever their number of gathers.
function Gathering.MainObject(name)
    if not mainObjects then
        mainObjects = {}
        for objectID, nodeName in pairs(data.Objects) do
            local known = mainObjects[nodeName]
            if wowhead.Objects[objectID] and (not known or objectID < known) then
                mainObjects[nodeName] = objectID
            end
        end
    end
    return mainObjects[name]
end

-- Whether the data knows the npc as one to skin: Wowhead lists its skinning
-- loot, or the character has skinned it (any creature type: the Bloodhounds of
-- Blackrock Depths are demons).
function Gathering.IsSkinnedNpc(npcID)
    if not npcID then return false end
    return Gathering.WowheadNpc(npcID) ~= nil or ns.db.gatherStats.npc[npcID] ~= nil
end

-- Forgets the character's own counts.
function Gathering.ResetOwn()
    ns.db.gatherStats = { npc = {}, node = {} }
end
end)
