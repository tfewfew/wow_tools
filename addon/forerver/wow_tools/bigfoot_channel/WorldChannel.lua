-- Login channel setup is independent of the chat skin's Ace initialization.
local locale = GetLocale()
local channel = locale == "zhTW" and "大腳世界頻道" or "大脚世界频道"
local frame = CreateFrame("Frame", "BigFootChatWorldChannel")
local module = WoWTools.bigfootChannel
module.worldChannel = frame
local generation = 0
local started = false
local maxAttempts = 6
frame.state = "waiting"
frame.attempts = 0

local function channelID()
    local id = GetChannelName(channel)
    if issecretvalue and issecretvalue(id) then
        return 0
    end
    return tonumber(id) or 0
end

local function isMuted()
    if not LibStub then
        return false
    end
    local ace = LibStub("AceAddon-3.0", true)
    local addon = ace and ace:GetAddon("WoWToolsBigFootChannel", true)
    return addon and addon.db and addon.db.profile and addon.db.profile.mute or false
end

local function report(message)
    local chat = DEFAULT_CHAT_FRAME or ChatFrame1
    if chat then
        chat:AddMessage("|cff00adef[大脚聊天]|r " .. message)
    end
end

local function attachToChat()
    if channelID() == 0 then
        return false
    end
    local chat = ChatFrame1 or DEFAULT_CHAT_FRAME
    if not chat then
        return false
    end
    local muted = isMuted()
    if not muted then
        if ChatFrameUtil and ChatFrameUtil.AddChannel then
            ChatFrameUtil.AddChannel(chat, channel)
        elseif ChatFrame_AddChannel then
            ChatFrame_AddChannel(chat, channel)
        end
    end
    if chat.SetChannelEnabled then
        chat:SetChannelEnabled(channel, not muted)
    end
    frame.state = muted and "muted" or "joined"
    frame.lastError = nil
    frame.active = false
    generation = generation + 1
    return true
end

local function finishFailure(message)
    frame.active = false
    frame.state = "failed"
    frame.lastError = message
    generation = generation + 1
    report(message .. "。输入 /bfchannel 查看状态，或 /join " .. channel .. " 手动加入。")
end

local function attemptJoin()
    if not frame.active or attachToChat() then
        return
    end
    if frame.attempts >= maxAttempts then
        finishFailure("自动加入" .. channel .. "未成功")
        return
    end
    local join = JoinTemporaryChannel or JoinChannelByName
    if not join then
        finishFailure("当前客户端未提供加入频道接口")
        return
    end
    frame.attempts = frame.attempts + 1
    frame.state = "joining"
    local chat = ChatFrame1 or DEFAULT_CHAT_FRAME
    local id = chat and chat:GetID() or 1
    local ok, err = pcall(join, channel, nil, id)
    if not ok then
        frame.lastError = tostring(err)
    end
    if attachToChat() then
        return
    end
    local token = generation
    C_Timer.After(5, function()
        if token == generation then
            attemptJoin()
        end
    end)
end

local function start()
    if locale ~= "zhCN" and locale ~= "zhTW" then
        return
    end
    generation = generation + 1
    frame.active = true
    frame.attempts = 0
    frame.lastError = nil
    frame.state = "waiting"
    local token = generation
    C_Timer.After(3, function()
        if token == generation then
            attemptJoin()
        end
    end)
end
module.StartWorldChannel = start
module.StopWorldChannel = function()
    generation = generation + 1
    frame.active = false
    frame.state = "disabled"
end
module.WorldChannelStatus = function()
    local states = {
        waiting = "等待加入",
        joining = "正在加入",
        joined = "已加入",
        muted = "已加入并屏蔽",
        failed = "加入失败",
        disabled = "自动加入已关闭",
    }
    local state = channelID() > 0 and (isMuted() and "muted" or "joined") or frame.state
    return (states[state] or state)
        .. "，频道编号 "
        .. channelID()
        .. (frame.lastError and "，" .. frame.lastError or "")
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHANNEL_UI_UPDATE")
frame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not started then
            started = true
            if module.GetSettings().autoJoinWorld then
                start()
            else
                module.StopWorldChannel()
            end
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
    elseif self.active then
        if event == "CHAT_MSG_CHANNEL_NOTICE" then
            local notice, _, _, name, _, _, _, _, baseName = ...
            if
                issecretvalue and (issecretvalue(notice) or issecretvalue(name) or issecretvalue(baseName))
            then
                return
            end
            local matching = (baseName and baseName == channel)
                or (type(name) == "string" and name:find(channel, 1, true))
            if
                matching
                and (
                    notice == "BANNED"
                    or notice == "WRONG_PASSWORD"
                    or notice == "INVALID_NAME"
                    or notice == "CHANNEL_FULL"
                )
            then
                finishFailure("服务器拒绝加入" .. channel .. "（" .. notice .. "）")
                return
            end
        end
        attachToChat()
    end
end)

SLASH_BIGFOOTWORLDCHANNEL1 = "/bfchannel"
SlashCmdList.BIGFOOTWORLDCHANNEL = function(message)
    if message and message:lower():match("^join%s*$") then
        start()
        return
    end
    local id = channelID()
    if id > 0 then
        report(
            "已加入"
                .. channel
                .. "，频道编号 "
                .. id
                .. (isMuted() and "；当前已屏蔽消息。" or "。")
        )
    elseif frame.active then
        report("正在自动加入" .. channel .. "（已尝试 " .. frame.attempts .. " 次）。")
    else
        report("尚未加入" .. channel .. "；输入 /bfchannel join 可重新尝试。")
    end
end
