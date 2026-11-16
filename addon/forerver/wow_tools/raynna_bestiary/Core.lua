WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Standalone lifecycle; no tracking events or required addon dependency.
local _, Addon = ...
RaynnaBestiaryAPI = Addon
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
