WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Reference-data queries. Resolves Classic loot pools and bundled metadata.
-- Unknown probabilities remain unknown; this module never substitutes personal loot samples.

local _, Addon = ...
local monsterDropCache = {}
-- Resolve source tables without treating reference-pool chances as item chances.

-- Loot-pool probability resolution
local function resolveLootTable(records, trail, onlyItem, memo)
    local result, groups = {}, {}
    for _, lootRow in ipairs(records or {}) do
        if lootRow[3] > 0 then
            local group = groups[lootRow[3]] or { sum = 0, zeros = 0, uncertain = false }
            groups[lootRow[3]] = group
            group.sum = group.sum + math.abs(lootRow[2])
            if lootRow[2] == 0 then
                group.zeros = group.zeros + 1
            end
            if lootRow[6] ~= 0 or lootRow[2] < 0 then
                group.uncertain = true
            end
        end
    end
    local function add(id, rate, conditional, quest)
        if onlyItem and id ~= onlyItem then
            return
        end
        if result[id] then
            -- Multiple paths may be correlated: don't invent an aggregate rate.
            result[id].rate = nil
            result[id].conditional = result[id].conditional or conditional
            result[id].quest = result[id].quest or quest
        else
            result[id] = { rate = rate, conditional = conditional, quest = quest }
        end
    end
    for _, lootRow in ipairs(records or {}) do
        local rate = math.abs(lootRow[2]) / 100
        local conditional = lootRow[2] < 0 or lootRow[6] ~= 0
        if lootRow[3] > 0 then
            local group = groups[lootRow[3]]
            if group.uncertain or group.sum > 100 then
                rate = nil
            elseif lootRow[2] == 0 then
                rate = math.max(0, 1 - group.sum / 100) / math.max(1, group.zeros)
            end
        elseif lootRow[2] == 0 then
            rate = nil
        end
        if lootRow[4] > 0 then
            add(lootRow[1], rate, conditional, lootRow[2] < 0)
        elseif lootRow[4] < 0 and not trail[-lootRow[4]] then
            local ref = -lootRow[4]
            trail[ref] = true
            local resolved = memo and memo[ref]
                or resolveLootTable(Addon.LootReference.refs[ref], trail, onlyItem, memo)
            if memo then
                memo[ref] = resolved
            end
            for id, drop in pairs(resolved) do
                local combinedChance = rate and drop.rate and rate * drop.rate or nil
                -- Repeat rolls have duplicate-item reroll rules; no false precision.
                if lootRow[5] ~= 1 then
                    combinedChance = nil
                end
                add(id, combinedChance, conditional or drop.conditional, lootRow[2] < 0 or drop.quest)
            end
            trail[ref] = nil
        end
    end
    return result
end
local itemDropCache = {}

-- Bundled quest and location metadata
function Addon.ItemQuests(itemID)
    local referenceDatabase = Addon.ReferenceMetadata
    local result, seen = {}, {}
    if
        not referenceDatabase
        or not referenceDatabase.Item
        or not referenceDatabase.Item.Get
        or not referenceDatabase.Quest
        or not referenceDatabase.Quest.Get
    then
        return result
    end
    local function add(id, starts)
        if type(id) ~= 'number' or id <= 0 or seen[id] then
            return
        end
        local ok, name = pcall(referenceDatabase.Quest.Get, id, 'name')
        if ok and type(name) == 'string' and name ~= '' then
            seen[id] = true
            result[#result + 1] = { id = id, name = name, starts = starts }
        end
    end
    local ok, ids = pcall(referenceDatabase.Item.Get, itemID, 'relatedQuests')
    if ok and type(ids) == 'table' then
        for _, id in ipairs(ids) do
            add(id, false)
        end
    end
    local found, start = pcall(referenceDatabase.Item.Get, itemID, 'startQuest')
    if found then
        add(start, true)
    end
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    return result
end
function Addon.MonsterZones(npcID)
    local referenceDatabase = Addon.ReferenceMetadata
    if not referenceDatabase or not referenceDatabase.Npc or not referenceDatabase.Npc.Get then
        return 'Zone unavailable'
    end
    local ok, spawns = pcall(referenceDatabase.Npc.Get, npcID, 'spawns')
    local zones, seen = {}, {}
    local function add(id)
        if type(id) ~= 'number' or id <= 0 or seen[id] then
            return
        end
        local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
        if name then
            seen[id] = true
            zones[#zones + 1] = name
        end
    end
    if ok and type(spawns) == 'table' then
        for id in pairs(spawns) do
            add(id)
        end
    end
    if #zones == 0 then
        local found, zone = pcall(referenceDatabase.Npc.Get, npcID, 'zoneID')
        if found then
            add(zone)
        end
    end
    table.sort(zones)
    return #zones > 0 and table.concat(zones, ', ') or 'Zone unavailable'
end

-- Reverse lookup: item to monster, vendor and quest sources
function Addon.ReferenceItem(item)
    if not itemDropCache[item] then
        local drops, lootCache, memo = {}, {}, {}
        for npcID, npc in pairs(Addon.LootReference.creatures) do
            local lootID = npc[1]
            if not lootCache[lootID] then
                lootCache[lootID] = resolveLootTable(Addon.LootReference.loot[lootID], {}, item, memo)
            end
            local drop = lootCache[lootID][item]
            if drop then
                drops[npcID] = {
                    name = npc[2],
                    minLevel = npc[3],
                    maxLevel = npc[4],
                    rate = drop.rate and math.min(100, drop.rate * 100),
                    conditional = drop.conditional,
                    quest = drop.quest,
                }
            end
        end
        for npcID, npc in pairs(Addon.ForeverReference or {}) do
            local drop = npc.drops[item]
            if drop and not drops[npcID] then
                drops[npcID] = {
                    name = npc.name,
                    minLevel = npc.minLevel,
                    maxLevel = npc.maxLevel,
                    rate = drop.rate,
                    quest = drop.quest,
                    conditional = drop.conditional,
                    source = npc.source,
                    url = npc.url,
                }
            end
        end
        itemDropCache[item] = drops
    end
    local name, quest
    if C_Item and C_Item.GetItemInfo then
        local info = { C_Item.GetItemInfo(item) }
        name, quest = info[1], info[12] == 12
    end
    for _, drop in pairs(itemDropCache[item]) do
        if drop.quest then
            quest = true
            break
        end
    end
    local drops = {}
    for id, drop in pairs(itemDropCache[item]) do
        drops[id] = drop
    end
    local referenceDatabase = Addon.ReferenceMetadata
    local function get(entity, id, field)
        if not referenceDatabase or not referenceDatabase[entity] or not referenceDatabase[entity].Get then
            return nil
        end
        local ok, value = pcall(referenceDatabase[entity].Get, id, field)
        if ok then
            return value
        end
    end
    for _, id in ipairs(get('Item', item, 'npcDrops') or {}) do
        if not drops[id] then
            drops[id] = {
                name = get('Npc', id, 'name') or ('Creature ' .. id),
                minLevel = get('Npc', id, 'minLevel'),
                maxLevel = get('Npc', id, 'maxLevel'),
                source = 'Source metadata',
            }
        end
    end
    for _, id in ipairs(get('Item', item, 'questRewards') or {}) do
        drops['quest:' .. id] = {
            kind = 'Quest',
            name = get('Quest', id, 'name') or ('Quest ' .. id),
            details = 'Quest reward / source metadata',
            source = 'Source metadata',
        }
    end
    for _, id in ipairs(get('Item', item, 'vendors') or {}) do
        drops['vendor:' .. id] = {
            kind = 'Vendor',
            name = get('Npc', id, 'name') or ('Vendor ' .. id),
            details = Addon.MonsterZones(id),
            source = 'Source metadata',
        }
    end
    -- Verified Forever-only reward absent from the Classic reference snapshot.
    if item == 279844 then
        local exists = false
        for _, drop in pairs(drops) do
            if drop.kind == 'Quest' and drop.name == 'Heart of Disruption' then
                exists = true
            end
        end
        if not exists then
            drops['quest:96984'] = {
                kind = 'Quest',
                name = 'Heart of Disruption',
                details = 'Lv 33 / City of Dalaran / Horde',
                source = 'Wowhead Forever',
                url = 'https://www.wowhead.com/forever/item=279844/striking-staff',
            }
        end
        name = name or 'Striking Staff'
    end
    return {
        itemID = item,
        quest = quest,
        name = name or Addon.LootReference.names[item] or ('Item ' .. item),
        drops = drops,
    }
end

-- Forward lookup: creature to possible items
function Addon.ReferenceMonster(id, name, level)
    local database = Addon.LootReference
    local npc = database and database.creatures[id]
    local monster = {
        npcID = id,
        name = name or (npc and npc[2]) or 'Unknown creature',
        minLevel = level or (npc and npc[3]),
        maxLevel = level or (npc and npc[4]),
        drops = {},
    }
    if not npc then
        local fallback = Addon.ForeverReference and Addon.ForeverReference[id]
        if fallback then
            monster.name = name or fallback.name
            monster.minLevel = level or fallback.minLevel
            monster.maxLevel = level or fallback.maxLevel
            monster.drops = fallback.drops
            monster.source = fallback.source
            monster.foreverReference = true
        end
        return monster
    end
    if not monsterDropCache[id] then
        local drops = resolveLootTable(database.loot[npc[1]], {})
        for item, drop in pairs(drops) do
            drop.link = 'item:' .. item
            drop.name = database.names[item]
            drop.source = 'cMaNGOS Classic'
            if drop.rate then
                drop.rate = math.min(100, drop.rate * 100)
            end
        end
        monsterDropCache[id] = drops
    end
    monster.drops = monsterDropCache[id]
    return monster
end

-- Probability labels
function Addon.DropChance(drop)
    if not drop or not drop.rate then
        return 'Chance unknown'
    end
    local rate = drop.rate
    local value = rate > 0 and rate < 0.01 and '<0.01'
        or string.format('%.2f', rate):gsub('0+$', ''):gsub('%.$', '')
    return value .. '%' .. (drop.conditional and ' (conditional)' or '')
end
end)
