WoWTools.prr.RegisterSource(function(...)
-- AceConfig pages rendered in the host's shared settings canvas.
-- Values live in ns.db.settings.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local OptionsPanel = {}
ns.Components.OptionsPanel = OptionsPanel

local OPTIONS_NAME = "WoWToolsPRR"          -- AceConfig id of the addon page

-- the language the texts are in now: the settings say another one -- a reload is needed
local loadedLanguage = nil

local function Setting(key)
    return {
        get = function()
            return ns.db.settings[key]
        end,
        set = function(_, value)
            ns.db.settings[key] = value
        end,
    }
end

local function Toggle(order, key, nameKey, extra)
    local option = Setting(key)
    option.type = "toggle"
    option.order = order
    option.width = "full"
    option.name = Text(nameKey .. ".name")
    option.desc = Text(nameKey .. ".description")
    for field, value in pairs(extra or {}) do
        option[field] = value
    end
    return option
end

-- { [id] = text } and the order of the ids for the select of the open binding
local function OpenBindingChoices()
    local values = {}
    local sorting = {}
    for _, binding in ipairs(ns.Constants.OPEN_BINDINGS) do
        values[binding.id] = Text("options.open_binding.values." .. binding.id)
        table.insert(sorting, binding.id)
    end
    return values, sorting
end

local function IsTooltipOff()
    return not ns.db.settings.showTooltip
end

local function HiddenProfessions()
    return ns.db.settings.tooltipHiddenProfessions
end

local function SetAllProfessionsShown(isShown)
    local hidden = HiddenProfessions()
    for _, profession in ipairs(ns.Dataflows.RecipeIndex.Professions()) do
        hidden[profession] = (not isShown) or nil
    end
end

-- A toggle for every profession of the base: off -- its recipes leave the tooltips.
local function ProfessionArgs()
    local args = {
        description = {
            type = "description",
            order = 1,
            name = Text("options.tooltip_professions.description"),
        },
        showAll = {
            type = "execute",
            order = 2,
            name = Text("options.tooltip_professions.show_all"),
            func = function()
                SetAllProfessionsShown(true)
            end,
        },
        hideAll = {
            type = "execute",
            order = 3,
            name = Text("options.tooltip_professions.hide_all"),
            func = function()
                SetAllProfessionsShown(false)
            end,
        },
        buttonsEnd = { type = "description", order = 4, name = "" },
    }
    for index, profession in ipairs(ns.Dataflows.RecipeIndex.Professions()) do
        args["profession" .. profession] = {
            type = "toggle",
            order = 10 + index,
            name = ns.GameData.ProfessionName(profession),
            get = function()
                return not HiddenProfessions()[profession]
            end,
            set = function(_, value)
                HiddenProfessions()[profession] = (not value) or nil
            end,
        }
    end
    return args
end

local function TooltipPage()
    return {
        type = "group",
        order = 1,
        name = Text("options.tooltip_header"),
        args = {
            showTooltip = Toggle(1, "showTooltip", "options.show_tooltip"),
            showCraftedBy = Toggle(2, "showCraftedBy", "options.show_crafted_by", { disabled = IsTooltipOff }),
            showReagentFor = Toggle(3, "showReagentFor", "options.show_reagent_for", { disabled = IsTooltipOff }),
            showAuctionPrice = Toggle(4, "showAuctionPrice", "options.show_auction_price", { disabled = IsTooltipOff }),
            professions = {
                type = "group",
                order = 10,
                inline = true,
                name = Text("options.tooltip_professions.name"),
                disabled = IsTooltipOff,
                args = ProfessionArgs(),
            },
        },
    }
end

local function WindowPage()
    return {
        type = "group",
        order = 2,
        name = Text("options.window_header"),
        args = {
            openBinding = {
                type = "select",
                order = 1,
                width = "double",
                name = Text("options.open_binding.name"),
                desc = Text("options.open_binding.description"),
                values = function()
                    local values = OpenBindingChoices()
                    return values
                end,
                sorting = function()
                    local _, sorting = OpenBindingChoices()
                    return sorting
                end,
                get = function()
                    return ns.db.settings.openBinding
                end,
                set = function(_, value)
                    ns.db.settings.openBinding = value
                    ns.Components.ItemWindow.Refresh(true)   -- its hint names the click
                end,
            },
        },
    }
end

local function WowheadPage()
    return {
        type = "group",
        order = 3,
        name = Text("options.link_header"),
        args = {
            copyLink = Toggle(1, "copyLink", "options.copy_link"),
        },
    }
end

local function InterfacePage()
    return {
        type = "group",
        order = 4,
        name = Text("options.interface_header"),
        args = {
            minimap = {
                type = "toggle",
                order = 1,
                width = "full",
                name = Text("options.minimap.name"),
                desc = Text("options.minimap.description"),
                get = function()
                    return not ns.db.settings.minimap.hide
                end,
                set = function(_, value)
                    ns.Components.MinimapButton.SetHidden(not value)
                end,
            },
            lootGlow = Toggle(2, "lootGlow", "options.loot_glow", {
                set = function(_, value)
                    ns.db.settings.lootGlow = value
                    ns.Components.LootGlow.RefreshAll()
                end,
            }),
        },
    }
end

local function PlannerPage()
    return {
        type = "group",
        order = 5,
        name = Text("options.planner_header"),
        args = {
            auctionCutExplanation = {
                type = "description",
                order = 1,
                fontSize = "medium",
                name = Text("options.auction_cut.explanation"),
            },
            auctionCut = {
                type = "range",
                order = 2,
                width = "double",
                min = 0,
                max = 30,
                step = 1,
                name = Text("options.auction_cut.name"),
                desc = Text("options.auction_cut.description"),
                get = function()
                    return ns.db.settings.planner.auctionCut
                end,
                set = function(_, value)
                    ns.db.settings.planner.auctionCut = value
                    ns.Components.PlannerWindow.Refresh()
                end,
            },
        },
    }
end

-- { [language] = name } for the language select: the client's one first, then
-- each language in its own name.
local function LanguageChoices()
    local Localization = ns.Localization
    local clientName = Localization.NativeName(Localization.ClientLanguage())
    local values = { [Localization.AUTO] = Text("options.language.auto", clientName) }
    local sorting = { Localization.AUTO }
    for _, language in ipairs(Localization.Languages()) do
        values[language] = Localization.NativeName(language)
        if language == "zh" then table.insert(sorting, 1, language) else table.insert(sorting, language) end
    end
    return values, sorting
end

local function IsReloadNeeded()
    return ns.db.settings.language ~= loadedLanguage
end

local function LanguagePage()
    local values, sorting = LanguageChoices()
    return {
        type = "group",
        order = 6,
        name = Text("options.language_header"),
        args = {
            language = {
                type = "select",
                order = 1,
                width = "double",
                name = Text("options.language.name"),
                desc = Text("options.language.description"),
                values = values,
                sorting = sorting,
                get = function()
                    return ns.db.settings.language
                end,
                set = function(_, value)
                    ns.db.settings.language = value
                end,
            },
            note = {
                type = "description",
                order = 2,
                fontSize = "medium",
                name = Text("options.language.note"),
            },
            reload = {
                type = "execute",
                order = 3,
                name = Text("options.language.reload"),
                disabled = function()
                    return not IsReloadNeeded()
                end,
                func = function()
                    ReloadUI()
                end,
            },
        },
    }
end

-- The addon page itself: what it is, buttons for its windows. The settings
-- are on its sub-pages (PAGES), in the list on the left under it.
local function BuildMainPage()
    return {
        type = "group",
        name = ns.Constants.ADDON_TITLE,
        args = {
            description = {
                type = "description",
                order = 1,
                fontSize = "medium",
                name = Text("options.main.description"),
            },
            openWindow = {
                type = "execute",
                order = 2,
                name = Text("options.main.open_window"),
                func = function()
                    ns.Components.ItemWindow.Toggle()
                end,
            },
            openPlanner = {
                type = "execute",
                order = 3,
                name = Text("options.main.open_planner"),
                func = function()
                    ns.Components.PlannerWindow.Toggle()
                end,
            },
        },
    }
end

-- Each settings section remains available in the embedded options tree.

local function BuildPages()
    return {
        type = "group",
        name = ns.Constants.ADDON_TITLE,
        args = {
            tooltip = TooltipPage(),
            window = WindowPage(),
            wowhead = WowheadPage(),
            interface = InterfacePage(),
            planner = PlannerPage(),
            language = LanguagePage(),
        },
    }
end

-- Register after the host's saved settings are available.
function OptionsPanel.Setup()
    local config = LibStub("AceConfig-3.0", true)
    local dialog = LibStub("AceConfigDialog-3.0", true)
    if not (config and dialog) then return end
    loadedLanguage = ns.db.settings.language

    config:RegisterOptionsTable(OPTIONS_NAME, function()
        local options = BuildPages()
        options.args.general = BuildMainPage()
        options.args.general.order = 0
        return options
    end)

    ns.ready = true
end

function OptionsPanel.Open()
    WoWTools.settings.Open("prr")
end
end)
