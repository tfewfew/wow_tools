WoWTools.prr.RegisterSource(function(...)
-- command_router.lua -- chat commands: /prr <command> [arguments].
-- Every command calls ns.Commands.Run, so a button could call it the same way.

local ADDON, ns = ...

local routes = {}   -- [command name] = options
local order = {}    -- names in the order they were added, for the help list
ns.Commands = {}

-- options: run(arguments), helpKey -- the lang key of the hint in chat (read when printed:
-- the language of the settings is known only after the files are loaded),
-- developer -- not in the help list (scans that build the recipe base)
function ns.Commands.Add(name, options)
    routes[name] = options
    if not options.developer then
        table.insert(order, name)
    end
end

function ns.Commands.PrintHelp()
    for _, commandName in ipairs(order) do
        local helpKey = routes[commandName].helpKey
        local help = helpKey and ns.Localization.Text(helpKey) or ""
        ns.Utilities.Print("/prr " .. commandName .. " -- " .. help)
    end
end

-- Unknown command -- print the list of all commands.
function ns.Commands.Run(name, arguments)
    local route = routes[name]
    if route then
        return route.run(arguments or "")
    end
    ns.Commands.PrintHelp()
end

SLASH_PRR1 = "/prr"
SLASH_PRR2 = "/prrm"  -- the addon's names before PRR
SLASH_PRR3 = "/rom"
SlashCmdList.PRR = function(message)
    local trimmed = message:match("^%s*(.-)%s*$")
    local firstWord, rest = trimmed:match("^(%S*)%s*(.-)$")
    local commandName = firstWord:lower()
    -- /prr alone -- the item window
    if commandName == "" then
        commandName = "show"
    end
    ns.Commands.Run(commandName, rest)
end
end)
