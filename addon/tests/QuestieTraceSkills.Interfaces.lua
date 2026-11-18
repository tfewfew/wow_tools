-- Check the installed/staged tracker's raw skill-query interface.
local addonRoot = assert(TEST_QUESTIETRACE_ROOT)
local tracker
local function RejectMutation()
    error("QuestieTrace skill queries must preserve the native list")
end
local core = {
    PackArgs = function(...) return {n = select("#", ...), ...} end,
    DeepCompare = function(left, right)
        for key, value in pairs(left) do
            if right[key] ~= value then return false end
        end
        for key, value in pairs(right) do
            if left[key] ~= value then return false end
        end
        return true
    end,
    RegisterTracker = function(value) tracker = value end,
}
local env = setmetatable({
    QuestieTraceCore = core,
    GetTime = function() return 11 end,
    GetTimePreciseSec = function() return 11.5 end,
    GetNumSkillLines = function() return 1 end,
    GetSkillLineInfo = function(index)
        assert(index == 1)
        return "Professions", true, false, nil, 0
    end,
    GetProfessions = function() return 1, nil, nil, 4 end,
    GetProfessionInfo = function(index)
        assert(index == 1 or index == 4)
        return index == 1 and "Alchemy" or "Fishing", nil, 0, 75
    end,
    ExpandSkillHeader = RejectMutation,
    CollapseSkillHeader = RejectMutation,
    C_SkillInfo = {ExpandSkillHeader = RejectMutation, CollapseSkillHeader = RejectMutation},
    C_TradeSkillUI = {
        GetAllProfessionTradeSkillLines = function() return {171} end,
        GetTradeSkillLineInfoByID = function(id)
            assert(id == 171)
            return {professionID = id, skillLevel = 0}
        end,
    },
}, {__index = _G})
local chunk = assert(loadfile(addonRoot .. "/Modules/Trackers/SkillLines.lua"))
setfenv(chunk, env)
chunk()
assert(type(tracker.Init) == "function" and type(tracker.OnEvent) == "function")
local capture = {startedAt = 10, startedAtPrecise = 10, session = {functions = {}}}
tracker.Init(capture)
for _, event in ipairs(tracker.events) do
    tracker.OnEvent(capture, event)
end
local functions = capture.session.functions
assert(functions.GetNumSkillLines[1].v == 1)
local row = functions.GetSkillLineInfo[1][1].v
assert(row.n == 5 and row[1] == "Professions" and row[2] == true and row[3] == false)
local professions = functions.GetProfessions[1].v
assert(professions.n == 4 and professions[1] == 1 and professions[4] == 4)
assert(functions.GetProfessionInfo[1][1].v[1] == "Alchemy")
assert(functions.GetProfessionInfo[4][1].v[1] == "Fishing")
assert(functions["C_TradeSkillUI.GetTradeSkillLineInfoByID"][171][1].v.skillLevel == 0)

-- Clients expose the observed legacy streams independently from native profession APIs.
env.GetNumSkillLines, env.GetSkillLineInfo = nil, nil
capture.session = {functions = {}}
tracker.Init(capture)
assert(capture.session.functions.GetNumSkillLines == nil)
assert(capture.session.functions.GetProfessionInfo[1][1].v[1] == "Alchemy")
print("PASS: QuestieTrace read-only skill queries, raw tuples and optional API interfaces.")
