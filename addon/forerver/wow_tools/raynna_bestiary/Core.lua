WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Standalone lifecycle; no tracking events or required addon dependency.
local _, Addon = ...
RaynnaBestiaryAPI = Addon
local function copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local result = {}
    for key, entry in pairs(value) do
        result[key] = copy(entry)
    end
    return result
end
function Addon.ImportLegacySettings(old)
    if type(old) ~= 'table' then return end
    for _, key in ipairs({ 'bestiary', 'appearance', 'recentPortraitNPCs' }) do
        Addon.db[key] = copy(old[key])
    end
end
function Addon.LevelText(row)
    if not row.minLevel then
        return '?'
    end
    if not row.maxLevel or row.minLevel == row.maxLevel then
        return tostring(row.minLevel)
    end
    return row.minLevel .. '-' .. row.maxLevel
end
function Addon.HideDrops()
    local frame = _G.RaynnaTrackerDrops
    if frame then
        frame:Hide()
    end
end
end)
