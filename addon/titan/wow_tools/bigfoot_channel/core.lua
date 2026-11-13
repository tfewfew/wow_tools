-- BigFootChat by Terry, imported from Forever's 1.60.1.1-chat-only.2 extraction.
local issecretvalue = issecretvalue or function()
    return false
end
local _
local BFChatAddOn = LibStub("AceAddon-3.0"):NewAddon(
    "WoWToolsBigFootChannel",
    "AceEvent-3.0",
    "AceConsole-3.0",
    "AceHook-3.0",
    "AceTimer-3.0"
)
local L = LibStub("AceLocale-3.0"):GetLocale("WoWToolsBigFootChannel")
local BFC_IconTableMap = {}
local BFC_ReverseIconTableMap = {}
local db
local defaults = {
    profile = {
        enabletimestamp = false,
        enableOldChatFrameStyle = true,
        enableclasscolor = true,
        useshortname = true,
        enablecopy = false,
        enablechatchannelmove = true,
        enableRollButton = true,
        enableReportButton = true,
        enableRaidersButton = true,
        modules = { ["ICONFRAME"] = true, ["CHATFRAME"] = true },
    },
}
local function generateIconMap()
    for index, entry in pairs(BFC_IconTable) do
        BFC_IconTableMap[entry[1]] = entry[2]
    end
    for index, entry in pairs(BFC_IconTable) do
        BFC_ReverseIconTableMap[entry[2]] = entry[1]
    end
end
local function getpoint(point)
    local point, relPoint, relp, xoff, yoff = unpack(point)
    local relObj = _G[relPoint]
    return point, relObj, relp, xoff, yoff
end
local function setpoint(point, relObj, relp, xoff, yoff)
    return { point, relObj:GetName(), relp, xoff, yoff }
end
local function getCurrentFont()
    local _, font = SELECTED_CHAT_FRAME:GetFont()
    font = ceil(font)
    return font
end
local function isTextProcessable(text)
    if type(text) ~= "string" then
        return false
    end
    if issecretvalue(text) then
        return false
    end
    if text == "" then
        return false
    end
    return true
end
function BFC_Print(...)
    local str = ...
    SELECTED_CHAT_FRAME:AddMessage("|cff00adef[" .. L["BFChat"] .. "]|r" .. str)
end
function BFCChatFrame_SavePos(self)
    local point, rel, relp, xoff, yoff = unpack(self.oripoint)
    db.frameposition =
        setpoint(point, rel, relp, xoff + self.endx - self.startx, yoff + self.endy - self.starty)
    self:SetPoint(getpoint(db.frameposition))
end
function BFChatAddOn:ParseLocalText(text)
    for tag in string.gmatch(text, "|T([^:]+):%d+|t") do
        if BFC_ReverseIconTableMap[tag] then
            text = string.gsub(text, "|T[^:]+:%d+|t", BFC_ReverseIconTableMap[tag], 1)
            return text, true
        end
    end
    return text, false
end
local function parseText(text)
    if not isTextProcessable(text) then
        return text
    end
    for tag in string.gmatch(text, "({[^}]+})") do
        if BFC_IconTableMap[tag] then
            local fontSize = getCurrentFont()
            text = text:gsub(tag, "|T" .. BFC_IconTableMap[tag] .. ":" .. fontSize .. "|t", 1)
            break
        end
    end
    return text
end
function BFChatAddOn:ReverseParseText(text, font)
    for tag in string.gmatch(text, "|T([^:]+):" .. font .. "|t") do
        if BFC_ReverseIconTableMap[tag] then
            text = string.gsub(text, "|T[^:]+:" .. font .. "|t", BFC_ReverseIconTableMap[tag], 1)
        end
    end
    return text
end
function BFChatAddOn:MaskSystemColoring(flag)
    local m_ChatTypeInfo
    for k, v in pairs(getmetatable(ChatTypeInfo) or {}) do
        if k == "__index" then
            m_ChatTypeInfo = v
        end
    end
    m_ChatTypeInfo = m_ChatTypeInfo or ChatTypeInfo
    if flag then
        for _chatType, _table in pairs(m_ChatTypeInfo) do
            ToggleChatColorNamesByClassGroup(1, _chatType)
        end
    else
        for _chatType, _isColoring in pairs(m_ChatTypeInfo) do
            ToggleChatColorNamesByClassGroup(nil, _chatType)
        end
    end
end
function BFChatAddOn:UnhookEvents()
    self:UnregisterAllEvents()
end
function BFChatAddOn:Refresh()
    db = self.db.profile
    BFCChatFrame:SetMovable(db.enablechatchannelmove)
    if WoWTools.bigfootChannel.RefreshCopy then
        WoWTools.bigfootChannel.RefreshCopy()
    end
    BFChatAddOn:MaskSystemColoring(db.enableclasscolor)
    if db and db.frameposition then
        BFCChatFrame:SetPoint(unpack(db.frameposition))
    else
        BFCChatFrame:SetPoint("TOPLEFT", ChatFrame1, "BOTTOMLEFT", -5, -2)
    end
    for name, module in self:IterateModules() do
        if module.db then
            if db.modules[name] then
                self:EnableModule(name)
            else
                self:DisableModule(name)
            end
            module:Refresh()
        end
    end
    if BFChannelMuteButton then
        BFChannel_RefreshMuteButton()
    end
end
function BFChatAddOn:OnInitialize()
    if not WoWTools.thirdParty.IsActive("bigfoot_channel") then
        self:SetEnabledState(false)
        return
    end
    self.db = LibStub("AceDB-3.0"):New(WoWTools.bigfootChannel.GetSettings().chat, defaults, "Default")
    self.db.RegisterCallback(self, "OnProfileChanged", "Refresh")
    self.db.RegisterCallback(self, "OnProfileCopied", "Refresh")
    self.db.RegisterCallback(self, "OnProfileReset", "Refresh")
    db = self.db.profile
    self:SetupOptions()
    generateIconMap()
end
local function SetWhisperMode(editbox)
    editbox:SetAttribute("bfwhispermode", "true")
end
local function ClearWhisperMode(editbox)
    editbox:SetAttribute("bfwhispermode", nil)
end
local function RestoreChatType(editbox, name, val)
    if name == "bfwhispermode" then
        if not editbox.bfChatType then
            editbox.bfChatType = "SAY"
        end
        if not val then
            editbox:SetAttribute("chatType", editbox.bfChatType)
            ChatFrameEditBoxMixin.UpdateHeader(editbox)
        end
    end
end
function BFChatAddOn:EnableOldStyleReply()
    hooksecurefunc(ChatFrameEditBoxMixin, "SendText", function(editBox)
        local chatType = editBox:GetAttribute("chatType")
        if chatType ~= "WHISPER" and chatType ~= "BN_WHISPER" then
            editBox.bfChatType = chatType
        end
    end)
    hooksecurefunc(ChatFrameEditBoxMixin, "ClearChat", function(editBox)
        ClearWhisperMode(editBox)
    end)
    ChatFrame1EditBox:HookScript("OnAttributeChanged", function(...)
        if db.enableOldChatFrameStyle then
            RestoreChatType(...)
        end
    end)
    for _, name in ipairs({ "ReplyTell", "ReplyTell2" }) do
        hooksecurefunc(ChatFrameUtil, name, function(chatFrame)
            SetWhisperMode(ChatFrameUtil.ChooseBoxForSend(chatFrame))
        end)
    end
end
function BFChatAddOn:FCF_FadeInChatFrame(chatFrame)
    BFChannelMuteButton:Show()
    UIFrameFadeIn(BFChannelMuteButton, CHAT_FRAME_FADE_TIME, 0.5, 1)
    if ChannelFilterMuteButton then
        ChannelFilterMuteButton:Show()
        UIFrameFadeIn(ChannelFilterMuteButton, CHAT_FRAME_FADE_TIME, 0.5, 1)
    end
end
function BFChatAddOn:FCF_FadeOutChatFrame(chatFrame)
    UIFrameFadeOut(BFChannelMuteButton, CHAT_FRAME_FADE_OUT_TIME, BFChannelMuteButton:GetAlpha(), 0)
    if ChannelFilterMuteButton then
        UIFrameFadeOut(
            ChannelFilterMuteButton,
            CHAT_FRAME_FADE_OUT_TIME,
            ChannelFilterMuteButton:GetAlpha(),
            0
        )
    end
end
function BFChatAddOn:GetChannelListTab(...)
    return { ... }
end
local channelAbbreviations = {
    ["大脚世界频道"] = "世界",
    ["本地防务"] = "防务",
    ["寻求组队"] = "组队",
    ["新手聊天"] = "新手",
    ["预创建队伍"] = "预建",
}
local function shortenChannelName(
    chatFrame,
    event,
    message,
    speaker,
    language,
    channelName,
    target,
    flags,
    zoneChannelID,
    channelIndex,
    channelBaseName,
    ...
)
    if
        not db.useshortname
        or not isTextProcessable(channelName)
        or not isTextProcessable(channelBaseName)
        or issecretvalue(zoneChannelID)
        or issecretvalue(channelIndex)
        or type(zoneChannelID) ~= "number"
        or type(channelIndex) ~= "number"
        or not chatFrame.channelList
    then
        return false
    end

    local channelLength = strlen(channelName)
    local prefix = channelName:match("(%d+. )")
    if not prefix then
        return false
    end

    for full, short in pairs(channelAbbreviations) do
        if channelName:find(full, 1, true) then
            local baseName = strupper(channelBaseName)
            for index, value in pairs(chatFrame.channelList) do
                if isTextProcessable(value) and channelLength > strlen(value) then
                    local zoneID = chatFrame.zoneChannelList and chatFrame.zoneChannelList[index]
                    local matchingZone = zoneChannelID > 0
                        and not issecretvalue(zoneID)
                        and zoneID == zoneChannelID
                    if matchingZone or strupper(value) == baseName then
                        local info = ChatTypeInfo["CHANNEL" .. channelIndex]
                        if not info then
                            return false
                        end
                        local color = CreateColor(info.r, info.g, info.b)
                        local abbreviatedName = prefix .. C_ColorUtil.WrapTextInColor(short, color)
                        return false,
                            message,
                            speaker,
                            language,
                            abbreviatedName,
                            target,
                            flags,
                            zoneChannelID,
                            channelIndex,
                            channelBaseName,
                            ...
                    end
                end
            end
            break
        end
    end
    return false
end

local function filter(chatFrame, event, message, ...)
    if
        not BFChatAddOn:GetModuleEnabled("ICONFRAME")
        or not isTextProcessable(message)
        or not message:find("{", 1, true)
    then
        return false
    end
    local ok, text = pcall(parseText, message)
    if ok and text ~= message then
        return false, text, ...
    end
    return false
end
function BFChatAddOn:OnEnable()
    if self:IsHooked(ChatFrame1, "MessageEventHandler") then
        self:Unhook(ChatFrame1, "MessageEventHandler")
    end
    local filterEvents = {
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_AFK",
        "CHAT_MSG_DND",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM",
    }
    for _, event in ipairs(filterEvents) do
        ChatFrameUtil.AddMessageEventFilter(event, filter)
    end
    ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL", shortenChannelName)
    self:SecureHook("FCF_FadeInChatFrame")
    self:SecureHook("FCF_FadeOutChatFrame")
    self:EnableOldStyleReply()
    BFChannel_RefreshMuteButton()
end
function BFChatAddOn:OnDisable()
    if self:IsHooked(ChatFrame1, "MessageEventHandler") then
        self:Unhook(ChatFrame1, "MessageEventHandler")
    end
    self:UnhookEvents()
end
function BFChatAddOn:GetModuleEnabled(module)
    return db.modules[module]
end
function BFChatAddOn:SetModuleEnabled(module, value)
    local old = db.modules[module]
    db.modules[module] = value
    if old ~= value then
        if value then
            self:EnableModule(module)
        else
            self:DisableModule(module)
        end
    end
end
function BFChannel_RefreshMuteButton()
    if db.mute then
        BFChannelMuteButtonMute:Show()
    else
        BFChannelMuteButtonMute:Hide()
    end
    ChatFrame1:SetChannelEnabled(L["BigFootChannel"], not db.mute)
end
function BFChannelMuteButton_OnClick()
    db.mute = not db.mute
    if db.mute then
        BFC_Print(L["BigFoot Channel has been blocked"])
    else
        BFC_Print(L["BigFoot Channel has been unblocked"])
    end
    BFChannel_RefreshMuteButton()
end
function BFChatAddOn:BFChannelRollButton_OnClick()
    self.db.profile.enableRollButton = not self.db.profile.enableRollButton
    self:GetModule("ICONFRAME"):Refresh()
end
function BFChatAddOn:BFChannelReportButton_OnClick()
    self.db.profile.enableReportButton = not self.db.profile.enableReportButton
    self:GetModule("ICONFRAME"):Refresh()
end
function BFChatAddOn:BFChannelRaidersButton_OnClick()
    self.db.profile.enableRaidersButton = not self.db.profile.enableRaidersButton
    createRaidersFrame()
end
WoWTools.bigfootChannel.addon = BFChatAddOn
