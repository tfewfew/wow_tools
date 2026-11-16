WoWTools.prr.RegisterSource(function(...)
-- core.lua -- initialization: settings from SavedVariables.
-- Called from events/addon_loaded.lua; before that ns.db == nil.

local ADDON, ns = ...

ns.Core = {}

function ns.Core.Init()
    local settings = ns.GetSettings()
    settings.db = ns.Utilities.Defaults(settings.db, ns.Config.defaults)
    ns.db = settings.db
    ns.Localization.SetLanguage(ns.db.settings.language)
end

-- Reads quietly the recipes whose reagents the base does not know yet
-- (recipes added by Forever), so tooltips get them without any command.
function ns.Core.ScanMissingReagents()
    local spellIDs = ns.Dataflows.RecipeIndex.MissingReagents()
    if #spellIDs > 0 then
        ns.Services.RecipeScan.Start({ spellIDs = spellIDs, quiet = true })
    end
end
end)
