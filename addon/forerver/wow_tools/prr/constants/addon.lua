WoWTools.prr.RegisterSource(function(...)
-- addon.lua -- the addon name as players see it. The folder and the .toc are
-- "PRR"; the interface shows the long title, chat messages -- the short one.

local ADDON, ns = ...
ns.Constants = ns.Constants or {}

ns.Constants.ADDON_TITLE = "PRR: Professions, Recipes, Reagents"
ns.Constants.ADDON_SHORT_TITLE = "PRR"
-- the gear that opens a settings page (white art, the same as in Loot Buddy)
ns.Constants.SETTINGS_ICON = "Interface\\AddOns\\" .. ADDON .. "\\prr\\textures\\icon_gear"
-- the button that opens the leveling plan: white art of steps going up
ns.Constants.PLANNER_ICON = "Interface\\AddOns\\" .. ADDON .. "\\prr\\textures\\icon_planner"

-- skill lines of the client that are not professions: their recipes are never
-- listed (an in-game scan can still bring them); scripts/build_database.py drops them too
ns.Constants.HIDDEN_PROFESSIONS = {
    [2933] = true,   -- Test Profession [DNT]
}
end)
