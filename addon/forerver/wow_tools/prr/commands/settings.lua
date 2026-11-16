WoWTools.prr.RegisterSource(function(...)
-- settings.lua -- turning the tooltip blocks on and off:
--   /prr crafted  -- "Crafted by"
--   /prr reagent  -- "Reagent for"

local ADDON, ns = ...

local Text = ns.Localization.Text

local function Toggle(settingKey, nameKey)
    local settings = ns.db.settings
    settings[settingKey] = not settings[settingKey]
    if settings[settingKey] then
        ns.Utilities.Print(Text("commands.toggle.on", Text(nameKey)))
    else
        ns.Utilities.Print(Text("commands.toggle.off", Text(nameKey)))
    end
end

ns.Commands.Add("crafted", {
    run = function()
        Toggle("showCraftedBy", "tooltip.crafted_by")
    end,
    helpKey = "commands.crafted.help",
})

ns.Commands.Add("reagent", {
    run = function()
        Toggle("showReagentFor", "tooltip.reagent_for")
    end,
    helpKey = "commands.reagent.help",
})
end)
