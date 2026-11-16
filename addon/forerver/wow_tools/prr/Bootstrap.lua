local addon = { sourceVersion = "1.5.2", sources = {} }
WoWTools.prr = addon
WoWTools.modules.prr = addon

function addon.RegisterSource(initialize)
    addon.sources[#addon.sources + 1] = initialize
end

function addon.GetSettings()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.prr) ~= "table" then wowDetectorDB.prr = {} end
    return wowDetectorDB.prr
end

function addon.OpenSettings() WoWTools.settings.Open("prr") end
WoWTools.thirdParty.Register("prr", "配方用途", addon.OpenSettings)
