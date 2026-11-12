-- Offline Lua 5.1 simulation. The collector and every client API are replaced.
local root = TEST_ROOT or "."
local source = root .. "/addon/forerver/wow_tools/LuaGC.lua"
local function Harness(config)
    local state = { pause = 350, stepmul = 250, now = 0, calls = {}, frames = {}, timers = {} }
    local secret = setmetatable({}, { __tostring = function() error("Printed a restricted value") end })
    function issecretvalue(value) return rawequal(value, secret) end
    state.secret = secret
    function collectgarbage(option, value)
        local key = option == "setpause" and "pause" or option == "setstepmul" and "stepmul"
        assert(key and type(value) == "number", "Unexpected collector operation")
        state.calls[#state.calls + 1] = { key = key, value = value, previous = state[key] }
        local action = state.intercept and state.intercept(key, value)
        if action == "error" then error("Simulated native failure") end
        if action == "secret" then return secret end
        local previous = state[key]
        if action ~= "ignore" then state[key] = value end
        return previous
    end
    function date() return "12:00:" .. tostring(state.now) end
    local function Widget(parent)
        local frame = { parent = parent, scripts = {}, events = {}, shown = true, text = "" }
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:CreateFontString() return Widget(self) end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetHeight(height) self.height = height end
        function frame:SetWidth(width) self.width = width end
        function frame:SetText(text) self.text = text end
        function frame:GetText() return self.text end
        function frame:GetWidth() return self.width or 420 end
        function frame:ClearAllPoints() self.point = nil end
        function frame:ClearFocus() self.focused = false end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:IsShown() return self.shown end
        function frame:SetJustifyH() end
        function frame:SetAutoFocus() end
        function frame:SetNumeric() end
        function frame:SetMaxLetters() end
        return frame
    end
    function CreateFrame(_, _, parent)
        local frame = Widget(parent)
        state.frames[#state.frames + 1] = frame
        return frame
    end
    C_Timer = {}
    function C_Timer.NewTicker(interval, callback)
        local timer = { interval = interval, callback = callback, due = state.now + interval }
        function timer:Cancel() self.cancelled = true end
        state.timers[#state.timers + 1] = timer
        return timer
    end
    function state.Event(event)
        for _, frame in ipairs(state.frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event) end
        end
    end
    function state.Advance(seconds)
        state.now = state.now + seconds
        for _, timer in ipairs(state.timers) do
            if not timer.cancelled and timer.due <= state.now then
                timer.due = timer.due + timer.interval
                timer.callback()
            end
        end
    end
    WoWTools = {}
    wowDetectorDB = { unrelated = 42, luaGC = config }
    dofile(source)
    state.module = WoWTools.luaGC
    state.parent = CreateFrame("Frame")
    state.module.BuildSettings(state.parent)
    state.view = state.module.views[1]
    return state
end

local state = Harness()
local module, view = state.module, state.view
assert(#state.calls == 0 and #state.timers == 0 and wowDetectorDB.luaGC == nil,
    "Loading the module or building settings changed the collector or created defaults")
state.Event("PLAYER_ENTERING_WORLD")
assert(#state.calls == 0 and #state.timers == 0, "An unsaved configuration was applied at startup")
assert(view.inputs.pause:GetText() == "200" and view.inputs.stepmul:GetText() == "200" and view.period:GetText() == "5")
assert(view.saved.pause.text == "未保存" and view.system.pause.text == "未知")
state.parent.scripts.OnShow()
assert(state.pause == 350 and state.stepmul == 250 and #state.calls == 4,
    "Reading current values did not restore both native parameters")
assert(view.system.pause.text == "350" and view.system.stepmul.text == "250" and view.saved.pause.text == "未保存")
assert(state.parent.height == module.settingsHeight and view.status.point[3] > -module.settingsHeight,
    "Settings page clips its feedback")
view.inputs.pause:SetText("450")
view.inputs.pause.scripts.OnTextChanged(view.inputs.pause, true)
state.pause = 375
view.refresh.scripts.OnClick()
assert(view.inputs.pause:GetText() == "450" and view.system.pause.text == "375" and state.pause == 375,
    "Refreshing replaced an edit or left the temporary probe applied")
state.parent.scripts.OnShow()
assert(view.inputs.pause:GetText() == "450", "Reopening discarded a dirty draft")
view.inputs.stepmul:SetText("225")
view.apply.scripts.OnClick()
assert(state.pause == 450 and state.stepmul == 225 and wowDetectorDB.luaGC.pause == 450)
assert(wowDetectorDB.luaGC.calibrationMinutes == 5 and wowDetectorDB.unrelated == 42)
assert(view.saved.pause.text == "450" and view.system.pause.text == "450" and view.savedPeriod.text == "5 分钟")
assert(#state.timers == 1 and state.timers[1].interval == 300)

-- A hidden panel still calibrates at its saved deadline, using saved values over UI drafts.
state.parent:Hide()
view.inputs.pause:SetText("999")
state.pause, state.stepmul = 150, 300
local before = #state.calls
state.Advance(299)
assert(#state.calls == before and state.pause == 150, "Calibration ran before five minutes")
state.Advance(1)
assert(state.pause == 450 and state.stepmul == 225 and view.system.pause.text == "450")
assert(view.inputs.pause:GetText() == "999", "Periodic calibration overwrote a draft")
assert(view.status.text:find("发现偏差", 1, true))
before = #state.calls
state.Advance(300)
assert(#state.calls == before + 4 and view.status.text:find("一致", 1, true),
    "An unchanged configuration was rewritten beyond the read-and-restore probes")

-- Independent IGC surfaces display shared current/saved values and retain their own edits.
local otherParent = CreateFrame("Frame")
module.BuildSettings(otherParent)
local otherView = module.views[2]
otherView.inputs.pause:SetText("777")
otherView.inputs.pause.scripts.OnTextChanged(otherView.inputs.pause, true)
state.pause = 399
otherView.refresh.scripts.OnClick()
assert(otherView.system.pause.text == "399" and view.system.pause.text == "399")
assert(otherView.saved.pause.text == "450" and otherView.inputs.pause:GetText() == "777")

-- Period changes cancel the previous ticker and invalidate callbacks already queued.
local oldTimer = state.timers[1]
assert(module.Save("500", "250", "1"))
assert(oldTimer.cancelled and state.timers[2].interval == 60)
state.pause = 333
before = #state.calls
oldTimer.callback()
assert(state.pause == 333 and #state.calls == before, "An obsolete timer changed the new configuration")
state.Advance(59)
assert(state.pause == 333)
state.Advance(1)
assert(state.pause == 500)
assert(module.Save(500, 250, 0))
assert(state.timers[2].cancelled and wowDetectorDB.luaGC.calibrationMinutes == 0)
state.pause = 123
before = #state.calls
state.Advance(600)
assert(state.pause == 123 and #state.calls == before, "A disabled period kept calibrating")
view.calibrate.scripts.OnClick()
assert(state.pause == 500 and wowDetectorDB.luaGC.calibrationMinutes == 0)

-- Validate the complete draft before touching native parameters or the persisted configuration.
local saved = wowDetectorDB.luaGC
before = #state.calls
for _, values in ipairs({
    {0, 200, 5}, {10001, 200, 5}, {200, 0, 5}, {200, 10001, 5},
    {200, 200, -1}, {200, 200, 1441}, {200.5, 200, 5},
    {"1e3", "200", "5"}, {"200", "x", "5"}, {"200", "200", "1.5"},
    {math.huge, 200, 5}, {state.secret, 200, 5},
}) do
    assert(not module.Save(unpack(values)), "Invalid draft was accepted")
end
assert(#state.calls == before and wowDetectorDB.luaGC == saved and state.pause == 500)
assert(module.Save(1, 10000, 1440), "Valid boundary values were rejected")

-- A failed second write restores the first write and keeps the former config/timer.
state = Harness({ pause = 400, stepmul = 250, calibrationMinutes = 5 })
module, view = state.module, state.view
state.Event("PLAYER_ENTERING_WORLD")
assert(state.pause == 400 and state.stepmul == 250 and #state.timers == 1)
before = #state.calls
state.Event("PLAYER_ENTERING_WORLD")
assert(#state.calls == before and #state.timers == 1, "Zoning repeated startup application")
saved = wowDetectorDB.luaGC
state.intercept = function(key, value) if key == "stepmul" and value == 700 then return "error" end end
local ok, message = module.Save(600, 700, 2)
assert(not ok and message:find("已还原", 1, true))
assert(state.pause == 400 and state.stepmul == 250 and wowDetectorDB.luaGC == saved and not state.timers[1].cancelled)
state.intercept = function(key, value) if key == "stepmul" and value == 700 then return "ignore" end end
assert(not module.Save(600, 700, 2), "A silently rejected native setting was reported as successful")
assert(state.pause == 400 and state.stepmul == 250 and wowDetectorDB.luaGC == saved)
local firstWriteApplied = false
state.intercept = function(key, value)
    if key == "pause" and value == 600 then firstWriteApplied = true end
    if key == "stepmul" and value == 700 then return "error" end
    if firstWriteApplied and key == "pause" and value == 400 then return "error" end
end
ok, message = module.Save(600, 700, 2)
assert(not ok and message:find("还原未完成", 1, true) and state.pause == 600 and wowDetectorDB.luaGC == saved,
    "An incomplete rollback was presented as successful restoration")
state.intercept = nil
assert(module.Calibrate() and state.pause == 400)

-- Reading reports failed/restricted fields as unknown and supports a transient restore failure.
state.intercept = function(key) if key == "stepmul" then return "error" end end
assert(not module.Refresh())
assert(view.system.stepmul.text == "未知" and view.saved.stepmul.text == "250" and state.pause == 400)
assert(not module.Calibrate() and wowDetectorDB.luaGC == saved)
state.intercept = function(key) if key == "stepmul" then return "secret" end end
assert(not module.Refresh() and view.system.stepmul.text == "未知")
local failedOnce = false
state.intercept = function(key, value)
    if key == "pause" and value == 400 and not failedOnce then failedOnce = true return "error" end
end
assert(module.Refresh() and failedOnce and state.pause == 400 and state.stepmul == 250)
state.intercept = function(key, value) if key == "pause" and value == 400 then return "error" end end
ok, message = module.Refresh()
assert(not ok and message:find("还原失败", 1, true) and view.system.pause.text == "未知")
state.intercept = nil
assert(module.Calibrate() and state.pause == 400)
state.pause, state.stepmul = 0, -1
assert(module.Refresh() and state.pause == 0 and state.stepmul == -1,
    "Reading an out-of-UI-range native value failed to restore it")

-- Reload restores persisted values once and logout invalidates every remaining callback.
state = Harness({ pause = 600, stepmul = 300, calibrationMinutes = 5 })
module = state.module
assert(#state.calls == 0)
state.Event("PLAYER_ENTERING_WORLD")
assert(state.pause == 600 and state.stepmul == 300 and state.timers[1].interval == 300)
local timer = state.timers[1]
state.Event("PLAYER_LOGOUT")
before = #state.calls
state.pause = 222
timer.callback()
assert(timer.cancelled and state.pause == 222 and #state.calls == before)
for _, frame in ipairs(state.frames) do assert(not frame.scripts.OnUpdate, "A persistent polling loop was installed") end

-- Old/invalid saves stay intact, and missing/timer APIs produce actionable feedback.
local malformed = { pause = 500, stepmul = 200 }
state = Harness(malformed)
state.Event("PLAYER_ENTERING_WORLD")
assert(wowDetectorDB.luaGC == malformed and #state.calls == 0 and #state.timers == 0)
assert(not state.module.Calibrate())
collectgarbage = nil
assert(not state.module.Refresh() and state.view.system.pause.text == "未知")
state = Harness()
wowDetectorDB = nil
assert(not state.module.Save(400, 200, 5) and #state.calls == 0)
state = Harness()
C_Timer.NewTicker = function() error("Simulated timer failure") end
ok, message = state.module.Save(400, 200, 5)
assert(ok and message:find("计时器启动失败", 1, true) and wowDetectorDB.luaGC.pause == 400)
assert(state.module.Save(400, 200, 0), "Manual mode depended on a periodic timer")

print("PASS: Forever Lua GC settings, separate drafts/saved/system values, read-and-restore, atomic apply/rollback, five-minute boundaries, hidden UI calibration, unchanged-value checks, timer replacement/disable/logout, reload, invalid/restricted/missing APIs and native failure feedback. All collector and game operations mocked.")
