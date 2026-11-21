WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Standalone lifecycle; no tracking events or required addon dependency.
local _, Addon = ...
RaynnaBestiaryAPI = Addon
function Addon.IsReadableValue(value)
    return not issecretvalue or not issecretvalue(value)
end
function Addon.LevelText(row)
    if type(row.minLevel) ~= 'number' or row.minLevel <= 0 then
        return '?'
    end
    if not row.maxLevel or row.maxLevel <= row.minLevel then
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
