local _, addon = ...
addon = addon or {}
addon.sourceVersion = "120105.05"
addon.sourceCommit = "355774b11757b46ed3bb4c784ad7145f03e43871"
WoWTools.lsToasts = addon

function addon.GetSettings()
    wowDetectorDB = wowDetectorDB or {}
    wowDetectorDB.lsToasts = wowDetectorDB.lsToasts or {}
    local settings = wowDetectorDB.lsToasts
    settings.db = settings.db or {}
    for _, profile in pairs(settings.db.profiles or {}) do
        if profile.types and profile.types.loot_items then
            profile.types.loot_item = profile.types.loot_item or profile.types.loot_items
            profile.types.loot_items = nil
        end
        if profile.anchors then
            profile.version = math.max(profile.version or 0, 1130202)
        end
    end
    return settings
end

local function IsShown()
    return WoWTools.settings and WoWTools.settings.IsGroupShown("ls_toasts") or false
end

local function Show()
    if addon.ready and not InCombatLockdown() then
        WoWTools.settings.Open("ls_toasts")
    end
end

WoWTools.modules.ls_toasts = {
    Show = Show,
    Hide = function() WoWTools.settings.HideGroup("ls_toasts") end,
    IsShown = IsShown,
    Toggle = function()
        if IsShown() then WoWTools.settings.HideGroup("ls_toasts") else Show() end
    end,
}
