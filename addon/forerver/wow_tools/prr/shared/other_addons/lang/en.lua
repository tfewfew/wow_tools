WoWTools.prr.RegisterSource(function(...)
-- en.lua -- the texts of the "Other addons" page, English. Part of the
-- shared/other_addons module: copied with it into every addon of the author.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
ns.OtherAddons.texts = ns.OtherAddons.texts or {}

ns.OtherAddons.texts.en = {
    language_name = "English",
    language = "Language",
    title = "Other Addons",
    subtitle = "More addons for WoW Forever. Installed: %d of %d.",
    footer = "Copy a name and search for it on CurseForge.",
    copy = "Copy Name",
    copy_hint = "Ctrl+C to copy",
    copy_tooltip = "Click, then press Ctrl+C to copy the name.",
    copied = "Copied!",
    state = {
        loaded = "Installed",
        disabled = "Installed, turned off",
        missing = "Not installed",
    },
    -- one line on what the addon is
    notes = {
        purple_note = "Notes on the players you meet: see them on nameplates, in tooltips and in chat.",
        prr = "What crafts an item and what it is a reagent for: in tooltips and in a recipe window.",
        loot_buddy = "Loot notifications, a searchable loot history and Auto Loot filters.",
        target_it = "Action-bar buttons that target the nearest living NPC you picked: quest mobs first.",
        simple_buff_tracker = "Your buffs on one icon panel: all with timers or only the missing ones. A click puts a buff back.",
    },
    -- its features, one point each
    features = {
        purple_note = {
            "Write a note on anyone in one click, from ready-made notes or your own",
            "See your notes above nameplates, in chat and in tooltips",
            "A reminder with a sound when a noted player shows up nearby",
            "A window of the players around you and a searchable history of every meeting",
            "Share notes with your guild",
            "Every note is signed and dated: several of your characters can each keep their own",
        },
        prr = {
            "\"Crafted by\" and \"Reagent for\" in every item tooltip",
            "A recipe window: Alt+click any item, follow the chain of reagents, keep favorites",
            "Craft planner: auction house prices, profit and the cheapest way to level a profession",
            "About 2,500 recipes of WoW Forever built in, nothing to scan",
            "The interface in 8 languages, the names of items and recipes from your game client",
        },
        loot_buddy = {
            "Animated loot notifications in the colors of item quality",
            "A history of every item looted: when, where and from what; search and filters",
            "Auto Loot filters: leave junk behind by quality, merchant price, name or mask",
            "Middle-click an item in your bags to block it from Auto Loot",
            "A bag tracker: your own groups of items with their counts on the screen",
            "Loot Journey: replay your loot on the zone map, item by item",
        },
        target_it = {
            "Buttons in the action bar style: a click targets the nearest living NPC you picked",
            "Your quest mobs and quest givers come first; search over 10,000 NPCs",
            "A raid mark on the target, a key for every button",
            "Alt+click: a waypoint to the nearest spawn",
            "Learns the new NPCs of Forever as you see them",
        },
        simple_buff_tracker = {
            "Your buffs on one panel of action bar style icons: with timers or only the missing ones",
            "A left-click puts a buff back: casts the spell, eats food for Well Fed, applies weapon oil",
            "Weapon enchants too, even an oil and Flametongue on one weapon",
            "A glow on missing buffs, three icon styles, any size and growth direction",
            "Right-click a buff on the panel to open its settings",
        },
    },
}
end)
