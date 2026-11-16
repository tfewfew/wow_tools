local ADDON, ns = "ForeverFaces", WoWTools.foreverFaces
local L = ns.L

-- A button on the edge of the minimap, made with LibDBIcon so that minimap
-- button collectors (Leatrix Plus and others) take it in with its own
-- tooltip. Left-click opens the window, right-click turns the addon on or
-- off. The icon goes grey while the addon is off.

local ICON = "Interface\\Icons\\INV_Misc_Head_Human_01"
local DBIcon = LibStub("LibDBIcon-1.0")

local broker
local brokerInfo = {
	type = "launcher",
	label = L.TITLE,
	icon = ICON,
	OnClick = function(_, mouse)
		if mouse == "RightButton" then
			ns.SetEnabled(not ns.DB().enabled)
		else
			ns.ToggleWindow()
		end
	end,
	OnTooltipShow = function(tip)
		tip:AddLine(L.TITLE, 1, 1, 1)
		tip:AddLine(L.MM_LEFT, 0.8, 0.8, 0.8)
		tip:AddLine(L.MM_RIGHT, 0.8, 0.8, 0.8)
	end,
}

-- LibDBIcon keeps the spot in db.minimapIcon; a reset can give a new table.
local registeredWith, shown

-- Shown or hidden by the setting, grey while the addon is off. Runs on every
-- change of state (each fight too), so Show and Hide only go out when the
-- setting really changed: Show puts the button back on the minimap's edge,
-- out of a collector that took it in.
function ns.UpdateMinimapButton()
	if not broker then broker = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON, brokerInfo) end
	local db = ns.DB()
	db.minimapIcon = db.minimapIcon or { minimapPos = db.minimapAngle }
	db.minimapIcon.hide = not db.minimapShow
	if registeredWith ~= db.minimapIcon then
		if registeredWith then
			DBIcon:Refresh(ADDON, db.minimapIcon)
		else
			DBIcon:Register(ADDON, broker, db.minimapIcon)
		end
		registeredWith, shown = db.minimapIcon, db.minimapShow
	end
	if db.minimapShow ~= shown then
		shown = db.minimapShow
		if shown then DBIcon:Show(ADDON) else DBIcon:Hide(ADDON) end
	end
	local button = DBIcon:GetMinimapButton(ADDON)
	if button and button.icon then button.icon:SetDesaturated(not db.enabled) end
end
