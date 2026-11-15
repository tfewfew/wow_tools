local Addon = {
    sourceVersion = "1.3.1",
    sourceCommit = "0c5da2aef6b2b56e307a77e37151fe4675be6c82",
}
WoWTools.petXPBar = Addon
WoWTools.modules.pet_xp_bar = Addon

function Addon.GetSettings()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.petXPBar) ~= "table" then wowDetectorDB.petXPBar = {} end
    local settings = wowDetectorDB.petXPBar
    if type(settings.db) ~= "table" then settings.db = {} end
    return settings
end

function Addon.OpenOptions() WoWTools.settings.Open("pet_xp_bar") end
WoWTools.thirdParty.Register("pet_xp_bar", "宠物经验", Addon.OpenOptions)
SLASH_PXP1 = "/pxp"
SlashCmdList.PXP = function(message)
    if Addon.HandleCommand then Addon.HandleCommand(message) else Addon.OpenOptions() end
end

function Addon.RefreshSettings()
    local panel = Addon.settingsPanel
    if not panel or not panel:IsVisible() then return end
    if not Addon.ready then
        panel.message:SetText("宠物经验已停用，可在“三方插件”的插件管理中勾选并重载后启用。")
        panel.message:Show()
        return
    end
    panel.message:Hide()
    if not Addon.optionsPanel then Addon.BuildOptions(panel) end
    Addon.RefreshControls()
end

function Addon.BuildSettings(parent)
    if Addon.settingsPanel then return Addon.settingsPanel end
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    panel.message:SetPoint("TOPLEFT", 16, -16)
    panel.message:SetPoint("RIGHT", -16, 0)
    panel.message:SetJustifyH("LEFT")
    panel:SetScript("OnShow", Addon.RefreshSettings)
    Addon.settingsPanel = panel
    return panel
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= "wow_tools" then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not WoWTools.thirdParty.IsActive("pet_xp_bar") then return end
    Addon.InitializeDB()
    Addon.Initialize()
    Addon.ready = true
    Addon.RefreshSettings()
end)
