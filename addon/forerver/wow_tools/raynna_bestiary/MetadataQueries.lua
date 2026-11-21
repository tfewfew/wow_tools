WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Prefer a newer installed QuestieDB; keep per-field standalone fallbacks.
local _, Addon = ...
local snapshotVersion = Addon.BundledMetadata.sourceVersion or '1.0.13'
local snapshotMajor, snapshotMinor, snapshotPatch = snapshotVersion:match('^(%d+)%.(%d+)%.(%d+)$')
local bundledVersion = { tonumber(snapshotMajor), tonumber(snapshotMinor), tonumber(snapshotPatch) }
local function newerInstalledProvider()
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if not metadata then
        return nil
    end
    local ok, version = pcall(metadata, 'QuestieDB', 'Version')
    if not ok or type(version) ~= 'string' then
        return nil
    end
    local major, minor, patch = version:match('^v?(%d+)%.(%d+)%.(%d+)$')
    if not major then
        return nil
    end
    local parts = { tonumber(major), tonumber(minor), tonumber(patch) }
    local newer = false
    for i = 1, 3 do
        if parts[i] ~= bundledVersion[i] then
            newer = parts[i] > bundledVersion[i]
            break
        end
    end
    if newer and type(LibQuestieDB) == 'table' then
        return LibQuestieDB
    end
end
Addon.ReferenceMetadata = {}
for _, entityName in ipairs({ 'Npc', 'Item', 'Quest' }) do
    local entity = entityName
    Addon.ReferenceMetadata[entity] = {
        Get = function(id, field)
            local provider = newerInstalledProvider()
            local api = provider and provider[entity]
            if api and type(api.Get) == 'function' then
                local ok, value = pcall(api.Get, id, field)
                -- Empty lists and false are intentional corrections, not missing data.
                if ok and value ~= nil then
                    return value
                end
            end
            local data = Addon.BundledMetadata
            local faction = UnitFactionGroup and UnitFactionGroup('player')
            local overlay = faction and data.factions[faction]
            local override = overlay and overlay[entity] and overlay[entity][id]
            if override and override[field] ~= nil then
                return override[field]
            end
            local record = data[entity][id]
            return record and record[field]
        end,
    }
end
function Addon.Relation(entity, id, field)
    if not id then return nil end
    local provider = newerInstalledProvider()
    local api = provider and provider[entity]
    if api and type(api.Get) == 'function' then
        local ok, value = pcall(api.Get, id, field)
        if ok and value ~= nil then return value end
    end
    local records = entity == 'Quest' and Addon.QuestDetails or entity == 'Object' and Addon.Objects or Addon.ExtraItems
    local record = records[id]
    return record and record[field]
end
end)
