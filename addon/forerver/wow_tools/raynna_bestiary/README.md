# Raynna's Bestiary

A standalone WoW Forever reference browser. Alt-hover a monster for possible
items, or Alt-hover an inventory item for monster, vendor and quest sources.
Known drop chances sort first; monster sources include levels and zones when known.
Quest items and associated quests are marked where reference data provides them.

## Install and use

Extract `RaynnaBestiary` into `Interface/AddOns`. Restart the game when first
installing a new addon folder. Tracker, Talent Guide, QuestieDB and GearQuest are
not required. Use `/rb`, `/rb hide`, or `/rb settings`.

Settings are under Escape > Settings > AddOns > Raynna's mods > Bestiary.
Preferences and recent portrait IDs save per character in `RaynnaBestiaryDB`.
On first load, Bestiary copies its preferences from available Tracker/legacy data;
existing standalone preferences take priority, and Tracker history is untouched.

Hold Alt or hover the panel to retain it, or use Pin. Release Alt and leave the
panel to dismiss. An inventory selection stays locked during an Alt press so you
can move into its list and scroll. Release and press Alt for another selection.

Tracker 1.18.0 or newer detects the standalone Bestiary and delegates its Bestiary
button instead of creating a duplicate panel. Older combined Tracker versions
should be updated before enabling both. Bestiary still works with Tracker absent.

## Data and portraits

Bundled Classic data is supplemented with metadata and a partial Forever snapshot.
A supported newer QuestieDB can supplement metadata but is optional. Percentages
are sourced reference figures, not guaranteed server rates or your personal loot.
Unknown data remains unknown. See `RaynnaBestiary/REFERENCE-SOURCES.txt` and the
bundled license notices for sources, coverage and terms.

Recently viewed monster IDs are saved for background portrait preloading after
reload. Rendered textures cannot persist across reload; a safety delay avoids
showing unfinished renders. Missing verified display IDs still show `?`.

## Development

Install `lupa` and run `python tests/test_bestiary.py` for mocked-runtime checks.
Run `python tools/package_release.py` to build the player-only CurseForge ZIP.
Generators are in `tools`; input versions and licenses are documented in the
source notices. Tests do not replace in-game visual verification.
# NPC browser (1.1.0)

`/rb` and Tracker's Bestiary button open a searchable NPC chooser. Search by name
or ID, switch between All, Tracked, Recent and Target, then click an NPC to view
its drops beside the chooser. The chooser stays open so you can switch NPCs.
Tracked entries are supplied through Tracker's optional integration; no Tracker
installation is required for the other views. Browse on a detail panel returns
to the chooser; `/rb hide` closes both windows. `/rb demo` remains an explicit demo.
Browser position is saved per character and it follows Bestiary's scale setting.
