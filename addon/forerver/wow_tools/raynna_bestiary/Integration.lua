local addon = WoWTools.raynnaBestiary
local events = CreateFrame("Frame")
addon.events = events
local needsMigration
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= "wow_tools" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not WoWTools.thirdParty.IsActive("raynna_bestiary") then
            addon.sources = nil
            return
        end
        for _, initialize in ipairs(addon.sources) do initialize("wow_tools", addon) end
        addon.sources = nil
        addon.db = addon.GetSettings()
        needsMigration = next(addon.db) == nil
        self:RegisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if needsMigration then addon.ImportLegacySettings(RaynnaTrackerDB or ForeverHuntDB) end
        addon.db.bestiary = addon.db.bestiary or {}
        addon.db.appearance = addon.db.appearance or {}
        addon.PreloadTrackerPortraits()
        addon.BuildBestiary()
        addon.ready = true
        addon.RefreshSettings()
    end
end)
