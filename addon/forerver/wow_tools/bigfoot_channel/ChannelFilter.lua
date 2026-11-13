-- Preserve the chat-only filter's selected-window scope and timing rules.
local channel = WoWTools.bigfootChannel
local history, lastCleanup = {}, 0
local defaults = {
    IgnoreWords = { "付款", GetLocale() == "zhTW" and "代練" or "代练" },
    OrderWords = { "成就", "幻化" },
}
local symbols = {
    "`",
    "~",
    "@",
    "#",
    "^",
    "*",
    "=",
    "|",
    " ",
    "，",
    "。",
    "、",
    "？",
    "！",
    "：",
    "；",
    "’",
    "‘",
    "“",
    "”",
    "【",
    "】",
    "『",
    "』",
    "《",
    "》",
    "<",
    ">",
    "（",
    "）",
}

local function Readable(value)
    return not issecretvalue or not issecretvalue(value)
end

function channel.GetFilterSettings()
    local settings = channel.GetSettings()
    if type(settings.filter) ~= "table" then
        settings.filter = { Enabled = 1, BanEnabled = 1, NewConfig = 2 }
    end
    for key, values in pairs(defaults) do
        if type(settings.filter[key]) ~= "table" then
            settings.filter[key] = { unpack(values) }
        end
    end
    return settings.filter
end

local function Matches(message, words)
    for _, word in ipairs(words) do
        if type(word) == "string" and word ~= "" then
            -- Legacy lists accept Lua patterns. Invalid patterns remain editable.
            local ok, match = pcall(string.find, message, word:lower())
            if ok and match then
                return true
            end
        end
    end
    return false
end

local function Filter(
    frame,
    event,
    message,
    sender,
    language,
    channelName,
    target,
    flags,
    zoneID,
    channelID,
    baseName,
    unused,
    lineID
)
    local settings = channel.GetFilterSettings()
    if not settings.Enabled or frame ~= SELECTED_CHAT_FRAME then
        return false
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false
    end
    for _, value in pairs({ message, sender, channelName, channelID, baseName, lineID }) do
        if not Readable(value) then
            return false
        end
    end
    if type(message) ~= "string" or type(sender) ~= "string" then
        return false
    end
    if Ambiguate(sender, "none") == UnitName("player") then
        return false
    end
    if event == "CHAT_MSG_TRADESKILLS" then
        return settings.mute and true or false
    end
    local worldName = GetLocale() == "zhTW" and "大腳世界頻道" or "大脚世界频道"
    local isWorld = baseName == worldName
        or (type(channelName) == "string" and channelName:find(worldName, 1, true))
    if settings.mute and not isWorld then
        return true
    end
    local text = message:lower()
    if isWorld and settings.BanEnabled then
        for _, symbol in ipairs(symbols) do
            text = text:gsub(symbol:gsub("(%W)", "%%%1"), "")
        end
        if Matches(text, settings.IgnoreWords) then
            return true
        end
    end
    local now = time()
    if now - lastCleanup > 60 then
        lastCleanup = now
        for name, records in pairs(history) do
            for index = #records, 1, -1 do
                if now - records[index].time > 60 then
                    table.remove(records, index)
                end
            end
            if #records == 0 then
                history[name] = nil
            end
        end
    end
    local records = history[sender] or {}
    for _, record in ipairs(records) do
        if lineID and lineID ~= 0 and record.lineID == lineID then
            return record.blocked
        end
        if type(channelID) == "number" and channelID ~= 0 and now - record.time < 1 then
            return true
        end
        if record.message == message and now - record.time <= 10 then
            return true
        end
    end
    local blocked = isWorld and settings.OrderEnabled and not Matches(message:lower(), settings.OrderWords)
        or false
    records[#records + 1] = { message = message, time = now, lineID = lineID, blocked = blocked }
    history[sender] = records
    return blocked
end
channel.FilterMessage = Filter

function ChannelFilterMuteButton_OnClick()
    local settings = channel.GetFilterSettings()
    settings.mute = not settings.mute
    ChannelFilterMuteButtonMute:SetShown(settings.mute)
end

local function ToggleOption(key, title, order)
    return {
        type = "toggle",
        name = title,
        order = order,
        width = "full",
        get = function()
            return not not channel.GetFilterSettings()[key]
        end,
        set = function(_, value)
            channel.GetFilterSettings()[key] = value and 1 or nil
            if key == "mute" then
                ChannelFilterMuteButtonMute:SetShown(value)
            end
        end,
    }
end

local function WordsOption(key, title, order)
    return {
        type = "input",
        name = title,
        order = order,
        multiline = 6,
        width = "full",
        get = function()
            return table.concat(channel.GetFilterSettings()[key], "\n")
        end,
        set = function(_, text)
            local words, seen = {}, {}
            for word in text:gmatch("[^\r\n]+") do
                word = word:match("^%s*(.-)%s*$")
                if word ~= "" and not seen[word] then
                    words[#words + 1], seen[word] = word, true
                end
            end
            channel.GetFilterSettings()[key] = words
        end,
    }
end

channel.filterOptions = {
    type = "group",
    name = "聊天过滤",
    order = 5,
    args = {
        Enabled = ToggleOption("Enabled", "启用聊天过滤", 1),
        mute = ToggleOption("mute", "屏蔽公共频道和喊话（保留大脚世界频道）", 2),
        BanEnabled = ToggleOption("BanEnabled", "启用大脚世界频道关键词黑名单", 3),
        IgnoreWords = WordsOption(
            "IgnoreWords",
            "屏蔽关键词（每行一个，可使用 Lua 匹配模式）",
            4
        ),
        resetIgnore = {
            type = "execute",
            name = "重置黑名单",
            order = 5,
            func = function()
                channel.GetFilterSettings().IgnoreWords = { unpack(defaults.IgnoreWords) }
            end,
        },
        OrderEnabled = ToggleOption("OrderEnabled", "仅显示匹配白名单的大脚世界频道消息", 6),
        OrderWords = WordsOption("OrderWords", "白名单关键词（每行一个）", 7),
        resetOrder = {
            type = "execute",
            name = "重置白名单",
            order = 8,
            func = function()
                channel.GetFilterSettings().OrderWords = { unpack(defaults.OrderWords) }
            end,
        },
    },
}

local function Command(message)
    local command, word = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local settings = channel.GetFilterSettings()
    if command == "on" then
        settings.Enabled = 1
    elseif command == "off" then
        settings.Enabled = nil
    elseif (command == "+" or command == "add") and word ~= "" then
        for _, existing in ipairs(settings.IgnoreWords) do
            if existing == word then
                return
            end
        end
        settings.IgnoreWords[#settings.IgnoreWords + 1] = word
    elseif command == "-" or command == "remove" then
        if word == "*" then
            settings.IgnoreWords = {}
        else
            for index, existing in ipairs(settings.IgnoreWords) do
                if existing == word or tostring(index) == word then
                    table.remove(settings.IgnoreWords, index)
                    break
                end
            end
        end
    elseif command == "*" or command == "list" then
        for index, existing in ipairs(settings.IgnoreWords) do
            DEFAULT_CHAT_FRAME:AddMessage(index .. ". " .. existing)
        end
    else
        WoWTools.modules.bigfoot_channel.Show("filters")
    end
end
SLASH_GUOLV1, SLASH_GUOLV2, SLASH_GUOLV3 = "/guolv", "/gl", "/过滤"
SLASH_GUOLV4, SLASH_GUOLV5 = "/channelfilter", "/filter"
SlashCmdList.GUOLV = Command

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= "wow_tools" then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    if not WoWTools.thirdParty.IsActive("bigfoot_channel") then return end
    ChannelFilterMuteButtonMute:SetShown(not not channel.GetFilterSettings().mute)
    for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_YELL", "CHAT_MSG_TRADESKILLS" }) do
        ChatFrameUtil.AddMessageEventFilter(event, Filter)
    end
end)
