local vendor = {
    sourceVersion = "1.3.1",
    sourceFileID = 9436965,
    sourceSHA256 = "62f2299e80ceadb4f920718ab3395af5b13833417d902ca13b6565f5375132b7",
}
WoWTools.betterVendorUI = vendor
WoWTools.modules.better_vendor_ui = vendor

function vendor.GetSettings()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.betterVendorUI) ~= "table" then wowDetectorDB.betterVendorUI = {} end
    local settings = wowDetectorDB.betterVendorUI
    if type(settings.db) ~= "table" then settings.db = {} end
    return settings
end

function vendor.OpenSettings() WoWTools.settings.Open("better_vendor_ui") end
function vendor.Show() vendor.OpenSettings() end
function vendor.Hide() WoWTools.settings.HideGroup("better_vendor_ui") end
function vendor.IsShown() return WoWTools.settings.IsGroupShown("better_vendor_ui") end
function vendor.Toggle() WoWTools.settings.Toggle("better_vendor_ui") end
WoWTools.thirdParty.Register("better_vendor_ui", "商人增强", vendor.Show)
SLASH_BETTERVENDOR1 = "/bvu"
SlashCmdList.BETTERVENDOR = vendor.Show

function vendor.RefreshSettings()
    local panel = vendor.settingsPanel
    if not panel or not panel:IsVisible() then return end
    local active = WoWTools.thirdParty.IsActive("better_vendor_ui")
    if not active or not vendor.ready then
        panel.message:SetText(active and "模块正在初始化，请稍候。" or "商人增强已停用，可在“三方插件”中勾选并重载后启用。")
        panel.message:Show()
        return
    end
    panel.message:Hide()
    if not vendor.optionsPanel then vendor.BuildOptions(panel) end
    vendor.optionsPanel:Show()
    vendor.RefreshOptions()
end

function vendor.BuildSettings(parent)
    if vendor.settingsPanel then return vendor.settingsPanel end
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    panel.message:SetPoint("TOPLEFT", 16, -16)
    panel.message:SetPoint("RIGHT", -16, 0)
    panel.message:SetJustifyH("LEFT")
    panel:SetScript("OnShow", vendor.RefreshSettings)
    vendor.settingsPanel = panel
    return panel
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= "wow_tools" then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not WoWTools.thirdParty.IsActive("better_vendor_ui") then return end
    local db = vendor.GetSettings().db
    db.whitelist = db.whitelist or {}
    db.blacklist = db.blacklist or {}
    db.settings = db.settings or {}
    db.version = db.version or 1
    vendor.DB = db
    vendor.Initialize()
    vendor.InitializeFilters()
    vendor.InitializeConfig()
    vendor.ready = true
    vendor.RefreshSettings()
end)
