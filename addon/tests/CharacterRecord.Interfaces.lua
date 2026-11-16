-- Check the production skill sampler against each client's native return shapes.
local root = TEST_ROOT or "."
local flavor = assert(TEST_FLAVOR)
local frame = {}
local env = setmetatable({
    CreateFrame = function(kind) assert(kind == "Frame"); return frame end,
}, { __index = _G })
function frame:RegisterEvent() end
function frame:SetScript(event, callback) self[event] = callback end
local chunk = assert(loadfile(root .. "/addon/" .. flavor .. "/wow_tools/CharacterRecord.lua"))
setfenv(chunk, env)
chunk()

local function FindUpvalue(callback, target, visited)
    visited = visited or {}
    if visited[callback] then return end
    visited[callback] = true
    for index = 1, math.huge do
        local name, value = debug.getupvalue(callback, index)
        if not name then return end
        if name == target then return value end
        if type(value) == "function" then
            local found = FindUpvalue(value, target, visited)
            if found then return found end
        end
    end
end
local Skills = assert(FindUpvalue(frame.OnEvent, "CharacterSkills"))
local secret = {}
env.issecretvalue = function(value) return rawequal(value, secret) end
local loaded, queries = 8, 0
local records = {
    [171] = { skillID = 171, name = "Alchemy", rank = 225, maxRank = 300 },
    [182] = { skillID = 182, name = "Herbalism", rank = 200, maxRank = 300 },
    [185] = { skillID = 185, name = "Cooking", rank = 100, maxRank = 150 },
    [356] = { skillID = 356, name = "Fishing", rank = 175, maxRank = 225 },
    [794] = { skillID = 794, name = "Archaeology", rank = 0, maxRank = 0 },
}
env.C_SkillInfo = {
    GetNumSkillLines = function() return loaded end,
    GetSkillLineInfoByID = function(id) queries = queries + 1; return records[id] end,
    GetSkillLineInfo = function() error("ID lookup must be independent of visible skill rows") end,
    ExpandSkillHeader = function() error("ID lookup must not change skill headers") end,
    CollapseSkillHeader = function() error("ID lookup must not change skill headers") end,
}
env.GetProfessions = function() error("Native skill APIs take precedence over profession stubs") end
local primary, secondary = Skills()
assert(primary == "171|Alchemy|225|300;182|Herbalism|200|300", primary)
assert(secondary == "185|Cooking|100|150;356|Fishing|175|225", secondary)
loaded, queries = 0, 0
primary, secondary = Skills()
assert(primary == "?" and secondary == "?" and queries == 0)
loaded = 8
records[171] = secret
primary, secondary = Skills()
assert(primary == "?" and secondary == "185|Cooking|100|150;356|Fishing|175|225")
records[171], records[182], records[185], records[356] = nil, nil, nil, nil
primary, secondary = Skills()
assert(primary == "" and secondary == "")
records[356] = { name = "Fishing", rank = 0, maxRank = 75 }
primary, secondary = Skills()
assert(primary == "" and secondary == "356|Fishing|0|75")

-- Visible rows can expose a different internal ID for a recognized skill name.
env.C_SkillInfo.GetSkillLineInfoByID = nil
env.C_SkillInfo.GetNumSkillLines = function() return 1 end
env.C_SkillInfo.GetSkillLineInfo = function()
    return { skillID = 900001, name = "Fishing", rank = 125, maxRank = 150, isHeader = false, isCollapsed = false }
end
primary, secondary = Skills()
assert(primary == "" and secondary == "356|Fishing|125|150")

-- Titan's global tuple API remains available when the namespace is absent.
env.C_SkillInfo = false
env.GetNumSkillLines = function() return 2 end
env.GetSkillLineInfo = function(index)
    if index == 1 then return "Mining", false, false, 200, 0, 0, 300 end
    return "Fishing", false, false, 125, 0, 0, 150
end
primary, secondary = Skills()
assert(primary == "186|Mining|200|300" and secondary == "356|Fishing|125|150")
print("PASS: " .. flavor .. " character skill ID/tuple contracts, unloaded data, unlearned skills and restricted values.")
