WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Forever dungeon relationships, independent of Classic probability tables.
local _, A = ...
local bosses, itemSources = {}, {}
for key, dungeon in pairs(A.DungeonReference) do
    for id, boss in pairs(dungeon.bosses) do
        bosses[id] = { name = boss.name, zone = dungeon.name, area = dungeon.area, loot = boss.loot }
        for _, item in ipairs(boss.loot) do
            itemSources[item] = itemSources[item] or {}
            itemSources[item][id] = bosses[id]
        end
    end
    for _, item in ipairs(dungeon.trash) do
        itemSources[item] = itemSources[item] or {}
        itemSources[item]['dungeon:' .. key] = { name = dungeon.name, zone = dungeon.name, trash = true }
    end
end
-- Small factual supplements from Forever-specific sources, never inferred by name.
-- Checked 2026-11-21; remaining NPCs use the bundled/provider data.
local supplements = {
    [250622] = {
        minLevel = 15,
        maxLevel = 16,
        zone = 'Ruins of Lordaeron',
        source = 'Warcraft Wiki / Ragged Ghoul (Ruins of Lordaeron)',
    },
    [250623] = {
        minLevel = 15,
        maxLevel = 16,
        zone = 'Ruins of Lordaeron',
        source = 'Warcraft Wiki / Mangled Cadaver (Ruins of Lordaeron)',
    },
    [250619] = {
        minLevel = 15,
        maxLevel = 16,
        zone = 'Ruins of Lordaeron',
        source = 'Warcraft Wiki / Broodwidow (Ruins of Lordaeron)',
    },
    [250654] = {
        minLevel = 14,
        maxLevel = 15,
        zone = 'Ruins of Lordaeron',
        source = 'Warcraft Wiki / Ghostly Citizen (Ruins of Lordaeron)',
    },
    [256040] = {
        minLevel = 15,
        maxLevel = 16,
        zone = 'Ruins of Lordaeron',
        source = 'Efficient Games / NPC 256040',
    },
    [250625] = { zone = 'Ruins of Lordaeron', source = 'Forever Drop Rate / NPC 250625' },
    [255964] = { zone = 'Ruins of Lordaeron', source = 'Forever Drop Rate / NPC 255964' },
    [255109] = { zone = 'Ruins of Lordaeron', source = 'Forever Drop Rate / NPC 255109' },
    [250656] = { zone = 'Ruins of Lordaeron', source = 'Forever Drop Rate / NPC 250656' },
    [250629] = { zone = 'Ruins of Lordaeron', source = 'Forever Drop Rate / NPC 250629' },
}
local T = A.Text
local oldZones, oldMonster, oldItem = A.MonsterZones, A.ReferenceMonster, A.ReferenceItem
function A.MonsterZones(id)
    local record = supplements[id] or bosses[id]
    return record and T(record.zone) or oldZones(id)
end
local function improve(id, row)
    local extra = supplements[id]
    if extra then
        if not row.minLevel or row.minLevel <= 0 then
            row.minLevel = extra.minLevel
        end
        if not row.maxLevel or row.maxLevel <= 0 then
            row.maxLevel = extra.maxLevel
        end
        row.metadataSource = extra.source
    end
    if row.minLevel and row.minLevel <= 0 then
        row.minLevel = nil
    end
    if row.maxLevel and row.maxLevel <= 0 then
        row.maxLevel = nil
    end
end
function A.ReferenceMonster(id, name, level)
    local result = oldMonster(id, name, level)
    improve(id, result)
    local boss = bosses[id]
    if boss then
        for _, item in ipairs(boss.loot) do
            if not result.drops[item] then
                result.drops[item] = {
                    link = 'item:' .. item,
                    name = A.ReferenceMetadata.Item.Get(item, 'name') or A.LootReference.names[item],
                    source = 'Forever DungeonJournal / NorgannonDB',
                }
            end
        end
        result.mixedReference = true
    end
    return result
end
function A.ReferenceItem(item)
    local result = oldItem(item)
    for id, row in pairs(result.drops) do
        if type(id) == 'number' then
            local copy = {}
            for key, value in pairs(row) do copy[key] = value end
            improve(id, copy)
            result.drops[id] = copy
        end
    end
    for id, entry in pairs(itemSources[item] or {}) do
        local row = result.drops[id]
        if not row then
            row = {
                name = entry.trash and T(entry.name) or A.EntityName('Npc', id, entry.name),
                kind = entry.trash and 'Dungeon trash' or nil,
                details = entry.zone,
                source = 'Forever DungeonJournal / NorgannonDB',
            }
            result.drops[id] = row
        end
    end
    for _, questID in ipairs(A.SuppliedItems[item] or {}) do
        if A.Relation('Quest', questID, 'sourceItemId') == item then
            local questName = A.EntityName('Quest', questID,
                A.Relation('Quest', questID, 'name') or (T('Quest ') .. questID))
            local starters = A.Relation('Quest', questID, 'startedBy') or {}
            for _, npcID in ipairs(starters[1] or {}) do
                result.drops['quest-supply:' .. questID .. ':npc:' .. npcID] = {
                    kind = 'Quest supply', name = questName, npcID = npcID,
                    details = A.MonsterZones(npcID), source = 'QuestieDB Forever metadata',
                }
            end
            for _, objectID in ipairs(starters[2] or {}) do
                result.drops['quest-supply:' .. questID .. ':object:' .. objectID] = {
                    kind = 'Quest supply', name = questName, objectID = objectID,
                    details = A.Relation('Object', objectID, 'name'), source = 'QuestieDB Forever metadata',
                }
            end
            if not next(starters[1] or {}) and not next(starters[2] or {}) then
                result.drops['quest-supply:' .. questID] = {
                    kind = 'Quest supply', name = questName,
                    details = T('Given when accepting this quest'), source = 'QuestieDB Forever metadata',
                }
            end
        end
    end
    for _, objectID in ipairs(A.Relation('Item', item, 'objectDrops') or {}) do
        result.drops['object:' .. objectID] = {
            kind = 'World object', objectID = objectID,
            name = A.Relation('Object', objectID, 'name') or (T('Object ') .. objectID),
            details = T('Chance unknown'), source = 'QuestieDB Forever metadata',
        }
    end
    for _, containerID in ipairs(A.Relation('Item', item, 'itemDrops') or {}) do
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(containerID)
        result.drops['container:' .. containerID] = {
            kind = 'Container', itemID = containerID,
            name = name or A.ReferenceMetadata.Item.Get(containerID, 'name') or (T('Item ') .. containerID),
            details = T('Chance unknown'), source = 'QuestieDB Forever metadata',
        }
    end
    return result
end
end)
