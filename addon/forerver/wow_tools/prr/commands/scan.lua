WoWTools.prr.RegisterSource(function(...)
-- scan.lua -- developer commands that read recipes from the client to build
-- the base (scripts/build_database.py bakes the results into database/recipes.lua,
-- players never need them; they are not in the /prr help list):
--   /prr scan               -- every recipe of the base (fresh reagents from the client)
--   /prr scan full          -- every spell id range where recipes live (ns.Config.FULL_SCAN_RANGES)
--   /prr scan <from> <to>   -- a range of spell ids: recipes the base does not know
--   /prr scan stop
--   /prr status             -- how many recipes are known

local ADDON, ns = ...

local Text = ns.Localization.Text
local RecipeIndex = ns.Dataflows.RecipeIndex
local RecipeScan = ns.Services.RecipeScan

ns.Commands.Add("scan", {
    run = function(arguments)
        if arguments == "stop" then
            RecipeScan.Stop()
            return
        end

        if arguments == "full" then
            RecipeScan.Start({ ranges = ns.Config.FULL_SCAN_RANGES })
            return
        end

        local first, last = arguments:match("^(%d+)%s+(%d+)$")
        if first then
            RecipeScan.Start({ ranges = { { tonumber(first), tonumber(last) } } })
            return
        end

        local spellIDs = RecipeIndex.All()
        RecipeScan.Start({ spellIDs = spellIDs })
    end,
    helpKey = "commands.scan.help",
    developer = true,
})

ns.Commands.Add("status", {
    run = function()
        local spellIDs, withReagents = RecipeIndex.All()
        local scanned = 0
        for _ in pairs(ns.db.scanned) do
            scanned = scanned + 1
        end
        ns.Utilities.Print(Text("commands.status.text", #spellIDs, withReagents, scanned))
    end,
    helpKey = "commands.status.help",
    developer = true,
})
end)
