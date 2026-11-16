WoWTools.prr.RegisterSource(function(...)
-- addons.lua -- the author's addons, for the "Other addons" page. Part of the
-- shared/other_addons module: the same list in every addon of the author; each
-- page leaves out the addon it is in.
--
-- A new addon -- a line here and its texts (notes.<id>, features.<id>) in
-- lang/en.lua and lang/ru.lua of this module, in every addon.
--
-- folder -- the folder in Interface\AddOns (tells whether it is installed);
-- title  -- the name players know it by (a name: not translated);
-- picture -- its CurseForge icon, carried by this module: icons/<picture>.tga
--           (scripts/other_addons_icons.py makes them; an addon that is not
--           installed has no files in the game, so the module brings its own);
-- icon    -- a picture of the game, for an addon without a CurseForge icon yet.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}

ns.OtherAddons.list = {
    {
        id = "purple_note",
        folder = "PurpleNote",
        title = "PurpleNote",
        picture = "purple_note",
    },
    {
        id = "prr",
        folder = "PRR",
        title = "PRR: Professions, Recipes, Reagents",
        picture = "prr",
    },
    {
        id = "loot_buddy",
        folder = "LootBuddy",
        title = "Loot Buddy",
        picture = "loot_buddy",
    },
    {
        id = "target_it",
        folder = "TargetIt",
        title = "TargetIt (NPC targeter and finder)",
        picture = "target_it",
    },
    {
        id = "simple_buff_tracker",
        folder = "SimpleBuffTracker",
        title = "Simple Buff Tracker",
        picture = "simple_buff_tracker",
    },
}
end)
