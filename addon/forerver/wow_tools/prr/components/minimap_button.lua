WoWTools.prr.RegisterSource(function(...)
-- minimap_button.lua -- minimap button on LibDBIcon: click -- show/hide the
-- item window, right click -- the settings. The library stores the position itself in settings.minimap.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local MinimapButton = {}
ns.Components.MinimapButton = MinimapButton

local NAME = "PRR"   -- LibDBIcon id; the title players see is ADDON_TITLE
local ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local TOOLTIP_TITLE_COLOR = { 1, 0.82, 0 }
local TOOLTIP_HINT_COLOR = { 0.8, 0.8, 0.8 }
local dataBroker = LibStub:GetLibrary("LibDataBroker-1.1", true)
local dbIcon = LibStub:GetLibrary("LibDBIcon-1.0", true)

local launcher = dataBroker and dataBroker:NewDataObject(NAME, {
    type = "launcher",
    icon = ICON,
    OnClick = function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Commands.Run("options")
            return
        end
        ns.Commands.Run("show")
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine(ns.Constants.ADDON_TITLE,
            TOOLTIP_TITLE_COLOR[1], TOOLTIP_TITLE_COLOR[2], TOOLTIP_TITLE_COLOR[3])
        tooltip:AddLine(Text("minimap.click"),
            TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
        tooltip:AddLine(Text("minimap.right_click"),
            TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
        tooltip:AddLine(Text("minimap.drag"),
            TOOLTIP_HINT_COLOR[1], TOOLTIP_HINT_COLOR[2], TOOLTIP_HINT_COLOR[3])
    end,
})

-- After settings are loaded: the library writes into the passed table right away.
function MinimapButton.Setup()
    if not (launcher and dbIcon) then
        ns.Utilities.Print(Text("minimap.no_library"))
        return
    end
    if not dbIcon:IsRegistered(NAME) then
        dbIcon:Register(NAME, launcher, ns.db.settings.minimap)
    end
end

function MinimapButton.SetHidden(hidden)
    ns.db.settings.minimap.hide = hidden
    if not dbIcon then return end
    if hidden then
        dbIcon:Hide(NAME)
    else
        dbIcon:Show(NAME)
    end
end
end)
