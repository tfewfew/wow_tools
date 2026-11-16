WoWTools.prr.RegisterSource(function(...)
-- checkbox.lua -- checkbox with a label on the right, on the client's built-in template.
--
-- The label is our own: the template names it differently in different client
-- versions (text or Text).

local ADDON, ns = ...
ns.UI = ns.UI or {}

local BOX_SIZE = 22
local LABEL_GAP = 2
local TOOLTIP_TEXT_COLOR = { 1, 1, 1 }

-- options: text, checked, onChange(checked),
-- tooltip -- a description shown on hover under the label as its title (optional)
function ns.UI.Checkbox(parent, options)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(BOX_SIZE, BOX_SIZE)
    checkbox:SetChecked(options.checked and true or false)

    checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", LABEL_GAP, 0)
    checkbox.label:SetText(options.text or "")

    -- a disabled checkbox has a grey label, like the game's own
    checkbox:HookScript("OnDisable", function(self)
        self.label:SetFontObject("GameFontDisableSmall")
    end)
    checkbox:HookScript("OnEnable", function(self)
        self.label:SetFontObject("GameFontHighlightSmall")
    end)

    checkbox:SetScript("OnClick", function(self)
        if options.onChange then
            options.onChange(self:GetChecked() and true or false)
        end
    end)

    if options.tooltip then
        checkbox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(options.text or "")
            GameTooltip:AddLine(options.tooltip,
                TOOLTIP_TEXT_COLOR[1], TOOLTIP_TEXT_COLOR[2], TOOLTIP_TEXT_COLOR[3], true)
            GameTooltip:Show()
        end)
        checkbox:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    return checkbox
end
end)
