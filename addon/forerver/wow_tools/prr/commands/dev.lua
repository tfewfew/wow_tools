WoWTools.prr.RegisterSource(function(...)
-- dev.lua -- /prr dev: developer mode on or off (settings.developer). In it
-- recipe rows show their spell id and a right click opens the fix menu
-- (components/recipe_fix_menu.lua). /prr skin -- where the window border
-- comes from. Not in the /prr help list.

local ADDON, ns = ...

local Text = ns.Localization.Text

ns.Commands.Add("dev", {
    run = function()
        local settings = ns.db.settings
        settings.developer = not settings.developer
        if settings.developer then
            ns.Utilities.Print(Text("dev.on"))
        else
            ns.Utilities.Print(Text("dev.off"))
        end
        ns.Dataflows.RecipeIndex.Invalidate()   -- ignored recipes are listed only in developer mode
        ns.Components.ItemWindow.Refresh(true)
    end,
    developer = true,
})

-- /prr skin: what the window border is made from (ui/client_border.lua); not localized, for debugging.
ns.Commands.Add("skin", {
    run = function()
        ns.Utilities.Print("skin: " .. tostring(ns.UI.clientBorderSource))
    end,
    developer = true,
})
end)
