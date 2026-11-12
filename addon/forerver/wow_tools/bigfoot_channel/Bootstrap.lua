-- Extracted from the Forever chat-only BigFoot installation. Ace3 is supplied by !!!Libs.
local channel = {}
WoWTools.bigfootChannel = channel

function channel.GetSettings()
    if type(wowDetectorDB) ~= "table" then
        wowDetectorDB = {}
    end
    if type(wowDetectorDB.bigfootChannel) ~= "table" then
        wowDetectorDB.bigfootChannel = {}
    end
    local settings = wowDetectorDB.bigfootChannel
    if type(settings.chat) ~= "table" then
        settings.chat = {}
    end
    if settings.autoJoinWorld == nil then
        settings.autoJoinWorld = true
    end
    return settings
end

function BigFoot_ShowNewbieTooltip(title, text)
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetText(title or "", 1, 0.82, 0)
    if text then
        GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function BigFoot_HideNewbieTooltip()
    GameTooltip:Hide()
end

local function Show(tab)
    if not channel.addon or not channel.addon.db then
        return
    end
    local dialog = LibStub("AceConfigDialog-3.0")
    dialog:Open("WoWToolsBigFootChannel")
    if tab then
        dialog:SelectGroup("WoWToolsBigFootChannel", tab)
    end
end

local function IsShown()
    local frame = LibStub("AceConfigDialog-3.0").OpenFrames.WoWToolsBigFootChannel
    return frame and frame.frame:IsShown() or false
end

local function Hide()
    LibStub("AceConfigDialog-3.0"):Close("WoWToolsBigFootChannel")
end

WoWTools.modules.bigfoot_channel = {
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
SLASH_WOWTOOLSBIGFOOT1 = "/bigfootchannel"
SLASH_WOWTOOLSBIGFOOT2 = "/bfchat"
SLASH_WOWTOOLSBIGFOOT3 = "/bigfoot"
SlashCmdList.WOWTOOLSBIGFOOT = function(message)
    Show(message and message:lower():match("^filter") and "filters" or nil)
end
SLASH_WOWTOOLSBIGFOOTFILTER1 = "/bffilter"
SlashCmdList.WOWTOOLSBIGFOOTFILTER = function()
    Show("filters")
end
