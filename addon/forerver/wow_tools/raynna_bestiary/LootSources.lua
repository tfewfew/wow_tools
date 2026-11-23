WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Reference-data queries. Resolves Classic loot pools and bundled metadata.
-- Unknown probabilities remain unknown; this module never substitutes personal loot samples.

local _, Addon = ...
local T = Addon.Text
local monsterDropCache = {}
local monsterSkinningCache = {}
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
local vendorSources = {
    'Efficient Games Forever vendor observations',
    'Efficient Games earlier Forever vendor observations',
    'QuestieDB Forever metadata',
}

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
            result[#result + 1] = { id = id, name = Addon.EntityName('Quest', id, name), starts = starts }
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
        return T('Zone unavailable')
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
    return #zones > 0 and table.concat(zones, ', ') or T('Zone unavailable')
end

-- Reverse lookup: item to monster, skinning, vendor and quest sources
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
                    source = 'cMaNGOS Classic (not verified for Forever)',
                }
            end
        end
        local skinning, skinningLootCache = Addon.SkinningReference, {}
        for npcID, npc in pairs(skinning.creatures) do
            local lootID = npc[1]
            if not skinningLootCache[lootID] then
                skinningLootCache[lootID] = resolveLootTable(skinning.loot[lootID], {}, item, memo)
            end
            local drop = skinningLootCache[lootID][item]
            if drop then
                drops['skinning:' .. npcID] = {
                    kind = 'Skinning',
                    npcID = npcID,
                    name = npc[2],
                    minLevel = npc[3],
                    maxLevel = npc[4],
                    rate = drop.rate and math.min(100, drop.rate * 100),
                    conditional = drop.conditional,
                    quest = drop.quest,
                    source = 'cMaNGOS Classic (not verified for Forever)',
                }
            end
        end
        for npcID, npc in pairs(Addon.ForeverReference or {}) do
            local drop = npc.drops[item]
            if drop then
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
    local name, classID
    if C_Item and C_Item.GetItemInfo then
        local info = { C_Item.GetItemInfo(item) }
        name, classID = info[1], info[12]
    end
    local quest = classID == 12
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
        if drops[id] then
            local current = drops[id]
            local updated = {}
            for key, value in pairs(current) do
                updated[key] = value
            end
            updated.name = Addon.EntityName('Npc', id, get('Npc', id, 'name') or current.name)
            updated.minLevel = get('Npc', id, 'minLevel') or current.minLevel
            updated.maxLevel = get('Npc', id, 'maxLevel') or current.maxLevel
            drops[id] = updated
        elseif not drops['skinning:' .. id] then
            -- Untyped NPC metadata may describe skinning, which already has its own row.
            drops[id] = {
                name = get('Npc', id, 'name') or (T('Creature ') .. id),
                minLevel = get('Npc', id, 'minLevel'),
                maxLevel = get('Npc', id, 'maxLevel'),
                source = 'QuestieDB Forever metadata',
            }
        end
    end
    for _, id in ipairs(get('Item', item, 'questRewards') or {}) do
        drops['quest:' .. id] = {
            kind = 'Quest',
            name = get('Quest', id, 'name') or (T('Quest ') .. id),
            details = 'Quest reward / source metadata',
            source = 'QuestieDB Forever metadata',
        }
    end
    local recipeVendors = Addon.RecipeVendors[item]
    local metadataVendors = get('Item', item, 'vendors') or {}
    local function addVendor(id, reference)
        local areaID = reference and reference[1]
        local area = areaID and areaID > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
        drops['vendor:' .. id] = {
            kind = 'Vendor',
            npcID = id,
            name = get('Npc', id, 'name') or (T('Vendor ') .. id),
            details = area or Addon.MonsterZones(id),
            source = reference and (vendorSources[reference[2]] or 'DungeonsForeverProf Forever vendor reference')
                or 'QuestieDB Forever metadata',
        }
    end
    for _, id in ipairs(metadataVendors) do
        addVendor(id, recipeVendors and recipeVendors[id])
    end
    for id, reference in pairs(recipeVendors or {}) do
        if not drops['vendor:' .. id] then
            addVendor(id, reference)
        end
    end
    if not recipeVendors and classID == nil and #metadataVendors > 0 and C_Item and C_Item.GetItemInfoInstant then
        classID = select(6, C_Item.GetItemInfoInstant(item))
    end
    -- Verified Forever-only reward absent from the Classic reference snapshot.
    if item == 279844 then
        local exists = drops['quest:96984'] ~= nil
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
    for sourceID, drop in pairs(drops) do
        local id = tonumber(tostring(sourceID):match(':(%d+)$')) or tonumber(sourceID)
        drop.name = Addon.EntityName(drop.kind == 'Quest' and 'Quest' or 'Npc', id, drop.name)
        if drop.kind == 'Skinning' then
            drop.minLevel = get('Npc', id, 'minLevel') or drop.minLevel
            drop.maxLevel = get('Npc', id, 'maxLevel') or drop.maxLevel
        end
    end
    return {
        itemID = item,
        quest = quest,
        recipeItem = recipeVendors ~= nil or classID == 9,
        name = name or Addon.LootReference.names[item] or Addon.SkinningReference.names[item] or (T('Item ') .. item),
        drops = drops,
    }
end

-- Build the reverse metadata index lazily, independently in each standalone package.
local foreverItemsByNPC
local function metadata(entity, id, field)
    local api = Addon.ReferenceMetadata and Addon.ReferenceMetadata[entity]
    if api and api.Get then
        local ok, value = pcall(api.Get, id, field)
        if ok then
            return value
        end
    end
end
local function foreverItems(npcID)
    if not foreverItemsByNPC then
        foreverItemsByNPC = {}
        for itemID in pairs(Addon.BundledMetadata and Addon.BundledMetadata.Item or {}) do
            for _, id in ipairs(metadata('Item', itemID, 'npcDrops') or {}) do
                foreverItemsByNPC[id] = foreverItemsByNPC[id] or {}
                foreverItemsByNPC[id][itemID] = true
            end
        end
    end
    return foreverItemsByNPC[npcID] or {}
end

-- Forward lookup: creature to possible items
function Addon.ReferenceMonster(id, name, level)
    local database = Addon.LootReference
    local npc = database and database.creatures[id]
    local skinning = Addon.SkinningReference
    local skinningNPC = skinning.creatures[id]
    local identity = npc or skinningNPC
    local monster = {
        npcID = id,
        name = Addon.EntityName('Npc', id, name or metadata('Npc', id, 'name') or (identity and identity[2]) or T('Unknown creature')),
        minLevel = level or metadata('Npc', id, 'minLevel') or (identity and identity[3]),
        maxLevel = level or metadata('Npc', id, 'maxLevel') or (identity and identity[4]),
        drops = {},
        skinning = {},
    }
    if npc and not monsterDropCache[id] then
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
    for itemID, drop in pairs(monsterDropCache[id] or {}) do
        monster.drops[itemID] = drop
    end
    if skinningNPC and not monsterSkinningCache[id] then
        local drops = resolveLootTable(skinning.loot[skinningNPC[1]], {})
        for item, drop in pairs(drops) do
            drop.link = 'item:' .. item
            drop.name = skinning.names[item]
            drop.kind = 'Skinning'
            drop.source = 'cMaNGOS Classic (not verified for Forever)'
            if drop.rate then
                drop.rate = math.min(100, drop.rate * 100)
            end
        end
        monsterSkinningCache[id] = drops
    end
    for itemID, drop in pairs(monsterSkinningCache[id] or {}) do
        monster.skinning[itemID] = drop
    end
    for itemID in pairs(foreverItems(id)) do
        -- Metadata confirms a source relationship, not a drop percentage.
        if not monster.drops[itemID] and not monster.skinning[itemID] then
            monster.drops[itemID] = {
                link = 'item:' .. itemID,
                name = metadata('Item', itemID, 'name') or database.names[itemID],
                source = 'QuestieDB Forever metadata',
                quest = #Addon.ItemQuests(itemID) > 0,
            }
        end
        monster.mixedReference = true
    end
    local correction = Addon.ForeverReference and Addon.ForeverReference[id]
    if correction then
        for itemID, drop in pairs(correction.drops) do
            monster.drops[itemID] = drop
        end
        monster.name = Addon.EntityName('Npc', id, name or correction.name)
        monster.minLevel = level or correction.minLevel or monster.minLevel
        monster.maxLevel = level or correction.maxLevel or monster.maxLevel
        monster.source = correction.source
        monster.foreverReference = true
    end
    return monster
end

-- Probability labels
function Addon.DropChance(drop, compact)
    if not drop or not drop.rate then
        return T('Chance unknown')
    end
    local rate = drop.rate
    local value = rate > 0 and rate < 0.01 and '<0.01'
        or string.format('%.2f', rate):gsub('0+$', ''):gsub('%.$', '')
    return value .. '%' .. (drop.conditional and (compact and '*' or T(' (conditional)')) or '')
end
end)
