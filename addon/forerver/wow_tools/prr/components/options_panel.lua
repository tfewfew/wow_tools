WoWTools.prr.RegisterSource(function(...)
local _, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local OptionsPanel = {}
ns.Components.OptionsPanel = OptionsPanel

local OPTIONS_NAME = "WoWToolsPRR"
local RESET_POPUP = "WOW_TOOLS_PRR_RESET_GATHERING"
local loadedLanguage

local function Saved()
    return ns.db.settings
end

-- ---------------------------------------------------------------------------
-- The upstream settings pages describe controls independently of the UI.
-- The host renders the controls through its shared AceConfig canvas.

local function Section(textKey)
    return { kind = "section", id = "section:" .. textKey, label = Text("options.sections." .. textKey) }
end

-- A switch of ns.db.settings[key], with optional enable and setter overrides.
local function Toggle(key, textKey, extra)
    local row = {
        kind = "toggle",
        id = key,
        label = Text("options." .. textKey .. ".name"),
        tooltip = Text("options." .. textKey .. ".description"),

        get = function() return Saved()[key] == true end,
        set = function(value) Saved()[key] = value end,
    }
    for field, value in pairs(extra or {}) do
        row[field] = value
    end
    return row
end

local function Button(id, textKey, onClick, extra)
    local row = {
        kind = "button",
        id = id,
        label = Text("options." .. textKey .. ".name"),
        tooltip = Text("options." .. textKey .. ".description"),
        onClick = onClick,
    }
    for field, value in pairs(extra or {}) do
        row[field] = value
    end
    return row
end

local function IsOn(key)
    return function() return Saved()[key] == true end
end

local function AreRecipesShown()
    local settings = Saved()
    return settings.showTooltip and (settings.showCraftedBy or settings.showReagentFor or settings.showSkillLevels)
end

local function IsGatheringShown()
    local settings = Saved()
    return settings.showHerbNodes or settings.showMiningNodes or settings.showSkinning
end

-- ---------------------------------------------------------------------------
-- The professions of the tooltips: a checkbox for each one of the base.

local function HiddenProfessions()
    return Saved().tooltipHiddenProfessions
end

local function ProfessionRowID(profession)
    return "profession" .. profession
end

local function SetAllProfessionsShown(isShown)
    for _, profession in ipairs(ns.Dataflows.RecipeIndex.Professions()) do
        HiddenProfessions()[profession] = (not isShown) or nil
    end
end

local function ProfessionRows()
    local rows = {
        Section("professions"),
        { kind = "buttons", id = "professionButtons", label = Text("options.tooltip_professions.all"),
          tooltip = Text("options.tooltip_professions.description"),
          buttons = {
              { text = Text("options.tooltip_professions.show_all"), onClick = function() SetAllProfessionsShown(true) end },
              { text = Text("options.tooltip_professions.hide_all"), onClick = function() SetAllProfessionsShown(false) end },
          },
          enabled = AreRecipesShown },
    }
    local tooltip = Text("options.tooltip_professions.description")
    for _, profession in ipairs(ns.Dataflows.RecipeIndex.Professions()) do
        table.insert(rows, {
            kind = "toggle",
            id = ProfessionRowID(profession),
            label = ns.GameData.ProfessionName(profession),
            tooltip = tooltip,

            get = function() return not HiddenProfessions()[profession] end,
            set = function(value) HiddenProfessions()[profession] = (not value) or nil end,
            enabled = AreRecipesShown,
        })
    end
    return rows
end

-- ---------------------------------------------------------------------------
-- The pages.

local function TooltipPage()
    local rows = {
        Section("general"),
        Toggle("showTooltip", "show_tooltip"),
        Section("crafting"),
        Toggle("showCraftedBy", "show_crafted_by", { enabled = IsOn("showTooltip") }),
        Toggle("showReagentFor", "show_reagent_for", { enabled = IsOn("showTooltip") }),
        Toggle("showSkillLevels", "show_skill_levels", { enabled = IsOn("showTooltip") }),
        Section("auction"),
        Toggle("showAuctionPrice", "show_auction_price", { enabled = IsOn("showTooltip") }),
        Section("disenchant"),
        Toggle("showDisenchant", "show_disenchant", { enabled = IsOn("showTooltip") }),
        Toggle("showDisenchantPrice", "show_disenchant_price", { enabled = function() return Saved().showTooltip and Saved().showDisenchant end }),
    }
    for _, row in ipairs(ProfessionRows()) do
        table.insert(rows, row)
    end
    return { key = "tooltip", title = Text("options.pages.tooltip"), rows = rows }
end

local function OwnGatheringCount()
    local count = 0
    for _, entries in pairs(ns.db.gatherStats) do
        for _, entry in pairs(entries) do
            count = count + (entry.n or 0)
        end
    end
    return count
end

-- "Reset": the game's yes / no popup with the number of loots, then the reset.
local function AskResetGathering()
    if not (StaticPopupDialogs and StaticPopup_Show) then
        ns.Dataflows.Gathering.ResetOwn()
        return
    end
    StaticPopupDialogs[RESET_POPUP] = {
        text = Text("options.gathering_reset.confirm", OwnGatheringCount()),
        button1 = YES,
        button2 = NO,
        OnAccept = function() ns.Dataflows.Gathering.ResetOwn() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(RESET_POPUP)
end

local function GatheringPage()
    return {
        key = "gathering",
        title = Text("options.pages.gathering"),
        rows = {
            Section("herbalism"),
            Toggle("showHerbNodes", "show_herb_nodes"),
            Section("mining"),
            Toggle("showMiningNodes", "show_mining_nodes"),
            Section("skinning"),
            Toggle("showSkinning", "show_skinning"),
            {
                kind = "dropdown",
                id = "skinningUnits",

                enabled = IsOn("showSkinning"),
                label = Text("options.skinning_units.name"),
                tooltip = Text("options.skinning_units.description"),

                values = function()
                    return { { "all", Text("options.skinning_units.all") }, { "dead", Text("options.skinning_units.dead") } }
                end,
                get = function() return Saved().skinningUnits end,
                set = function(value) Saved().skinningUnits = value end,
            },
            Section("loot"),
            Toggle("showPossibleLoot", "show_possible_loot", { enabled = IsGatheringShown }),
            Toggle("showGatheringOwn", "show_gathering_own", { enabled = IsGatheringShown }),
            Toggle("showGatheringStacks", "show_gathering_stacks", { enabled = IsGatheringShown }),
            Toggle("showGatheringPrice", "show_gathering_price", { enabled = IsGatheringShown }),
            Section("tracking"),
            Toggle("recordGathering", "record_gathering"),
            {
                kind = "slider",
                id = "gatheringHistory",

                enabled = IsOn("recordGathering"),
                label = Text("options.gathering_history.name"),
                tooltip = Text("options.gathering_history.description"),

                min = ns.Dataflows.Gathering.HISTORY_MIN,
                max = ns.Dataflows.Gathering.HISTORY_MAX,
                step = 10,

                get = function() return Saved().gatheringHistory end,
                set = function(value) Saved().gatheringHistory = value end,
            },
            Button("resetGathering", "gathering_reset", AskResetGathering),
        },
    }
end

local function ProfessionPage()
    return {
        key = "profession",
        title = Text("options.pages.profession"),
        rows = {
            Section("recipe"),
            Toggle("showSkillZones", "skill_zones", {
                set = function(value)
                    Saved().showSkillZones = value
                    ns.Components.SkillZones.RefreshAll()
                end,
            }),
        },
    }
end

local function OpenBindingValues()
    local values = {}
    for _, binding in ipairs(ns.Constants.OPEN_BINDINGS) do
        table.insert(values, { binding.id, Text("options.open_binding.values." .. binding.id) })
    end
    return values
end

local function WindowPage()
    return {
        key = "window",
        title = Text("options.pages.window"),
        rows = {
            Section("opening"),
            {
                kind = "dropdown",
                id = "openBinding",
                label = Text("options.open_binding.name"),
                tooltip = Text("options.open_binding.description"),

                values = OpenBindingValues,
                get = function() return Saved().openBinding end,
                set = function(value)
                    Saved().openBinding = value
                    ns.Components.ItemWindow.Refresh(true)   -- its hint names the click
                end,
            },
            Section("links"),
            Toggle("copyLink", "copy_link"),
        },
    }
end

local function PlannerPage()
    return {
        key = "planner",
        title = Text("options.pages.planner"),
        rows = {
            Section("auction"),
            {
                kind = "slider",
                id = "auctionCut",
                label = Text("options.auction_cut.name"),
                tooltip = Text("options.auction_cut.description"),

                min = 0,
                max = 30,
                step = 1,

                get = function() return Saved().planner.auctionCut end,
                set = function(value)
                    Saved().planner.auctionCut = value
                    ns.Components.PlannerWindow.Refresh()
                end,
            },
        },
    }
end

local function InterfacePage()
    return {
        key = "interface",
        title = Text("options.pages.interface"),
        rows = {
            Section("minimap"),
            Toggle("minimap", "minimap", {

                get = function() return not Saved().minimap.hide end,
                set = function(value) ns.Components.MinimapButton.SetHidden(not value) end,
            }),
            Section("loot_window"),
            Toggle("lootGlow", "loot_glow", {
                set = function(value)
                    Saved().lootGlow = value
                    ns.Components.LootGlow.RefreshAll()
                end,
            }),
        },
    }
end

-- Put Chinese first, then the automatic language choice and the other languages.
local function LanguageValues()
    local Localization = ns.Localization
    local clientName = Localization.NativeName(Localization.ClientLanguage())
    local values = { { Localization.AUTO, Text("options.language.auto", clientName) } }
    for _, language in ipairs(Localization.Languages()) do
        local choice = { language, Localization.NativeName(language) }
        if language == "zh" then
            table.insert(values, 1, choice)
        else
            table.insert(values, choice)
        end
    end
    return values
end

local function LanguagePage()
    return {
        key = "language",
        title = Text("options.pages.language"),
        rows = {
            Section("language"),
            {
                kind = "dropdown",
                id = "language",
                label = Text("options.language.name"),
                tooltip = Text("options.language.description"),

                values = LanguageValues,
                get = function() return Saved().language end,
                set = function(value) Saved().language = value end,
            },
            Button("reload", "language.reload", function() ReloadUI() end, {
                enabled = function() return Saved().language ~= loadedLanguage end,
            }),
        },
    }
end

-- The addon page itself: what it is and buttons for its windows.
local function MainPage()
    return {
        key = "general",
        title = ns.Constants.ADDON_TITLE,
        rows = {
            { kind = "section", id = "section:main", label = Text("options.main.header"),
              tooltip = Text("options.main.description") },
            Button("openWindow", "main.item_window", function() ns.Components.ItemWindow.Toggle() end),
            Button("openPlanner", "main.planner", function() ns.Components.PlannerWindow.Toggle() end),
        },
    }
end

-- The sub-pages, in the order of the list: by where in the game a setting works.
local function BuildPages()
    return { MainPage(), TooltipPage(), GatheringPage(), ProfessionPage(), WindowPage(), PlannerPage(), InterfacePage(), LanguagePage() }
end

local CONTROL_TYPES = { section = "header", toggle = "toggle", dropdown = "select",
    slider = "range", button = "execute" }

local function BuildOptions()
    local groups = {}
    for pageOrder, page in ipairs(BuildPages()) do
        local entries = {}
        local order = 0
        local function Add(id, entry)
            order = order + 1
            entry.order = order
            entries[id] = entry
        end
        for _, row in ipairs(page.rows) do
            local disabled
            if row.enabled then disabled = function() return not row.enabled() end end
            if row.kind == "buttons" then
                for i, button in ipairs(row.buttons) do
                    Add(row.id .. i, { type = "execute", name = button.text, desc = row.tooltip,
                        func = button.onClick, disabled = disabled })
                end
            else
                local entry = { type = CONTROL_TYPES[row.kind], name = row.label, desc = row.tooltip,
                    disabled = disabled, get = row.get, func = row.onClick }
                if row.set then entry.set = function(_, value) row.set(value) end end
                if row.kind == "dropdown" then
                    entry.values, entry.sorting = {}, {}
                    for _, choice in ipairs(row.values()) do
                        entry.values[choice[1]] = choice[2]
                        table.insert(entry.sorting, choice[1])
                    end
                elseif row.kind == "slider" then
                    entry.min, entry.max, entry.step = row.min, row.max, row.step
                end
                if row.kind == "section" and row.tooltip then
                    entry.type = "description"
                    entry.name = row.tooltip
                end
                Add(row.id, entry)
            end
        end
        groups[page.key] = { type = "group", order = pageOrder, name = page.title, args = entries }
    end
    return { type = "group", name = ns.Constants.ADDON_TITLE, args = groups }
end

function OptionsPanel.Setup()
    local config = LibStub("AceConfig-3.0", true)
    if not (config and LibStub("AceConfigDialog-3.0", true)) then return end
    loadedLanguage = Saved().language
    config:RegisterOptionsTable(OPTIONS_NAME, BuildOptions)
    ns.ready = true
end

function OptionsPanel.Open(pageKey)
    WoWTools.settings.Open("prr", pageKey)
end
end)
