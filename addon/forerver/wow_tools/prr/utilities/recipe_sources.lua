WoWTools.prr.RegisterSource(function(...)
local _, ns = ...
local Text = ns.Localization.Text
local Sources = {}
ns.RecipeSources = Sources
local locations = {}

function Sources.TrainerLocation(npcID)
    if locations[npcID] then return locations[npcID] end
    local trainer = ns.Database.Trainers[npcID]
    local map = trainer and trainer.mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(trainer.mapID)
    local location
    if map and map.name then
        location = map.name
        if type(trainer.x) == "number" and type(trainer.y) == "number" then
            location = location .. string.format(" (%.1f, %.1f)", trainer.x * 100, trainer.y * 100)
        end
    end
    local provider = LibQuestieDB and LibQuestieDB.Npc
    if not location and provider and type(provider.Get) == "function" and C_Map and C_Map.GetAreaInfo then
        local ok, zoneID = pcall(provider.Get, npcID, "zoneID")
        if ok and not (issecretvalue and issecretvalue(zoneID)) and type(zoneID) == "number" and zoneID > 0 then
            location = C_Map.GetAreaInfo(zoneID)
        end
    end
    locations[npcID] = location or Text("tooltip.location_unknown")
    return locations[npcID]
end

local function learningLocations(trainers)
    local observed, reference, seen = {}, {}, {}
    local function add(group, source)
        local location = Sources.TrainerLocation(source.npcID)
        if not seen[location] then
            seen[location] = true
            group[#group + 1] = location
        end
    end
    for _, source in ipairs(trainers) do
        if not source.reference then add(observed, source) end
    end
    for _, source in ipairs(trainers) do
        if source.reference then add(reference, source) end
    end
    return observed, reference
end

function Sources.Summary(recipe)
    local details = recipe.details or ns.Database.RecipeDetails[recipe.spellID]
    local trainers = details and details.trainers
    if not trainers or #trainers == 0 then return nil end
    local observed, reference = learningLocations(trainers)
    local location = observed[1] or (reference[1] .. Text("tooltip.reference_mark"))
    local summary = Text("tooltip.learning_location", location)
    local otherLocations = #observed + #reference - 1
    if otherLocations > 0 then summary = summary .. Text("tooltip.other_locations", otherLocations) end
    return summary
end

function Sources.AddTooltip(tooltip, recipe)
    if recipe.skillReference then
        tooltip:AddLine(Text("tooltip.skill_reference"), 1, 0.82, 0.2, true)
    end
    local details = recipe.details or ns.Database.RecipeDetails[recipe.spellID]
    local trainers = details and details.trainers
    if not trainers then
        if details and details.autoTaught then
            tooltip:AddLine(Text("tooltip.auto_taught"), 0.7, 0.8, 0.7, true)
        elseif not recipe.recipeItem then
            tooltip:AddLine(Text("tooltip.source_unknown"), 0.6, 0.6, 0.6, true)
        end
        return
    end
    local observed, reference = learningLocations(trainers)
    if #observed > 0 then
        tooltip:AddLine(Text("tooltip.locations_forever", table.concat(observed, ", ")), 0.7, 0.9, 0.7, true)
    end
    if #reference > 0 then
        tooltip:AddLine(Text("tooltip.locations_reference", table.concat(reference, ", ")), 1, 0.82, 0.2, true)
    end
end
end)
