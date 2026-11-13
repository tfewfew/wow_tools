local channel = WoWTools.bigfootChannel
local button, panel, editBox

local function ShowCopy()
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return
    end
    local chat = SELECTED_CHAT_FRAME or ChatFrame1
    local lines = {}
    for index = 1, chat:GetNumMessages() do
        local ok, text = pcall(chat.GetMessageInfo, chat, index)
        if ok and type(text) == "string" and (not issecretvalue or not issecretvalue(text)) then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            text = text:gsub("|H.-|h(.-)|h", "%1")
            text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
            lines[#lines + 1] = text
        end
    end
    if not panel then
        panel = CreateFrame("Frame", "wowToolsChatCopyPanel", UIParent, "BasicFrameTemplateWithInset")
        panel:SetSize(620, 400)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:SetClampedToScreen(true)
        panel.TitleText:SetText("复制聊天文字（Ctrl+C）")
        tinsert(UISpecialFrames, "wowToolsChatCopyPanel")
        local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -36)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(570)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function()
            panel:Hide()
        end)
        scroll:SetScrollChild(editBox)
        panel:SetScript("OnHide", function()
            editBox:ClearFocus()
        end)
    end
    panel:Show()
    editBox:SetText(table.concat(lines, "\n"))
    editBox:SetFocus()
    editBox:HighlightText()
end

function channel.RefreshCopy()
    if not button then
        button = CreateFrame("Button", "wowToolsChatCopyButton", ChatFrame1, "UIPanelButtonTemplate")
        button:SetSize(30, 20)
        button:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", -46, 3)
        button:SetText("复制")
        button:SetScript("OnClick", ShowCopy)
    end
    local enabled = channel.addon.db.profile.enablecopy
    button:SetShown(enabled)
    if not enabled and panel then
        panel:Hide()
    end
end
