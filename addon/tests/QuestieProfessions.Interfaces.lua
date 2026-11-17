-- Check installed/staged Questie skill queries and native panel-close bindings.
local questieRoot = assert(TEST_QUESTIE_ROOT)
local flavor = assert(TEST_FLAVOR)
local modules = {
    QuestieCompat = {IsSpellKnown = function() return false end},
    QuestieQuest = {ResetAutoblacklistCategory = function(category) assert(category == "skill") end},
    Expansions = {Current = flavor == "titan" and 2 or 0, Wotlk = 2, MoP = 4},
    l10n = {translations = setmetatable({}, {__index = function(_, name) return {[name] = true} end})},
    QuestieCombatQueue = {Queue = function(_, callback) assert(type(callback) == "function") end},
    AvailableQuests = {CalculateAndDrawAll = function() end},
}
local env = setmetatable({
    Questie = {Debug = function() end, db = {profile = {townsfolkKnownProfessions = false}}},
    ERR_QUEST_ACCEPTED_S = "Accepted %s", ERR_QUEST_COMPLETE_S = "Completed %s",
}, {__index = _G})
env.QuestieLoader = {
    CreateModule = function(_, name)
        assert(not modules[name], "Questie module loaded twice")
        modules[name] = {}
        return modules[name]
    end,
    ImportModule = function(_, name)
        modules[name] = modules[name] or {}
        return modules[name]
    end,
}
local function Load(relative)
    local chunk = assert(loadfile(questieRoot .. "/" .. relative))
    setfenv(chunk, env)
    chunk()
end
local compat = modules.QuestieCompat
local count = 2
local secret = {}
env.issecretvalue = function(value) return rawequal(value, secret) end
compat.GetNumSkillLines = function() return count end
compat.ExpandAllSkillHeaders = function() error("ID queries changed the visible skill list") end
local records = {
    [171] = {name = "Alchemy", rank = 225, maxRank = 300},
    [356] = {name = "Fishing", rank = 0, maxRank = 75},
    [794] = {name = "Archaeology", rank = 0, maxRank = 0},
}
env.C_SkillInfo = {GetSkillLineInfoByID = function(id) return records[id] end}
Load("Modules/QuestieProfessions.lua")
local professions = modules.QuestieProfessions
professions:Init()
professions:Update()
local known = professions:GetPlayerProfessions()
assert(known[171][2] == 225 and known[356][2] == 0 and not known[794],
    "Questie native ID queries lost learned-zero or unlearned skill semantics")
count = 0
professions:Update()
assert(professions:GetPlayerProfessions() == known, "Unloaded skill data replaced the valid profession cache")
count, records[171] = 2, secret
professions:Update()
assert(professions:GetPlayerProfessions() == known, "Restricted skill data replaced the valid profession cache")

-- The legacy list changes its visible indices when a header is expanded.
env.C_SkillInfo = nil
local collapsed, secondaryCollapsed = true, false
local failRead, failExpand = false, false
local function Lines()
    local lines = {{"Professions", true, not collapsed}}
    if not collapsed then lines[#lines + 1] = {"Alchemy", false, false, 225} end
    lines[#lines + 1] = {"Secondary Skills", true, not secondaryCollapsed}
    if not secondaryCollapsed then lines[#lines + 1] = {"Fishing", false, false, 75} end
    return lines
end
env.GetSkillLineInfo = function(index) return unpack(assert(Lines()[index])) end
compat.GetNumSkillLines = function() return #Lines() end
compat.GetSkillLineInfo = function(index)
    if failRead then error("Unavailable skill row") end
    local name, header, _, rank = env.GetSkillLineInfo(index)
    return name, header, rank
end
compat.ExpandAllSkillHeaders = function()
    collapsed, secondaryCollapsed = false, false
    if failExpand then error("Partial expansion failure") end
end
env.CollapseSkillHeader = function(index)
    local name = env.GetSkillLineInfo(index)
    if name == "Professions" then collapsed = true
    elseif name == "Secondary Skills" then secondaryCollapsed = true
    else error("Collapse requires a native header index") end
end
professions:Update()
known = professions:GetPlayerProfessions()
assert(known[171][2] == 225 and known[356][2] == 75 and collapsed and not secondaryCollapsed,
    "Questie legacy collection failed to restore the original mixed header state")
failRead = true
professions:Update()
assert(professions:GetPlayerProfessions() == known and collapsed and not secondaryCollapsed,
    "Questie legacy read failure lost the header state or valid profession cache")
failRead, failExpand = false, true
professions:Update()
assert(professions:GetPlayerProfessions() == known and collapsed and not secondaryCollapsed,
    "Questie partial expansion failure lost the header state or valid profession cache")
failExpand = false

Load("Modules/EventHandler/EventHandler.lua")
local hookClose
for index = 1, math.huge do
    local name, value = debug.getupvalue(modules.EventHandler.RegisterLateEvents, index)
    if not name then break end
    if name == "HookSkillPanelClose" then hookClose = value end
end
assert(type(hookClose) == "function", "Questie close registration did not bind its native panel hook")
assert(not hookClose(), "An unloaded skill panel must wait for its native frame")
local callback, hooks, updates = nil, 0, 0
local panel = {HookScript = function(_, event, handler)
    assert(event == "OnHide" and type(handler) == "function")
    callback, hooks = handler, hooks + 1
end}
env[flavor == "forerver" and "SkillsFrame" or "SkillFrame"] = panel
assert(hookClose() and hookClose() and hooks == 1,
    "Questie must bind the client-native panel once")
local originalUpdate = professions.Update
professions.Update = function(self)
    updates = updates + 1
    return originalUpdate(self)
end
callback(panel)
assert(updates == 1 and collapsed and not secondaryCollapsed,
    "Questie native panel-close callback did not bind one profession refresh")
local file = assert(io.open(questieRoot .. "/Modules/EventHandler/EventHandler.lua", "r"))
local source = file:read("*a")
file:close()
assert(not source:find('RegisterEvent("CHAT_MSG_SKILL"', 1, true)
    and not source:find('RegisterBucketEvent("CHAT_MSG_SKILL"', 1, true)
    and not source:find('RegisterEvent("SKILL_LINES_CHANGED"', 1, true)
    and not source:find('RegisterBucketEvent("SKILL_LINES_CHANGED"', 1, true),
    "Questie retained skill-event-triggered background profession refreshes")
print("PASS: " .. flavor .. " Questie native skill queries, cache validity, header restoration and panel-close interfaces.")
