WoWTools.prr.RegisterSource(function(...)
-- de.lua -- the texts of the "Other addons" page, German. Part of the
-- shared/other_addons module: copied with it into every addon of the author.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
ns.OtherAddons.texts = ns.OtherAddons.texts or {}

ns.OtherAddons.texts.de = {
    language_name = "Deutsch",
    language = "Sprache",
    title = "Weitere Addons",
    subtitle = "Mehr Addons für WoW Forever. Installiert: %d von %d.",
    footer = "Kopiere einen Namen und suche ihn auf CurseForge.",
    copy = "Namen kopieren",
    copy_hint = "Strg+C zum Kopieren",
    copy_tooltip = "Klicken, dann Strg+C drücken, um den Namen zu kopieren.",
    copied = "Kopiert!",
    state = {
        loaded = "Installiert",
        disabled = "Installiert, deaktiviert",
        missing = "Nicht installiert",
    },
    -- one line on what the addon is
    notes = {
        purple_note = "Notizen zu den Spielern, die du triffst: an Namensplaketten, in Tooltips und im Chat.",
        prr = "Was einen Gegenstand herstellt und wofür er ein Reagenz ist: in Tooltips und in einem Rezeptfenster.",
        loot_buddy = "Beute-Benachrichtigungen, ein durchsuchbarer Beuteverlauf und Filter für automatisches Plündern.",
        target_it = "Aktionsleisten-Knöpfe, die den nächsten lebenden NPC deiner Wahl anvisieren: Questgegner zuerst.",
        simple_buff_tracker = "Deine Buffs auf einer Symbolleiste: alle mit Timern oder nur die fehlenden. Ein Klick erneuert einen Buff.",
    },
    -- its features, one point each
    features = {
        purple_note = {
            "Eine Notiz zu jedem Spieler mit einem Klick: fertige Notizen oder eigener Text",
            "Deine Notizen über Namensplaketten, im Chat und in Tooltips",
            "Eine Erinnerung mit Ton, wenn ein markierter Spieler in der Nähe auftaucht",
            "Ein Fenster der Spieler um dich und ein durchsuchbarer Verlauf aller Begegnungen",
            "Notizen mit deiner Gilde teilen",
            "Jede Notiz ist signiert und datiert: jeder deiner Charaktere kann seine eigene haben",
        },
        prr = {
            "\"Hergestellt von\" und \"Reagenz für\" in jedem Gegenstands-Tooltip",
            "Ein Rezeptfenster: Alt+Klick auf einen Gegenstand, der Reagenzienkette folgen, Favoriten",
            "Handwerksplaner: Auktionshauspreise, Gewinn und der günstigste Weg, einen Beruf zu leveln",
            "Rund 2.500 Rezepte von WoW Forever eingebaut, nichts zu scannen",
            "Die Oberfläche in 8 Sprachen, Namen von Gegenständen und Rezepten aus deinem Spielclient",
        },
        loot_buddy = {
            "Animierte Beute-Benachrichtigungen in den Farben der Gegenstandsqualität",
            "Ein Verlauf jedes erbeuteten Gegenstands: wann, wo und woher; Suche und Filter",
            "Filter für automatisches Plündern: Plunder nach Qualität, Händlerpreis, Name oder Maske liegen lassen",
            "Mittelklick auf einen Gegenstand in den Taschen sperrt ihn für automatisches Plündern",
            "Ein Taschen-Tracker: eigene Gruppen von Gegenständen mit ihrer Anzahl auf dem Bildschirm",
            "Beutereise: deine Beute Gegenstand für Gegenstand auf der Zonenkarte abspielen",
        },
        target_it = {
            "Knöpfe im Stil der Aktionsleisten: ein Klick visiert den nächsten lebenden NPC deiner Wahl an",
            "Gegner und NPCs deiner Quests zuerst; Suche über mehr als 10.000 NPCs",
            "Ein Schlachtzugssymbol auf dem Ziel, eine Taste für jeden Knopf",
            "Alt+Klick: ein Wegpunkt zum nächsten Spawnpunkt",
            "Merkt sich die neuen NPCs von Forever, sobald du sie siehst",
        },
        simple_buff_tracker = {
            "Deine Buffs auf einer Leiste mit Symbolen im Stil der Aktionsleisten: mit Timern oder nur die fehlenden",
            "Ein Linksklick erneuert einen Buff: wirkt den Zauber, isst Essen für Satt, trägt Waffenöl auf",
            "Auch Waffenverzauberungen, sogar Öl und Flammenzunge auf einer Waffe",
            "Ein Leuchten an fehlenden Buffs, drei Symbolstile, beliebige Größe und Wachstumsrichtung",
            "Rechtsklick auf einen Buff in der Leiste öffnet seine Einstellungen",
        },
    },
}
end)
