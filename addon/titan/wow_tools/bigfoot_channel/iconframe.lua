local BFChat = LibStub("AceAddon-3.0"):GetAddon("WoWToolsBigFootChannel")
local L = LibStub("AceLocale-3.0"):GetLocale("WoWToolsBigFootChannel")
local MODNAME = "ICONFRAME"
local BFChatIconFrame = BFChat:NewModule(MODNAME)
local BFC_NUM_TAB = 60
local BFC_ICON_SIZE_X = 25
local BFC_ICON_SIZE_Y = 25
local BFC_ICON_NUMBER_X = 10
local chaticonbuttonlist = {}
BFC_IconTable = {
    { "{rt1}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
    { "{rt2}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
    { "{rt3}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
    { "{rt4}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
    { "{rt5}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
    { "{rt6}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
    { "{rt7}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
    { "{rt8}", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
    { "{" .. L.Angel .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\angel.tga" },
    { "{" .. L.Angry .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\angry.tga" },
    { "{" .. L.Biglaugh .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\biglaugh.tga" },
    { "{" .. L.Clap .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\clap.tga" },
    { "{" .. L.Cool .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\cool.tga" },
    { "{" .. L.Cry .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\cry.tga" },
    { "{" .. L.Cute .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\cutie.tga" },
    { "{" .. L.Despise .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\despise.tga" },
    { "{" .. L.Dreamsmile .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\dreamsmile.tga" },
    { "{" .. L.Embarras .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\embarrass.tga" },
    { "{" .. L.Evil .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\evil.tga" },
    { "{" .. L.Excited .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\excited.tga" },
    { "{" .. L.Faint .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\faint.tga" },
    { "{" .. L.Fight .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\fight.tga" },
    { "{" .. L.Flu .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\flu.tga" },
    { "{" .. L.Freeze .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\freeze.tga" },
    { "{" .. L.Frown .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\frown.tga" },
    { "{" .. L.Greet .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\greet.tga" },
    { "{" .. L.Grimace .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\grimace.tga" },
    { "{" .. L.Growl .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\growl.tga" },
    { "{" .. L.Happy .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\happy.tga" },
    { "{" .. L.Heart .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\heart.tga" },
    { "{" .. L.Horror .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\horror.tga" },
    { "{" .. L.Ill .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\ill.tga" },
    { "{" .. L.Innocent .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\innocent.tga" },
    { "{" .. L.Kongfu .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\kongfu.tga" },
    { "{" .. L.Love .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\love.tga" },
    { "{" .. L.Mail .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\mail.tga" },
    { "{" .. L.Makeup .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\makeup.tga" },
    { "{" .. L.Mario .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\mario.tga" },
    { "{" .. L.Meditate .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\meditate.tga" },
    { "{" .. L.Miserable .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\miserable.tga" },
    { "{" .. L.Okay .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\okay.tga" },
    { "{" .. L.Pretty .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\pretty.tga" },
    { "{" .. L.Puke .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\puke.tga" },
    { "{" .. L.Shake .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\shake.tga" },
    { "{" .. L.Shout .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\shout.tga" },
    { "{" .. L.Silent .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\shuuuu.tga" },
    { "{" .. L.Shy .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\shy.tga" },
    { "{" .. L.Sleep .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\sleep.tga" },
    { "{" .. L.Smile .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\smile.tga" },
    { "{" .. L.Suprise .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\suprise.tga" },
    { "{" .. L.Surrender .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\surrender.tga" },
    { "{" .. L.Sweat .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\sweat.tga" },
    { "{" .. L.Tear .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\tear.tga" },
    { "{" .. L.Tears .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\tears.tga" },
    { "{" .. L.Think .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\think.tga" },
    { "{" .. L.Titter .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\titter.tga" },
    { "{" .. L.Ugly .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\ugly.tga" },
    { "{" .. L.Victory .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\victory.tga" },
    { "{" .. L.Volunteer .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\volunteer.tga" },
    { "{" .. L.Wronged .. "}", "Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\wronged.tga" },
}
local db
local defaults = { profile = { enablechaticon = false } }
local optGetter, optSetter
do
    local mod = BFChatIconFrame
    function optGetter(info)
        local key = info[#info]
        return BFChat.db.profile[key]
    end
    function optSetter(info, value)
        local key = info[#info]
        BFChat.db.profile[key] = value
        mod:Refresh()
    end
end
local options
local getOptions = function()
    if not options then
        options = {
            type = "group",
            name = L["IconFrame"],
            arg = MODNAME,
            get = optGetter,
            set = optSetter,
            args = {
                intro = {
                    order = 1,
                    type = "description",
                    name = L["this function allows you to use emtion icons in your chat, and others who has this addon enabled can see your emtion icons"],
                },
                enablechaticon = {
                    order = 2,
                    type = "toggle",
                    name = L["Enable emotion icons"],
                    get = function()
                        return BFChat:GetModuleEnabled(MODNAME)
                    end,
                    set = function(info, value)
                        BFChat:SetModuleEnabled(MODNAME, value)
                    end,
                },
            },
        }
    end
    return options
end
local function createIconButton(text, texture, i)
    local chatTab = _G["BFCChatIconButton" .. i]
        or CreateFrame("Button", "BFCChatIconButton" .. i, BFCIconFrame, "BFCIconButtonTemplate")
    chatTab.id = i
    chatTab.text = text
    chatTab.texture = texture
    chatTab:SetNormalTexture(texture)
    return chatTab
end
local function setIconPosition(frame, icon, ix, iy)
    icon:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        (ix - 1) * BFC_ICON_SIZE_X + 5,
        -1 * (iy - 1) * BFC_ICON_SIZE_Y - 5
    )
end
local function arrangeIcons(frame, icons)
    local px = 1
    local py = 1
    for i = 1, BFC_NUM_TAB, 1 do
        setIconPosition(frame, icons[i], px, py)
        px = px + 1
        if px == BFC_ICON_NUMBER_X + 1 then
            px = 1
            py = py + 1
        end
    end
end
local function createRollFrame()
    local rollButton = _G.BFCIconFrameRollButton
    if BFChatFrame_CheckNumber then
        rollButton:SetPoint("LEFT", _G["BFCChatTab" .. BFChatFrame_CheckNumber], "RIGHT", 1, 0)
    else
        rollButton:SetPoint("TOPLEFT", BFCChatFrame, "TOPLEFT", 268, -3)
    end
    if BFChat.db.profile.enableRollButton then
        rollButton:Show()
    end
    rollButton:SetScript("OnEnter", function(self)
        BigFoot_ShowNewbieTooltip(L["RollDice"])
    end)
    rollButton:SetScript("OnLeave", function(self)
        BigFoot_HideNewbieTooltip()
    end)
end
local function createIconFrame()
    local callOutButton = _G.BFCIconFrameCalloutButton
    local iconFrame = _G.BFCIconFrame
    callOutButton:SetScript("OnClick", function()
        if not iconFrame then
            return
        end
        if iconFrame:IsShown() then
            iconFrame:Hide()
        else
            iconFrame:Show()
        end
    end)
    callOutButton:SetScript("OnEnter", function() end)
    callOutButton:SetScript("OnLeave", function() end)
    callOutButton:SetAlpha(0.8)
    callOutButton:SetPoint("TOPLEFT", BFCChatFrame, "TOPLEFT", 2, -3)
    callOutButton:Show()
    local i = 0
    for index, entry in pairs(BFC_IconTable) do
        i = i + 1
        chaticonbuttonlist[i] = createIconButton(entry[1], entry[2], index)
    end
    BFC_NUM_TAB = i
    arrangeIcons(iconFrame, chaticonbuttonlist)
    iconFrame.iconButtonList = chaticonbuttonlist
    iconFrame:SetScript("OnShow", function(self)
        local i = 1
        while self.iconButtonList[i] do
            self.iconButtonList[i]:Show()
            i = i + 1
        end
    end)
    iconFrame:SetScript("OnHide", function(self)
        local i = 1
        while self.iconButtonList[i] do
            self.iconButtonList[i]:Hide()
            i = i + 1
        end
    end)
end
function BFChatIconFrame:OnInitialize()
    if not WoWTools.thirdParty.IsActive("bigfoot_channel") then
        self:SetEnabledState(false)
        return
    end
    self.db = BFChat.db:RegisterNamespace(MODNAME, defaults)
    db = self.db.profile
    self:SetEnabledState(BFChat:GetModuleEnabled(MODNAME))
    BFChat:RegisterModuleOptions(MODNAME, getOptions, L["IconFrame"])
    local worldFrame_MouseUp = WorldFrame:GetScript("OnMouseUp")
    if worldFrame_MouseUp then
        WorldFrame:HookScript("OnMouseUp", function()
            if BFCIconFrame then
                BFCIconFrame:Hide()
            end
        end)
    else
        WorldFrame:SetScript("OnMouseUp", function()
            if BFCIconFrame then
                BFCIconFrame:Hide()
            end
        end)
    end
end
function BFChatIconFrame:Refresh()
    local enabled = self:IsEnabled()
    BFCIconFrameCalloutButton:SetShown(enabled)
    BFCIconFrameRollButton:SetShown(enabled and BFChat.db.profile.enableRollButton)
    BFCIconFrameReportButton:SetShown(enabled and BFChat.db.profile.enableReportButton)
    createRaidersFrame()
end
local function NormalizeEmoteText(self)
    if not BFChatIconFrame:IsEnabled() then
        return
    end
    local current = self:GetText()
    if type(current) ~= "string" or (issecretvalue and issecretvalue(current)) then
        return
    end
    local text, changed = BFChat:ParseLocalText(current)
    if changed then
        self:SetText(text)
    end
end
function BFChatIconFrame:OnEnable()
    for i = 1, NUM_CHAT_WINDOWS do
        local editBox = _G["ChatFrame" .. i .. "EditBox"]
        if editBox and not editBox.wowToolsEmoteHook then
            editBox.wowToolsEmoteHook = true
            editBox:HookScript("OnTextChanged", NormalizeEmoteText)
        end
    end
    createIconFrame()
    createRollFrame()
    createReportFrame()
    raidersFrame_Init()
    self:Refresh()
end
function BFChatIconFrame:OnDisable()
    BFCIconFrame:Hide()
    self:Refresh()
end
function BFC_StartCount(frame)
    if frame:GetParent() ~= UIParent then
        BFC_StartCount(frame:GetParent())
        return
    end
    frame.showTimer = 1
    frame.isCounting = 1
end
function BFC_StopCount(frame)
    if frame:GetParent() ~= UIParent then
        BFC_StopCount(frame:GetParent())
        return
    end
    frame.isCounting = nil
end
function BFC_OnUpdate(self, elapsed)
    if not self.showTimer or not self.isCounting then
        return
    elseif self.showTimer < 0 then
        self:Hide()
        self.showTimer = nil
        self.isCounting = nil
    else
        self.showTimer = self.showTimer - elapsed
    end
end
local function StartMoving(self, button)
    changeBGTexture(self)
    if not BFChat.db.profile.enablechatchannelmove or button ~= "LeftButton" then
        return
    end
    BFCChatFrame.isMoving = true
    BFCChatFrame.oripoint = { BFCChatFrame:GetPoint() }
    BFCChatFrame.starty = BFCChatFrame:GetTop()
    BFCChatFrame.startx = BFCChatFrame:GetLeft()
    local scale = BFCChatFrame:GetEffectiveScale()
    local mouseX, mouseY = GetCursorPosition()
    local point, relativeTo, relativePoint, startX, startY = BFCChatFrame:GetPoint()
    local minX = -relativeTo:GetLeft()
    local maxX = UIParent:GetWidth() - BFCChatFrame:GetWidth()
    local minY = -(relativeTo:GetBottom() - BFCChatFrame:GetHeight())
    local maxY = UIParent:GetHeight() - relativeTo:GetBottom()
    local lastX = mouseX
    local lastY = mouseY
    BFCChatFrame:SetScript("OnUpdate", function()
        local newMouseX, newMouseY = GetCursorPosition()
        if newMouseX == lastX and newMouseY == lastY then
            return
        end
        lastX = newMouseX
        lastY = newMouseY
        local newX = startX + (newMouseX - mouseX) / scale
        newX = max(newX, minX)
        newX = min(newX, maxX)
        local newY = startY + (newMouseY - mouseY) / scale
        newY = max(newY, minY)
        newY = min(newY, maxY)
        BFCChatFrame:ClearAllPoints()
        BFCChatFrame:SetPoint(point, relativeTo, relativePoint, newX, newY)
    end)
end
local function StopMoving(self)
    changeBGTexture(self, 1)
    if BFCChatFrame.isMoving then
        BFCChatFrame.isMoving = nil
        BFCChatFrame:SetScript("OnUpdate", nil)
        BFCChatFrame.endx = BFCChatFrame:GetLeft()
        BFCChatFrame.endy = BFCChatFrame:GetTop()
        BFCChatFrame_SavePos(BFCChatFrame)
    end
end
function BFC_RegisterForDrag(f)
    f:SetScript("OnMouseDown", StartMoving)
    f:SetScript("OnMouseUp", StopMoving)
end
function changeBGTexture(self, switch)
    local texture = _G[self:GetName() .. "BG"]
    if not texture then
        return
    end
    if switch then
        texture:SetTexture("Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\text_push_frame")
    else
        texture:SetTexture("Interface\\AddOns\\wow_tools\\bigfoot_channel\\icon\\text_nor_frame")
    end
end
