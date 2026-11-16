WoWTools.prr.RegisterSource(function(...)
-- select.lua -- a dropdown with one choice out of a list, the game's own look.
--
-- The client's dropdown (DropdownButton with WowStyle1DropdownTemplate, used by
-- BugSack and Leatrix Plus on this client) shows the chosen item itself and
-- opens a menu of radio items. On a client without it -- a plain button with
-- the chosen text that opens the same menu through MenuUtil.
-- The choices are asked every time the menu is built, so they can change;
-- after they change call select:Refresh() to update the shown text.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local DROPDOWN_TEMPLATE = "WowStyle1DropdownTemplate"
local DEFAULT_HEIGHT = 26

-- options: width, height, choices() -> { { value, text }, ... },
-- selected() -> the current value, onChange(value),
-- emptyText -- shown when nothing is chosen (or there is nothing to choose),
-- maxMenuHeight -- a taller menu scrolls (where the client can)
function ns.UI.Select(parent, options)
    local function IsSelected(value)
        return options.selected() == value
    end
    local function Select(value)
        options.onChange(value)
    end
    local function BuildMenu(_, rootDescription)
        if options.maxMenuHeight and rootDescription.SetScrollMode then
            rootDescription:SetScrollMode(options.maxMenuHeight)
        end
        for _, choice in ipairs(options.choices()) do
            rootDescription:CreateRadio(choice.text, IsSelected, Select, choice.value)
        end
    end

    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, DROPDOWN_TEMPLATE)
    if ok and dropdown.SetupMenu then
        dropdown:SetSize(options.width, options.height or DEFAULT_HEIGHT)
        if dropdown.SetDefaultText and options.emptyText then
            dropdown:SetDefaultText(options.emptyText)
        end
        dropdown:SetupMenu(BuildMenu)

        function dropdown:Refresh()
            self:GenerateMenu()
        end
        return dropdown
    end

    -- fallback: a button with the chosen text
    local button = ns.UI.Button(parent, { width = options.width, height = options.height or DEFAULT_HEIGHT })
    function button:Refresh()
        local chosenText = options.emptyText or ""
        for _, choice in ipairs(options.choices()) do
            if IsSelected(choice.value) then
                chosenText = choice.text
            end
        end
        self:SetText(chosenText)
    end
    button:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, BuildMenu)
    end)
    Select = function(value)
        options.onChange(value)
        button:Refresh()
    end
    button:Refresh()
    return button
end
end)
