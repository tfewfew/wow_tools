-- Verify the generated PRR correction data through its normal indexed lookup.
local root = TEST_ROOT or "."
local addon = root .. "/addon/forerver/wow_tools/prr/"
local ns = {
    Database = {}, Constants = {HIDDEN_PROFESSIONS = {}},
    db = {scanned = {}, fixes = {}, settings = {developer = true}},
}
WoWTools = {prr = {RegisterSource = function(initialize) initialize("wow_tools", ns) end}}
for _, relative in ipairs({"libs/json/json.lua", "database/recipes.lua", "database/fixes.lua",
    "database/recipe_details.lua", "dataflows/recipe_index.lua", "dataflows/skill_planner.lua"}) do
    dofile(addon .. relative)
end
local file = assert(io.open(addon .. "RECIPE-SOURCES.json", "r"))
local provenance = ns.json.decode(file:read("*a"))
file:close()
local index = ns.Dataflows.RecipeIndex
local calibration = ns.Database.RecipeCalibration
ns.Database.RecipeCalibration = {}
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
for _, review in ipairs(provenance.learningVerification.questionMarkReview.records) do
    if review.status == "verified" and review.yellow and review.requirement.skill > review.yellow then
        confirmed[review.spellID] = true
    end
end
for _, recipe in ipairs(index.AllRecipes()) do
    if recipe.skill and recipe.yellow and recipe.skill > recipe.yellow then
        assert(confirmed[recipe.spellID], "Unverified learning requirement still exceeds the yellow threshold")
    end
end
assert(index.Get(2665).skill == 40 and index.Get(2674).skill == 100,
    "Observed Forever sharpening-stone ranks did not override the old base values")
assert(index.Get(3861).skill == 150 and index.Get(9954).skill == 200,
    "Observed and documented Forever skill supplements did not reach the index")
assert(index.Get(9273).skill == 165 and index.Get(9273).yellow == 160,
    "A verified recipe-item requirement was clamped to the yellow threshold")

local verification = assert(provenance.learningVerification)
local coverage = provenance.coverage.learningVerification
local factionNames = {A = "Alliance", H = "Horde", AH = "Neutral"}
local factionCounts = {Alliance = 0, Horde = 0, Neutral = 0}
for npcID, trainer in pairs(ns.Database.Trainers) do
    local expected = factionNames[verification.trainerFactions.records[tostring(npcID)]]
    assert(expected and trainer.faction == expected, "A learning location lacks its reviewed trainer faction")
    factionCounts[expected] = factionCounts[expected] + 1
end
for faction, count in pairs(factionCounts) do
    assert(count == provenance.coverage.trainerFactions[faction], "Trainer faction coverage differs from the data")
end
assert(ns.Database.Trainers[11097].faction == "Alliance" and ns.Database.Trainers[11098].faction == "Horde"
    and ns.Database.Trainers[11557].faction == "Neutral",
    "Faction-specific master trainers or the neutral reputation trainer were classified incorrectly")
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

local questionReview = assert(verification.questionMarkReview)
assert(questionReview.baseline == "c16642dcfafc1b4457239c09e50009fc1cef233a"
    and questionReview.clientBuild == "1.60.1.70938")
local questionSkills, questionCount, questionVerified = {}, 0, 0
for _, record in ipairs(questionReview.records) do
    assert(not questionSkills[record.spellID], "Duplicate question-mark review")
    questionSkills[record.spellID] = true
    questionCount = questionCount + 1
    local recipe = assert(index.Get(record.spellID))
    assert(recipe.profession == record.profession and recipe.item == record.itemID
        and recipe.yellow == record.yellow and recipe.gray == record.gray,
        "Question-mark review changed recipe identity or native thresholds")
    assert(record.checks and record.reason and record.checks.exactSpellSearch,
        "An individual unknown requirement lacks its source review")
    if record.status == "verified" then
        questionVerified = questionVerified + 1
        local requirement = assert(record.requirement)
        assert(recipe.skill == requirement.skill and not recipe.skillReference,
            "A reviewed requirement did not reach the normal lookup")
        for _, sourceID in ipairs(requirement.sourceIDs) do
            assert(questionReview.sources[sourceID].url, "Missing reviewed source")
        end
        local teachers = {}
        for _, source in ipairs(recipe.details.trainers or {}) do teachers[source.npcID] = true end
        for _, npcID in ipairs(requirement.trainerNPCIDs) do
            assert(teachers[npcID] and ns.Database.Trainers[npcID].mapID,
                "A reviewed teacher lacks its learning location")
        end
    else
        assert(record.status == "unresolved" and not recipe.skill and not record.requirement,
            "An unresolved class gate, old schematic or ambiguous recipe was assigned a guessed rank")
    end
end
for _, spellID in ipairs(questionReview.targetSpellIDs) do
    assert(questionSkills[spellID], "A baseline question-mark recipe was omitted")
end
for _, recipe in ipairs(index.AllRecipes()) do
    if not recipe.skill then assert(questionSkills[recipe.spellID], "An unknown recipe escaped review") end
end
assert(questionCount == 198 and questionCount == coverage.questionMarksChecked
    and questionVerified == coverage.questionMarksVerified)
assert(index.Get(12052).skill == 175 and index.Get(12072).skill == 190
    and index.Get(12088).skill == 200 and index.Get(18402).skill == 210
    and index.Get(1249634).skill == 120 and index.Get(1293088).skill == 125,
    "Current documented requirements were replaced by stale Quick Facts or yellow fallbacks")
assert(index.Get(10619).skill == 225 and index.Get(10619).yellow == 220
    and index.Get(10630).skill == 230 and index.Get(10630).yellow == 225
    and index.Get(24655).skill == 280 and index.Get(24655).yellow == 275,
    "Documented specialization requirements were clamped to yellow")
local battery = assert(index.TaughtBy(274049)[1])
assert(battery.spellID == 1293088 and battery.skill == 125 and battery.recipeItemBound,
    "The verified battery schematic is missing from normal recipe-item lookups")
local batteryBase = ns.Database.Recipes[1293088]
batteryBase.recipeItem, batteryBase.recipeItemBound = 12345, false
index.Invalidate()
assert(index.Get(1293088).recipeItem == 12345 and index.Get(1293088).recipeItemBound == false,
    "A generated teaching item overwrote an existing recipe item or explicit unbound flag")
batteryBase.recipeItem, batteryBase.recipeItemBound = nil, nil
index.Invalidate()
assert(index.TaughtBy(274049)[1].spellID == 1293088,
    "The reviewed teaching item was not restored after clearing base data")

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

local current = provenance.skillCalibration
local equal = current.previousLearnEqualsYellow
local reviewed = {}
for _, group in pairs(equal) do
    for _, spellID in ipairs(group) do
        local recipe = index.Get(spellID)
        assert(not reviewed[spellID] and recipe.skill and recipe.skill == recipe.yellow,
            "A recipe with equal learning and yellow ranks was misclassified")
        reviewed[spellID] = true
    end
end
local total = 0
for _, recipe in ipairs(index.AllRecipes()) do
    total = total + 1
    if recipe.skill and recipe.skill == recipe.yellow then
        assert(reviewed[recipe.spellID], "A prior equal-rank recipe was omitted from the calibration")
    end
end
assert(total == current.recipesChecked, "PRR calibration omitted recipes")

ns.Database.RecipeCalibration = calibration
index.Invalidate()
local learningChanges, thresholdChanges = 0, 0
for _, change in ipairs(current.changes) do
    local recipe = index.Get(change.spellID)
    local fields = change.corrected
    if fields.skill then
        assert(recipe.skill == fields.skill, "Calibrated learning rank did not reach the index")
        learningChanges = learningChanges + 1
    end
    if fields.yellow then
        assert((recipe.yellow or 0) == fields.yellow and (recipe.gray or 0) == fields.gray,
            "Calibrated skill-up thresholds did not reach the index")
        thresholdChanges = thresholdChanges + 1
    end
end
assert(learningChanges == current.learningRanksChanged and thresholdChanges == current.thresholdsChanged,
    "PRR calibration coverage differs from its changes")
assert(index.Get(2167).skill == 75 and index.Get(2167).yellow == 100,
    "Gray Leather Boots still uses the yellow threshold as the learning requirement")
assert(index.Get(2665).skill == 40 and index.Get(2665).yellow == 40
    and index.Get(3326).skill == 50 and index.Get(3326).gray == 90,
    "Verified equal learning and yellow ranks were lost")
assert(index.Get(1263031).skill == 125 and index.Get(1263031).yellow == 125 and index.Get(1263031).gray == 130,
    "Tanning Rack did not apply the documented server hotfix")
local campfire = index.Get(1283400)
local chance = ns.Dataflows.SkillPlanner.Chance
assert(campfire.yellow == campfire.gray and chance(campfire, campfire.skill, true) == 1
    and chance(campfire, campfire.gray, true) == nil,
    "A recipe that moves directly from orange to gray lost its orange range")
assert(index.Get(9957).skill == 205 and index.TaughtBy(7994)[1].spellID == 9957,
    "The current Orcish War Leggings plans did not reach the recipe item index")
assert(index.FixOf(3170).skill == 15 and index.Get(3170).skill == 15,
    "A stale built-in fix masked the trainer's calibrated requirement")
ns.db.fixes[3170] = {skill = 17}
index.Invalidate()
assert(index.Get(3170).skill == 17, "A calibrated built-in fix took precedence over a user correction")
print("PASS: PRR learning audits, calibrated client thresholds, recipe item indexing and user-fix precedence.")
