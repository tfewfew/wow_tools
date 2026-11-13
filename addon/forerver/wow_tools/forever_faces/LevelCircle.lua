local ns = WoWTools.foreverFaces

-- The game's own target frame bug, not a portrait one. When the target is a
-- companion pet, the game hides the level circle (Forever has no pet battle
-- badge to show there) and only shows it again on a /reload, so every target
-- after the first pet gets a bare level number. The circle is put back for any
-- target that is not a pet; a pet keeps the game's look.

-- a secret answer counts as no: testing a secret value is an error
local function Yes(v)
	if issecretvalue and issecretvalue(v) then return false end
	return v and true or false
end

local function IsPet(unit)
	return Yes(UnitIsWildBattlePet(unit)) or Yes(UnitIsBattlePetCompanion(unit))
end

local function Hook(frame)
	if not (frame and frame.CheckBattlePet) then return end
	local main = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
	local circle = main and main.LevelBackgroundCircle
	-- only a frame the game itself gives a circle
	if not (circle and circle:IsShown()) then return end
	hooksecurefunc(frame, "CheckBattlePet", function(self)
		if self.unit and not IsPet(self.unit) then
			circle:Show()
		end
	end)
end

function ns.InitLevelCircle()
    Hook(TargetFrame)
    Hook(FocusFrame)
end
