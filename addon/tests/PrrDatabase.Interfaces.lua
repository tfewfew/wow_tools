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

local verification = assert(provenance.learningVerification)
local coverage = provenance.coverage.learningVerification
local evidenceFile = assert(io.open(root .. "/" .. verification.evidenceFile, "r"))
local evidence = ns.json.decode(evidenceFile:read("*a"))
evidenceFile:close()
assert(#verification.unknownSkills == #evidence.targets.unknownSkills
    and #verification.unknownSkills == coverage.unknownSkillsChecked,
    "The learning audit omitted a previously unknown requirement")
local auditedSkills, verifiedSkills = {}, 0
for _, record in ipairs(verification.unknownSkills) do
    local recipe = assert(index.Get(record.spellID))
    assert(not auditedSkills[record.spellID], "Duplicate unknown-skill audit record")
    auditedSkills[record.spellID] = true
    if record.status == "verified" then
        verifiedSkills = verifiedSkills + 1
        assert(recipe.skill == record.skill and not recipe.skillReference,
            "A verified requirement did not reach the normal indexed lookup")
    else
        assert(record.status == "unresolved" and not recipe.skill,
            "A missing trainer rank or absent teaching item was replaced with a guess")
    end
end
for _, spellID in ipairs(evidence.targets.unknownSkills) do
    assert(auditedSkills[spellID], "An unknown-skill audit target is missing")
end
assert(verifiedSkills == coverage.skillsVerified)
assert(index.Get(1249631).skill == 120 and index.Get(1249632).skill == 215
    and index.Get(8681).skill == 1, "Verified dye and automatic poison requirements are missing")
assert(not index.Get(818).skill, "A historical beta trainer rank was asserted as a current requirement")

local checkedPairs, verifiedPairs, rejectedPairs, checkedRecipes = 0, 0, 0, 0
for _, record in ipairs(verification.referenceTrainers) do
    checkedRecipes = checkedRecipes + 1
    local expected = assert(evidence.targets.referenceTrainers[tostring(record.spellID)])
    local sources, checked = {}, {}
    local details = index.Get(record.spellID).details
    for _, source in ipairs(details and details.trainers or {}) do sources[source.npcID] = source end
    for _, key in ipairs({"verifiedDocumentationNPCIDs", "verifiedBetaNPCIDs", "rejectedCrossExpansionNPCIDs"}) do
        for _, npcID in ipairs(record[key]) do
            assert(not checked[npcID], "A reference trainer has multiple audit dispositions")
            checked[npcID] = true
            checkedPairs = checkedPairs + 1
            local source = sources[npcID]
            if key == "rejectedCrossExpansionNPCIDs" then
                rejectedPairs = rejectedPairs + 1
                assert(not source, "An unverified cross-expansion trainer is still offered as a learning location")
            else
                verifiedPairs = verifiedPairs + 1
                assert(source and not source.reference and ns.Database.Trainers[npcID].mapID,
                    "A verified trainer relationship lacks its Forever location")
            end
        end
    end
    for _, npcID in ipairs(expected) do assert(checked[npcID], "An individual reference pair was not audited") end
end
assert(checkedPairs == coverage.referencePairsChecked and verifiedPairs == coverage.referencePairsVerified
    and rejectedPairs == coverage.rejectedReferencePairs and coverage.remainingReferencePairs == 0
    and checkedRecipes == coverage.referenceRecipesChecked,
    "Reference trainer audit coverage does not match its individual records")
for _, capture in ipairs(verification.localTrainerCaptures.records) do
    assert(capture.build == "1.60.1:70938" and capture.trainerObserved
        and index.Get(capture.spellID).skill == capture.skill,
        "Current-client trainer skill requirements did not reach the indexed recipes")
end
for _, review in ipairs(verification.recipeTrainerReviews.recipes) do
    local sources = {}
    for _, source in ipairs(index.Get(review.spellID).details.trainers) do sources[source.npcID] = true end
    for _, npcID in ipairs(review.trainerNPCIDs) do
        assert(sources[npcID], "A recipe-specific reviewed teacher is missing")
    end
end
local rugged = assert(index.CraftedBy(8170)[1])
assert(rugged.spellID == 22331 and rugged.profession == 165 and rugged.skill == 225
    and rugged.yellow == 225 and rugged.gray == 225 and rugged.reagents[1][1] == 4304
    and rugged.reagents[1][2] == 6, "Rugged Leather must use its current-client learning requirement")
assert(#rugged.details.trainers == 2 and rugged.details.trainers[1].npcID == 11097
    and rugged.details.trainers[2].npcID == 11098,
    "Rugged Leather still uses the generic Wrath/Cataclysm trainer list")
for _, recipe in ipairs(index.AllRecipes()) do
    for _, source in ipairs(recipe.details and recipe.details.trainers or {}) do
        assert(not source.reference, "Unverified imported teachers remain in the runtime database")
    end
end

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
print("PASS: PRR exhaustive learning audit, client thresholds, indexed corrections and user-fix precedence.")
