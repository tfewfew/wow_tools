WoWTools.prr.RegisterSource(function(...)
-- fr.lua -- the texts of the "Other addons" page, French. Part of the
-- shared/other_addons module: copied with it into every addon of the author.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
ns.OtherAddons.texts = ns.OtherAddons.texts or {}

ns.OtherAddons.texts.fr = {
    language_name = "Français",
    language = "Langue",
    title = "Autres addons",
    subtitle = "D'autres addons pour WoW Forever. Installés : %d sur %d.",
    footer = "Copiez un nom et cherchez-le sur CurseForge.",
    copy = "Copier le nom",
    copy_hint = "Ctrl+C pour copier",
    copy_tooltip = "Cliquez, puis appuyez sur Ctrl+C pour copier le nom.",
    copied = "Copié !",
    state = {
        loaded = "Installé",
        disabled = "Installé, désactivé",
        missing = "Non installé",
    },
    -- one line on what the addon is
    notes = {
        purple_note = "Des notes sur les joueurs que vous croisez : sur les barres de nom, dans les infobulles et le chat.",
        prr = "Ce qui fabrique un objet et à quoi il sert de composant : dans les infobulles et une fenêtre de recettes.",
        loot_buddy = "Des notifications de butin, un historique du butin avec recherche et des filtres de fouille automatique.",
        target_it = "Des boutons de barre d'action qui ciblent le PNJ vivant choisi le plus proche : les monstres de quête d'abord.",
        simple_buff_tracker = "Vos améliorations sur une barre d'icônes : toutes avec minuteurs ou seulement les manquantes. Un clic les remet.",
    },
    -- its features, one point each
    features = {
        purple_note = {
            "Une note sur n'importe qui en un clic : notes toutes prêtes ou votre propre texte",
            "Vos notes au-dessus des barres de nom, dans le chat et dans les infobulles",
            "Un rappel sonore quand un joueur noté apparaît à proximité",
            "Une fenêtre des joueurs autour de vous et un historique de toutes les rencontres avec recherche",
            "Partagez vos notes avec votre guilde",
            "Chaque note est signée et datée : chacun de vos personnages peut avoir la sienne",
        },
        prr = {
            "« Fabriqué par » et « Composant pour » dans l'infobulle de chaque objet",
            "Une fenêtre de recettes : Alt+clic sur un objet, suivez la chaîne des composants, favoris",
            "Planificateur d'artisanat : prix de l'hôtel des ventes, bénéfice et la montée de métier la moins chère",
            "Environ 2 500 recettes de WoW Forever intégrées, rien à scanner",
            "L'interface en 8 langues, les noms des objets et recettes tirés de votre client de jeu",
        },
        loot_buddy = {
            "Des notifications de butin animées aux couleurs de la qualité des objets",
            "Un historique de chaque objet ramassé : quand, où et sur quoi ; recherche et filtres",
            "Filtres de fouille automatique : laissez la camelote par qualité, prix du marchand, nom ou masque",
            "Clic du milieu sur un objet de vos sacs pour l'exclure de la fouille automatique",
            "Un suivi des sacs : vos propres groupes d'objets avec leur nombre à l'écran",
            "Voyage du butin : rejouez votre butin sur la carte de la zone, objet par objet",
        },
        target_it = {
            "Des boutons au style des barres d'action : un clic cible le PNJ vivant choisi le plus proche",
            "Les monstres et PNJ de vos quêtes d'abord ; recherche parmi plus de 10 000 PNJ",
            "Une marque de raid sur la cible, une touche pour chaque bouton",
            "Alt+clic : un point de passage vers l'apparition la plus proche",
            "Retient les nouveaux PNJ de Forever dès que vous les voyez",
        },
        simple_buff_tracker = {
            "Vos améliorations sur une barre d'icônes au style des barres d'action : avec minuteurs ou seulement les manquantes",
            "Un clic gauche remet une amélioration : lance le sort, mange pour Bien nourri, applique l'huile d'arme",
            "Les enchantements d'arme aussi, même une huile et Langue de feu sur la même arme",
            "Une lueur sur les améliorations manquantes, trois styles d'icônes, toute taille et direction",
            "Clic droit sur une amélioration de la barre pour ouvrir ses réglages",
        },
    },
}
end)
