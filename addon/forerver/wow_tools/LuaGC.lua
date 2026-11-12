local module = { views = {}, settingsHeight = 494 }
WoWTools.luaGC = module

local options = {
    { key = "pause", option = "setpause", label = "回收启动阈值",
      description = "setpause，1–10000%。数值越大，下一轮回收启动越晚。" },
    { key = "stepmul", option = "setstepmul", label = "增量回收工作量",
      description = "setstepmul，1–10000%。数值越大，每步回收工作量越多。" },
}
local ticker, timerVersion = nil, 0
local status = "尚未保存 Lua 配置。"

local function Integer(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "number" and value == value and math.abs(value) <= 2147483647
        and value == math.floor(value)
end

local function Valid(config)
    return type(config) == "table" and Integer(config.pause) and config.pause >= 1 and config.pause <= 10000
        and Integer(config.stepmul) and config.stepmul >= 1 and config.stepmul <= 10000
        and Integer(config.calibrationMinutes) and config.calibrationMinutes >= 0 and config.calibrationMinutes <= 1440
end

local function Config()
    local config = type(wowDetectorDB) == "table" and wowDetectorDB.luaGC
    if Valid(config) then return config end
end

local function UpdateViews()
    local config = Config()
    for _, view in ipairs(module.views) do
        for _, spec in ipairs(options) do
            view.saved[spec.key]:SetText(config and tostring(config[spec.key]) or "未保存")
            local value = module.latest and module.latest[spec.key]
            view.system[spec.key]:SetText(value ~= nil and tostring(value) or "未知")
        end
        view.savedPeriod:SetText(config and (config.calibrationMinutes .. " 分钟") or "未保存")
        view.updated:SetText(module.readAt and ("最近读取 " .. module.readAt) or "尚未读取系统值")
        view.status:SetText(status)
    end
end

local function Write(spec, value)
    if type(collectgarbage) ~= "function" then return false end
    local ok, previous = pcall(collectgarbage, spec.option, value)
    return ok and Integer(previous)
end

local function ReadOption(spec)
    if type(collectgarbage) ~= "function" then return nil, spec.label .. "接口不可用。" end
    -- Lua 5.1 exposes these values through setters' return values. Restore immediately,
    -- before formatting text or allocating a snapshot, using a bounded probe value.
    local ok, previous = pcall(collectgarbage, spec.option, 200)
    if not ok or not Integer(previous) then return nil, spec.label .. "读取失败。" end
    if not Write(spec, previous) and not Write(spec, previous) then
        return nil, spec.label .. "读取后的还原失败，请重试刷新。"
    end
    return previous
end

local function ReadSystem()
    local values, errors = {}, {}
    for _, spec in ipairs(options) do
        local value, message = ReadOption(spec)
        values[spec.key] = value
        if message then errors[#errors + 1] = message end
    end
    module.latest = values
    module.readAt = date("%H:%M:%S")
    if #errors > 0 then return nil, table.concat(errors, " ") end
    return values
end

local function ApplyValues(previous, desired)
    local changed, succeeded = false, true
    for _, spec in ipairs(options) do
        if previous[spec.key] ~= desired[spec.key] then
            changed = true
            if not Write(spec, desired[spec.key]) then succeeded = false break end
        end
    end
    if not changed then return true, false end
    local actual = ReadSystem()
    if succeeded and actual and actual.pause == desired.pause and actual.stepmul == desired.stepmul then
        return true, true
    end
    local restored = true
    for _, spec in ipairs(options) do
        if not Write(spec, previous[spec.key]) then restored = false end
    end
    actual = ReadSystem()
    restored = restored and actual and actual.pause == previous.pause and actual.stepmul == previous.stepmul
    return false, restored and "应用失败，已还原操作前的系统值。" or "应用失败，系统值还原未完成，请刷新后检查。"
end

function module.Refresh()
    local values, message = ReadSystem()
    status = values and "已刷新最新系统值。" or message
    UpdateViews()
    return values ~= nil, status
end

function module.Calibrate()
    local config = Config()
    if not config then
        status = "尚无有效的保存配置，请先保存并应用。"
        UpdateViews()
        return false, status
    end
    local previous, message = ReadSystem()
    local succeeded, changed = false, nil
    if previous then succeeded, changed = ApplyValues(previous, config) end
    if succeeded then
        status = changed and "发现偏差，已按保存配置校准。" or "校准完成，系统值与保存配置一致。"
    else
        status = message or changed
    end
    UpdateViews()
    return succeeded, status
end

local function StopTimer()
    timerVersion = timerVersion + 1
    if ticker then ticker:Cancel() ticker = nil end
end

local function StartTimer()
    StopTimer()
    local config = Config()
    if not config or config.calibrationMinutes == 0 then return true end
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return false end
    local version = timerVersion
    local ok, created = pcall(C_Timer.NewTicker, config.calibrationMinutes * 60, function()
        if version == timerVersion then module.Calibrate() end
    end)
    if not ok or not created or type(created.Cancel) ~= "function" then return false end
    ticker = created
    return true
end

local function Parse(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "string" and value:match("^%s*%d+%s*$") then return tonumber(value) end
    if Integer(value) then return value end
end

function module.Save(pause, stepmul, calibrationMinutes)
    local desired = { pause = Parse(pause), stepmul = Parse(stepmul), calibrationMinutes = Parse(calibrationMinutes) }
    if not Valid(desired) then
        status = "两个百分比须为 1–10000 整数，校准周期须为 0–1440 整数分钟。"
        UpdateViews()
        return false, status
    end
    if type(wowDetectorDB) ~= "table" then
        status = "插件尚未初始化，请稍后重试。"
        UpdateViews()
        return false, status
    end
    local previous, message = ReadSystem()
    local succeeded, failure = false, nil
    if previous then succeeded, failure = ApplyValues(previous, desired) end
    if not succeeded then
        status = message or failure
        UpdateViews()
        return false, status
    end
    wowDetectorDB.luaGC = desired
    local timerStarted = StartTimer()
    status = desired.calibrationMinutes == 0 and "已保存并应用，周期校准已关闭。"
        or ("已保存并应用，每 " .. desired.calibrationMinutes .. " 分钟校准一次。")
    if not timerStarted then status = "已保存并应用，周期计时器启动失败，请重新保存。" end
    UpdateViews()
    return true, status
end

local function LoadDraft(view)
    local config = Config()
    view.inputs.pause:SetText(tostring(config and config.pause or 200))
    view.inputs.stepmul:SetText(tostring(config and config.stepmul or 200))
    view.period:SetText(tostring(config and config.calibrationMinutes or 5))
    view.dirty = false
end

function module.BuildSettings(parent)
    local function Text(text, x, y, width, font)
        local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        return label
    end
    local view = { inputs = {}, saved = {}, system = {}, dirty = false }
    module.views[#module.views + 1] = view
    Text("两个参数均采用百分比刻度，100 表示 1 倍。设置作用于整个 Lua 环境，保存后立即应用，登录或重载后恢复。", 8, -8, 398)
    Text("参数", 8, -78, 140, "GameFontNormal")
    Text("设置值 %", 154, -78, 76, "GameFontNormal")
    Text("已保存 %", 238, -78, 76, "GameFontNormal")
    Text("最新系统值 %", 320, -78, 94, "GameFontNormal")
    local function Input(x, y)
        local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", x, y)
        input:SetSize(66, 24)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(5)
        input:SetScript("OnTextChanged", function(_, userInput) if userInput then view.dirty = true end end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return input
    end
    for index, spec in ipairs(options) do
        local y = -112 - (index - 1) * 76
        Text(spec.label, 8, y, 140)
        view.inputs[spec.key] = Input(154, y + 5)
        view.saved[spec.key] = Text("未保存", 238, y, 76)
        view.system[spec.key] = Text("未知", 320, y, 94)
        Text(spec.description, 8, y - 30, 398)
    end
    Text("校准周期（分钟）", 8, -264, 140)
    view.period = Input(154, -259)
    view.savedPeriod = Text("未保存", 238, -264, 170)
    Text("周期范围 0–1440 分钟，0 关闭自动校准。每次校准比对保存值，发现偏差后立即应用保存配置。", 8, -296, 398)
    local function Button(text, x, width, callback)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", x, -344)
        button:SetSize(width, 26)
        button:SetText(text)
        button:SetScript("OnClick", callback)
        return button
    end
    view.refresh = Button("刷新系统值", 8, 110, module.Refresh)
    view.apply = Button("保存并应用", 134, 118, function()
        local saved = module.Save(view.inputs.pause:GetText(), view.inputs.stepmul:GetText(), view.period:GetText())
        if saved then LoadDraft(view) end
        view.inputs.pause:ClearFocus()
        view.inputs.stepmul:ClearFocus()
        view.period:ClearFocus()
    end)
    view.calibrate = Button("立即校准", 268, 110, module.Calibrate)
    view.updated = Text("", 8, -386, 398)
    view.status = Text("", 8, -412, 398)
    Text("系统参数读取使用接口返回的旧值，并立即还原该值。", 8, -466, 398)
    parent:SetHeight(module.settingsHeight)
    parent:SetScript("OnShow", function()
        if not view.dirty then LoadDraft(view) end
        module.Refresh()
    end)
    LoadDraft(view)
    UpdateViews()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then StopTimer() return end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if Config() then
        module.Calibrate()
        if not StartTimer() then
            status = "周期计时器启动失败，请重新保存。"
            UpdateViews()
        end
    end
end)
