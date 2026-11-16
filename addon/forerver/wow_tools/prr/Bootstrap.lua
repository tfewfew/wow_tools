local addon = { sourceVersion = "1.5.2", sources = {} }
WoWTools.prr = addon
WoWTools.modules.prr = addon

function addon.RegisterSource(initialize)
    addon.sources[#addon.sources + 1] = initialize
end

function addon.GetSettings()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.prr) ~= "table" then wowDetectorDB.prr = {} end
    local settings = wowDetectorDB.prr
    if type(settings.db) ~= "table" then
        -- The previous session can save its standalone DB after deployment.
        if type(PRRDB) ~= "table" and C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "PRR")
        end
        settings.db = type(PRRDB) == "table" and PRRDB or {}
    end
    return settings
end

function addon.OpenSettings() WoWTools.settings.Open("prr") end
WoWTools.thirdParty.Register("prr", "配方用途", addon.OpenSettings)
