WoWTools.prr.RegisterSource(function(...)
-- localization.lua -- UI texts in the language of the settings (settings.language),
-- the client's language by default ("auto").
--
-- Texts live in lang/<language>.json. The game does not read .json, so
-- scripts/build_lang.py builds lang/<language>.lua next to it, which passes
-- the JSON string here, to Add. Keys are nested, in code -- dotted:
-- Text("window.title", 5) -> "Players nearby: 5".

local ADDON, ns = ...

local Localization = {}
ns.Localization = Localization

local FALLBACK_LANGUAGE = "en"

Localization.AUTO = "auto"       -- settings.language: the client's language

-- the client's locale -> the language of the texts; any other one -> en
local CLIENT_LANGUAGES = {
    deDE = "de",
    esES = "es",
    esMX = "es",
    frFR = "fr",
    itIT = "it",
    ptBR = "pt",
    ruRU = "ru",
    zhCN = "zh",
}
-- languages whose letters only the fonts of some clients have: Chinese on a
-- European client would be squares, so it is not offered there
local FONT_LOCALES = {
    zh = { zhCN = true, zhTW = true },
}
local clientLanguage = CLIENT_LANGUAGES[GetLocale()] or FALLBACK_LANGUAGE
-- until the settings are loaded (core.lua) -- the client's language
local currentLanguage = clientLanguage

local sources = {}   -- [language] = the JSON text of lang/<language>.lua, not decoded yet
local texts = {}     -- [language] = { ["window.title"] = "..." }

-- { window = { title = "..." } } -> { ["window.title"] = "..." }
local function Flatten(tree, prefix, result)
    for key, value in pairs(tree) do
        local path = key
        if prefix ~= "" then
            path = prefix .. "." .. key
        end

        if type(value) == "table" then
            Flatten(value, path, result)
        else
            result[path] = value
        end
    end
    return result
end

-- Called from lang/<language>.lua. A language is decoded when it is first needed:
-- the files are loaded before the settings say which one it is.
function Localization.Add(language, jsonText)
    sources[language] = jsonText
end

local function Texts(language)
    if texts[language] then
        return texts[language]
    end
    local source = sources[language]
    if not source then
        return {}
    end
    sources[language] = nil
    local ok, tree = pcall(ns.json.decode, source)
    if not ok then
        ns.Utilities.Print("lang/" .. language .. ".json: " .. tostring(tree))
        texts[language] = {}
        return texts[language]
    end
    texts[language] = Flatten(tree, "", {})
    return texts[language]
end

-- There is a lang file of it, and the client's fonts can draw it.
local function IsUsable(language)
    local hasTexts = sources[language] ~= nil or texts[language] ~= nil
    local locales = FONT_LOCALES[language]
    return hasTexts and (locales == nil or locales[GetLocale()] == true)
end

-- The languages this client can show, sorted: { "de", "en", "es", ... }.
function Localization.Languages()
    local seen = {}
    local languages = {}
    for _, list in ipairs({ sources, texts }) do
        for language in pairs(list) do
            if not seen[language] and IsUsable(language) then
                seen[language] = true
                table.insert(languages, language)
            end
        end
    end
    table.sort(languages)
    return languages
end

-- The name of a language in that language itself: "English", "Russian" in Russian.
function Localization.NativeName(language)
    return Texts(language)["language.native_name"] or language
end

function Localization.ClientLanguage()
    return clientLanguage
end

-- The language of the settings ("auto" or "ru"...); an unknown or unusable one -- the client's.
-- The texts of frames made before stay as they are: a reload of the UI changes them.
function Localization.SetLanguage(choice)
    if choice and choice ~= Localization.AUTO and IsUsable(choice) then
        currentLanguage = choice
    else
        currentLanguage = clientLanguage
    end
end

-- Text by key. Missing in the current language -- take the fallback, missing there too --
-- the key itself, so the gap is visible in the UI. Extra arguments go to
-- string.format: Text("window.footer", 2, 3, 140).
function Localization.Text(key, ...)
    local current = Texts(currentLanguage)
    local fallback = Texts(FALLBACK_LANGUAGE)
    local text = current[key] or fallback[key] or key

    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end
end)
