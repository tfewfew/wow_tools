local addon = { sourceVersion = "1.6.0", sources = {} }
WoWTools.prr = addon
WoWTools.modules.prr = addon

function addon.RegisterSource(initialize)
    addon.sources[#addon.sources + 1] = initialize
end

function addon.GetSettings()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.prr) ~= "table" then wowDetectorDB.prr = {} end
    local settings = wowDetectorDB.prr
    if type(settings.db) ~= "table" then settings.db = {} end
    return settings
end

function addon.OpenSettings() WoWTools.settings.Open("prr") end
WoWTools.thirdParty.Register("prr", "配方用途", addon.OpenSettings)
