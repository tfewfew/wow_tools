-- Verify the generated PRR correction data through its normal indexed lookup.
local root = TEST_ROOT or "."
local addon = root .. "/addon/forerver/wow_tools/prr/"
local ns = {
    Database = {}, Constants = {HIDDEN_PROFESSIONS = {}},
    db = {scanned = {}, fixes = {}, settings = {developer = true}},
}
WoWTools = {prr = {RegisterSource = function(initialize) initialize("wow_tools", ns) end}}
for _, relative in ipairs({"libs/json/json.lua", "database/recipes.lua", "database/fixes.lua",
    "database/recipe_details.lua", "dataflows/recipe_index.lua"}) do
    dofile(addon .. relative)
end
local file = assert(io.open(addon .. "RECIPE-SOURCES.json", "r"))
local provenance = ns.json.decode(file:read("*a"))
file:close()
local index = ns.Dataflows.RecipeIndex
local confirmed, statuses = {}, {corrected = 0, rejectedReference = 0, confirmedLearnAboveYellow = 0}
for _, record in ipairs(provenance.skillAudit) do
    local recipe = assert(index.Get(record.spellID), "Audited recipe missing from the PRR index")
    assert(recipe.yellow == record.yellow and recipe.gray == record.gray,
        "PRR correction changed the independently verified client skill-up thresholds")
    assert(record.previousSkill > record.yellow, "Audit contains a recipe outside the reviewed conflict set")
    if record.status == "rejectedReference" then
        assert(not recipe.skill and not recipe.skillReference,
            "Unconfirmed borrowed learning requirements must retain the unknown representation")
    else
        assert(recipe.skill == record.skill and not recipe.skillReference,
            "Verified learning requirement did not reach the normal indexed lookup")
        if record.status == "confirmedLearnAboveYellow" then confirmed[record.spellID] = true end
    end
    statuses[record.status] = assert(statuses[record.status], "Unknown skill-audit disposition") + 1
end
for status, count in pairs(statuses) do
    assert(count == provenance.coverage.skillAudit[status], "Skill-audit coverage does not match its records")
end
for _, recipe in ipairs(index.AllRecipes()) do
    if recipe.skill and recipe.yellow and recipe.skill > recipe.yellow then
        assert(confirmed[recipe.spellID], "Unverified learning requirement still exceeds the yellow threshold")
    end
end
assert(index.Get(2665).skill == 40 and index.Get(2674).skill == 100,
    "Observed Forever sharpening-stone ranks did not override the old base values")
assert(index.Get(3861).skill == 150 and not index.Get(9954).skill,
    "Observed and unconfirmed Forever skill supplements are not distinguished")
assert(index.Get(9273).skill == 165 and index.Get(9273).yellow == 160,
    "A verified recipe-item requirement was clamped to the yellow threshold")

ns.db.fixes[2665] = {skill = 55}
index.Invalidate()
assert(index.Get(2665).skill == 55, "Explicit user corrections must keep priority over generated data")
ns.db.fixes[2665] = {skillUnknown = true}
index.Invalidate()
assert(not index.Get(2665).skill and index.Get(2665).skillUnknown,
    "Generated data overwrote an explicitly unknown user correction")
ns.db.fixes[2665] = nil
ns.Database.Fixes[2665] = {skill = 45}
index.Invalidate()
assert(index.Get(2665).skill == 45, "Built-in PRR fixes must keep their existing priority")
ns.Database.Fixes[2665] = nil
index.Invalidate()
assert(index.Get(2665).skill == 40, "Cleared hand fixes did not restore the corrected source data")
print("PASS: PRR generated skill audit, client thresholds, indexed corrections and user-fix precedence.")
