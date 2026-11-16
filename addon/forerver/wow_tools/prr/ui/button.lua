WoWTools.prr.RegisterSource(function(...)
-- button.lua -- standard client button.

local ADDON, ns = ...
ns.UI = ns.UI or {}

-- options: text, width, height, onClick
function ns.UI.Button(parent, options)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(options.width or 80, options.height or 20)
    button:SetText(options.text or "")
    if options.onClick then
        button:SetScript("OnClick", options.onClick)
    end
    return button
end
end)
