WoWTools.prr.RegisterSource(function(...)
-- es.lua -- the texts of the "Other addons" page, Spanish. Part of the
-- shared/other_addons module: copied with it into every addon of the author.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
ns.OtherAddons.texts = ns.OtherAddons.texts or {}

ns.OtherAddons.texts.es = {
    language_name = "Español",
    language = "Idioma",
    title = "Otros addons",
    subtitle = "Más addons para WoW Forever. Instalados: %d de %d.",
    footer = "Copia un nombre y búscalo en CurseForge.",
    copy = "Copiar nombre",
    copy_hint = "Ctrl+C para copiar",
    copy_tooltip = "Haz clic y pulsa Ctrl+C para copiar el nombre.",
    copied = "¡Copiado!",
    state = {
        loaded = "Instalado",
        disabled = "Instalado, desactivado",
        missing = "No instalado",
    },
    -- one line on what the addon is
    notes = {
        purple_note = "Notas sobre los jugadores que conoces: en las placas de nombre, en las descripciones y en el chat.",
        prr = "Qué fabrica un objeto y para qué es componente: en las descripciones y en una ventana de recetas.",
        loot_buddy = "Avisos de botín, un historial de botín con búsqueda y filtros de despojo automático.",
        target_it = "Botones de barra de acción que seleccionan al PNJ vivo elegido más cercano: primero los de misión.",
        simple_buff_tracker = "Tus beneficios en una barra de iconos: todos con temporizadores o solo los que faltan. Un clic los repone.",
    },
    -- its features, one point each
    features = {
        purple_note = {
            "Una nota sobre cualquiera con un clic: notas listas o tu propio texto",
            "Tus notas sobre las placas de nombre, en el chat y en las descripciones",
            "Un aviso con sonido cuando un jugador anotado aparece cerca",
            "Una ventana de los jugadores a tu alrededor y un historial de encuentros con búsqueda",
            "Comparte notas con tu hermandad",
            "Cada nota está firmada y fechada: cada uno de tus personajes puede tener la suya",
        },
        prr = {
            "\"Fabricado por\" y \"Componente para\" en la descripción de cada objeto",
            "Una ventana de recetas: Alt+clic en un objeto, sigue la cadena de componentes, favoritos",
            "Planificador: precios de la casa de subastas, beneficio y la forma más barata de subir una profesión",
            "Unas 2.500 recetas de WoW Forever incluidas, nada que escanear",
            "La interfaz en 8 idiomas, los nombres de objetos y recetas de tu cliente del juego",
        },
        loot_buddy = {
            "Avisos de botín animados con los colores de la calidad de los objetos",
            "Un historial de cada objeto despojado: cuándo, dónde y de qué; búsqueda y filtros",
            "Filtros de despojo automático: deja la chatarra por calidad, precio de venta, nombre o máscara",
            "Clic central en un objeto de tus bolsas para excluirlo del despojo automático",
            "Un rastreador de bolsas: tus propios grupos de objetos con su cantidad en pantalla",
            "Viaje del botín: reproduce tu botín en el mapa de la zona, objeto a objeto",
        },
        target_it = {
            "Botones al estilo de las barras de acción: un clic selecciona al PNJ vivo elegido más cercano",
            "Primero los enemigos y PNJ de tus misiones; búsqueda entre más de 10.000 PNJ",
            "Una marca de banda en el objetivo, una tecla para cada botón",
            "Alt+clic: un punto de ruta a la aparición más cercana",
            "Recuerda los PNJ nuevos de Forever en cuanto los ves",
        },
        simple_buff_tracker = {
            "Tus beneficios en una barra de iconos al estilo de las barras de acción: con temporizadores o solo los que faltan",
            "Un clic izquierdo repone un beneficio: lanza el hechizo, come para Bien alimentado, aplica aceite al arma",
            "También los encantamientos de arma, incluso un aceite y Lengua de Fuego en la misma arma",
            "Un brillo en los beneficios que faltan, tres estilos de icono, cualquier tamaño y dirección",
            "Clic derecho en un beneficio de la barra para abrir sus ajustes",
        },
    },
}
end)
