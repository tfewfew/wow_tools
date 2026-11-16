WoWTools.prr.RegisterSource(function(...)
-- it.lua -- the texts of the "Other addons" page, Italian. Part of the
-- shared/other_addons module: copied with it into every addon of the author.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
ns.OtherAddons.texts = ns.OtherAddons.texts or {}

ns.OtherAddons.texts.it = {
    language_name = "Italiano",
    language = "Lingua",
    title = "Altri addon",
    subtitle = "Altri addon per WoW Forever. Installati: %d di %d.",
    footer = "Copia un nome e cercalo su CurseForge.",
    copy = "Copia nome",
    copy_hint = "Ctrl+C per copiare",
    copy_tooltip = "Fai clic, poi premi Ctrl+C per copiare il nome.",
    copied = "Copiato!",
    state = {
        loaded = "Installato",
        disabled = "Installato, disattivato",
        missing = "Non installato",
    },
    -- one line on what the addon is
    notes = {
        purple_note = "Note sui giocatori che incontri: sulle barre dei nomi, nei tooltip e in chat.",
        prr = "Cosa crea un oggetto e a cosa serve come reagente: nei tooltip e in una finestra delle ricette.",
        loot_buddy = "Notifiche del bottino, una cronologia del bottino con ricerca e filtri per il saccheggio automatico.",
        target_it = "Pulsanti da barra azioni che selezionano il PNG vivo scelto più vicino: prima i mostri delle missioni.",
        simple_buff_tracker = "I tuoi potenziamenti in una barra di icone: tutti con timer o solo quelli mancanti. Un clic li rimette.",
    },
    -- its features, one point each
    features = {
        purple_note = {
            "Una nota su chiunque con un clic: note pronte o il tuo testo",
            "Le tue note sopra le barre dei nomi, in chat e nei tooltip",
            "Un promemoria con suono quando un giocatore annotato compare vicino",
            "Una finestra dei giocatori intorno a te e una cronologia degli incontri con ricerca",
            "Condividi le note con la tua gilda",
            "Ogni nota è firmata e datata: ognuno dei tuoi personaggi può avere la sua",
        },
        prr = {
            "\"Creato da\" e \"Reagente per\" nel tooltip di ogni oggetto",
            "Una finestra delle ricette: Alt+clic su un oggetto, segui la catena dei reagenti, preferiti",
            "Pianificatore: prezzi della casa d'aste, profitto e il modo più economico di salire di professione",
            "Circa 2.500 ricette di WoW Forever incluse, niente da scansionare",
            "L'interfaccia in 8 lingue, i nomi di oggetti e ricette dal tuo client di gioco",
        },
        loot_buddy = {
            "Notifiche del bottino animate nei colori della qualità degli oggetti",
            "Una cronologia di ogni oggetto raccolto: quando, dove e da cosa; ricerca e filtri",
            "Filtri per il saccheggio automatico: lascia la spazzatura per qualità, prezzo del mercante, nome o maschera",
            "Clic centrale su un oggetto nelle borse per escluderlo dal saccheggio automatico",
            "Un tracciatore delle borse: i tuoi gruppi di oggetti con la loro quantità sullo schermo",
            "Viaggio del bottino: rivedi il tuo bottino sulla mappa della zona, oggetto per oggetto",
        },
        target_it = {
            "Pulsanti in stile barra azioni: un clic seleziona il PNG vivo scelto più vicino",
            "Prima i mostri e i PNG delle tue missioni; ricerca tra oltre 10.000 PNG",
            "Un simbolo da incursione sul bersaglio, un tasto per ogni pulsante",
            "Alt+clic: un punto di riferimento verso la comparsa più vicina",
            "Ricorda i nuovi PNG di Forever appena li vedi",
        },
        simple_buff_tracker = {
            "I tuoi potenziamenti in una barra di icone in stile barra azioni: con timer o solo quelli mancanti",
            "Un clic sinistro rimette un potenziamento: lancia l'incantesimo, mangia per Ben nutrito, applica l'olio all'arma",
            "Anche gli incantamenti dell'arma, persino un olio e Lingua di Fuoco sulla stessa arma",
            "Un bagliore sui potenziamenti mancanti, tre stili di icona, qualsiasi dimensione e direzione",
            "Clic destro su un potenziamento della barra per aprirne le impostazioni",
        },
    },
}
end)
