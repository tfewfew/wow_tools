local addonTable = WoWTools.lsToasts

-- Mine
local C, D = {}, {}
addonTable.C, addonTable.D = C, D

D.profile = {
    strata = "DIALOG",
    skin = "default",
    font = {
        -- name = nil,
        size = 12,
    },
    colors = {
        name = true,
        border = true,
        icon_border = true,
        threshold = 1,
    },
    types = {},
    anchors = {
        [1] = {
            fadeout_delay = 2.8,
            growth_direction = "UP",
            growth_offset_x = 26,
            growth_offset_y = 14,
            max_active_toasts = 12,
            scale = 1,
            point = {
                p = "BOTTOMRIGHT",
                rP = "BOTTOMRIGHT",
                x = -319,
                y = 280,
            },
        },
    },
}
