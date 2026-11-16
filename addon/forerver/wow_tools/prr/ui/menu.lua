WoWTools.prr.RegisterSource(function(...)
-- menu.lua -- context menu on the client's built-in menu system (MenuUtil).
--
-- We do not write our own menu: MenuUtil.CreateContextMenu exists and works on
-- this client -- TomTom and BagBrother with interface 16001 use it too.

local ADDON, ns = ...
ns.UI = ns.UI or {}

-- owner -- frame the menu opens at; title -- first line, not clickable (optional);
-- items: { { text, onClick, disabled }, ... }; { separator = true } draws a line.
function ns.UI.ShowMenu(owner, title, items)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        if title then
            rootDescription:CreateTitle(title)
        end
        for _, item in ipairs(items) do
            if item.separator then
                rootDescription:CreateDivider()
            else
                local button = rootDescription:CreateButton(item.text, item.onClick)
                if item.disabled and button.SetEnabled then
                    button:SetEnabled(false)
                end
            end
        end
    end)
end
end)
