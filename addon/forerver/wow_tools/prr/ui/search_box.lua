WoWTools.prr.RegisterSource(function(...)
-- search_box.lua -- the game's search field (SearchBoxTemplate, as in the bags
-- and the quest log): a magnifier, a gray placeholder and a clear button.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local TEMPLATES = { "SearchBoxTemplate", "InputBoxTemplate" }
local HEIGHT = 20

local function CreateEditBox(parent)
    for _, template in ipairs(TEMPLATES) do
        local ok, editBox = pcall(CreateFrame, "EditBox", nil, parent, template)
        if ok and editBox then
            return editBox
        end
    end
    return CreateFrame("EditBox", nil, parent)
end

-- options: placeholder, onChange(text) -- on every change of the text,
-- onCommit(text) -- Enter pressed or the field left (optional).
function ns.UI.SearchBox(parent, options)
    local searchBox = CreateEditBox(parent)
    searchBox:SetHeight(HEIGHT)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then
        searchBox.Instructions:SetText(options.placeholder)
    end

    -- the template has its own OnTextChanged (placeholder, clear button): add to it
    searchBox:HookScript("OnTextChanged", function(self)
        options.onChange(self:GetText())
    end)
    searchBox:HookScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:HookScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    if options.onCommit then
        searchBox:HookScript("OnEditFocusLost", function(self)
            options.onCommit(self:GetText())
        end)
    end

    return searchBox
end
end)
