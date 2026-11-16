WoWTools.prr.RegisterSource(function(...)
-- wowhead.lua -- links to the Wowhead database of WoW Forever
-- (https://www.wowhead.com/forever/item=2318), in the client's language.

local ADDON, ns = ...

local Wowhead = {}
ns.Wowhead = Wowhead

local BASE_URL = "https://www.wowhead.com/forever/"

-- client locale -> Wowhead language folder; English has none
local LANGUAGE_FOLDERS = {
    deDE = "de/",
    esES = "es/",
    esMX = "es/",
    frFR = "fr/",
    itIT = "it/",
    ptBR = "pt/",
    ruRU = "ru/",
    koKR = "ko/",
    zhCN = "cn/",
    zhTW = "tw/",
}

-- kind -- "item" | "spell"
function Wowhead.Url(kind, id)
    local languageFolder = LANGUAGE_FOLDERS[GetLocale()] or ""
    return BASE_URL .. languageFolder .. kind .. "=" .. tostring(id)
end

-- What the mouse is over in the item window, for Ctrl+C: { kind, id } or nil.
-- Our icons set it on enter and clear it on leave (ui/icon_button.lua,
-- ui/item_slot.lua, components/recipe_row.lua); nothing else does.
Wowhead.hovered = nil

function Wowhead.SetHovered(kind, id)
    if kind and id then
        Wowhead.hovered = { kind = kind, id = id }
    else
        Wowhead.hovered = nil
    end
end
end)
