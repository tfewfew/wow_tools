WoWTools.prr.RegisterSource(function(...)
local _, ns = ...
local Text = ns.Localization.Text
local Sources = {}
ns.RecipeSources = Sources
local names = {}

function Sources.TrainerName(npcID)
    if names[npcID] then return names[npcID] end
    local trainer = ns.Database.Trainers[npcID]
    local name = trainer and trainer.name or ("NPC " .. npcID)
    local language = ns.db.settings.language
    local chinese = language == "zh" or (language == "auto" and ns.Localization.ClientLanguage() == "zh")
    local provider = LibQuestieDB and LibQuestieDB.Npc
    if chinese and provider and type(provider.Get) == "function" then
        local ok, translated = pcall(provider.Get, npcID, "name")
        if ok and not (issecretvalue and issecretvalue(translated)) and type(translated) == "string"
            and translated:find("[\228-\233][\128-\191][\128-\191]") then
            name = translated
        end
    end
    names[npcID] = name
    return name
end

function Sources.Summary(recipe)
    local details = recipe.details or ns.Database.RecipeDetails[recipe.spellID]
    local trainers = details and details.trainers
    if not trainers then return nil end
    local first = trainers[1]
    local name = Sources.TrainerName(first.npcID)
    if first.reference then name = name .. Text("tooltip.reference_mark") end
    local summary = Text("tooltip.trainer", name)
    if #trainers > 1 then summary = summary .. Text("tooltip.other_trainers", #trainers - 1) end
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
    local observed, reference = {}, {}
    for _, source in ipairs(trainers) do
        local name = Sources.TrainerName(source.npcID)
        local trainer = ns.Database.Trainers[source.npcID]
        local map = trainer and trainer.mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(trainer.mapID)
        if map and map.name then
            name = name .. " (" .. map.name .. string.format(" %.1f, %.1f)", trainer.x * 100, trainer.y * 100)
        end
        local group = source.reference and reference or observed
        group[#group + 1] = name
    end
    if #observed > 0 then
        tooltip:AddLine(Text("tooltip.trainers_forever", table.concat(observed, ", ")), 0.7, 0.9, 0.7, true)
    end
    if #reference > 0 then
        tooltip:AddLine(Text("tooltip.trainers_reference", table.concat(reference, ", ")), 1, 0.82, 0.2, true)
    end
    if #reference > 0 and details.referenceTrainerTotal then
        tooltip:AddLine(Text("tooltip.trainer_reference_count", details.referenceTrainerTotal,
            details.referenceTrainerListed), 0.6, 0.6, 0.6, true)
    end
end
end)
