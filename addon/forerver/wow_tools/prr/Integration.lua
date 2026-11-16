local addon = WoWTools.prr
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= "wow_tools" then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not WoWTools.thirdParty.IsActive("prr") then
        addon.sources = nil
        return
    end
    for _, initialize in ipairs(addon.sources) do initialize("wow_tools", addon) end
    addon.sources = nil
    addon.Core.Init()
    addon.Components.OptionsPanel.Setup()
end)
