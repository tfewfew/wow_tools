-- ls_Toasts by lightspark, imported from the installed Forever 16001 package.
local module = { sourceVersion = "16001" }
WoWTools.lsToasts = module

function module.GetSettings()
    if type(wowDetectorDB) ~= "table" then
        wowDetectorDB = {}
    end
    if type(wowDetectorDB.lsToasts) ~= "table" then
        wowDetectorDB.lsToasts = {}
    end
    local settings = wowDetectorDB.lsToasts
    if type(settings.db) ~= "table" then
        settings.db = {}
    end
    return settings
end

local function IsShown()
    local window = LibStub("AceConfigDialog-3.0").OpenFrames.WoWToolsLsToasts
    return window and window.frame:IsShown() or false
end

local function Show()
    if not module.ready then
        return
    end
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("lsToast：请在脱战后打开设置。")
        return
    end
    LibStub("AceConfigDialog-3.0"):Open("WoWToolsLsToasts")
end

local function Hide()
    LibStub("AceConfigDialog-3.0"):Close("WoWToolsLsToasts")
end

WoWTools.modules.ls_toasts = {
    Show = Show,
    Hide = Hide,
    IsShown = IsShown,
    Toggle = function()
        if IsShown() then
            Hide()
        else
            Show()
        end
    end,
}
