local addon = { sourceVersion = "2.4.8", sources = {} }
WoWTools.raynnaBestiary = addon
WoWTools.modules.raynna_bestiary = addon

function addon.RegisterSource(initialize)
    addon.sources[#addon.sources + 1] = initialize
end

function addon.GetSettings()
    if type(wowToolsCharacterSettings) ~= "table" then wowToolsCharacterSettings = {} end
    if type(wowToolsCharacterSettings.raynnaBestiary) ~= "table" then
        wowToolsCharacterSettings.raynnaBestiary = {}
    end
    local settings = wowToolsCharacterSettings.raynnaBestiary
    if type(settings.db) ~= "table" then settings.db = {} end
    return settings.db
end

function addon.OpenSettings() WoWTools.settings.Open("raynna_bestiary") end
WoWTools.thirdParty.Register("raynna_bestiary", "怪物图鉴", addon.OpenSettings)

function addon.SetAppearance(key, value)
    addon.db.appearance[key] = value
    addon.ApplyAppearance()
end

function addon.RefreshSettings()
    local panel = addon.settingsPanel
    if not panel or not panel:IsVisible() then return end
    if not addon.ready then
        panel.message:SetText(WoWTools.thirdParty.IsActive("raynna_bestiary")
            and "模块正在初始化，请稍候。" or "怪物图鉴已停用，可在“三方插件 → 插件列表”中勾选并重载后启用。")
        panel.message:Show()
        return
    end
    panel.message:Hide()
    if not addon.optionsPanel then
        addon.optionsPanel = CreateFrame("Frame", nil, panel)
        addon.optionsPanel:SetAllPoints(panel)
        addon.RefreshOptions = addon.BuildOptions(addon.optionsPanel)
    end
    addon.RefreshOptions()
end

function addon.BuildSettings(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    panel.message:SetPoint("TOPLEFT", 16, -16)
    panel.message:SetPoint("RIGHT", -16, 0)
    panel.message:SetJustifyH("LEFT")
    panel:SetScript("OnShow", addon.RefreshSettings)
    addon.settingsPanel = panel
    return panel
end
