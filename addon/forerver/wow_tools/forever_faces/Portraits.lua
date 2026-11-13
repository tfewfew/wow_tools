local ns = WoWTools.foreverFaces

-- The game draws a portrait by handing a texture and a unit to
-- SetPortraitTexture. That call is hooked: each portrait texture gets one
-- PlayerModel of its own, laid over the texture, and the flat picture is made
-- invisible while the model shows.
--
-- On Forever every portrait that matters is round: the unit frames, the party
-- frames and the portrait of a quest, gossip, merchant or trainer window are
-- all masked to a circle and framed by ring art (the trade window's other
-- player has a square texture, but the game's picture in it is round too,
-- so it gets the same circle). Models can't be masked: a
-- model is a square and would show a straight edge across the circle. So the
-- model gets a dark disc behind it and a soft dark fade over its edges
-- (textures, which can be masked to the circle). On a unit frame it is also
-- slid under the ring art (see Levels); in a window it stays small enough for
-- its corners to stay inside the circle.
--
-- The flat picture comes back whenever the model can't be shown: the unit is
-- gone or out of sight, the model has not loaded, the game put a plain
-- picture on the texture (book icon, class icon), or the part is switched off.
-- State is kept in local tables keyed by texture, nothing is written onto
-- Blizzard frames.

local MIN_SIZE = 30     -- smaller portraits stay flat
local SIZE_MIN, SIZE_MAX, SIZE_DEFAULT = 0.70, 0.85, 80 -- size of the face in a round portrait
-- A model is a square that can't be cut round: at this size (of the circle's
-- width) its corners reach just under the ring art around the circle, not past
-- it, and the dark edge between the model and the ring stays thin. A bigger
-- face is shown by bringing the camera closer, not by a bigger square. On a
-- window's portrait, which has no ring over it, the square stays at SIZE_MIN.
local SQUARE = 0.85 -- the model square on a unit frame, whatever the face size: the dark edge starts at its sides
local FADE_EDGE = 0.70  -- media/fade.tga is fully opaque from this share of its radius out
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FADE = "Interface\\AddOns\\wow_tools\\forever_faces\\media\\fade"
local DARK = { 0.04, 0.04, 0.06, 1 }
local TINT_SHARE = 0.40 -- how much of the unit's colour the background takes (the rest stays DARK)
local LOAD_CHECK = 0.25 -- seconds; a cached model may never fire OnModelLoaded
local RETRIES = 3        -- load checks, and retries of a failed load out of combat
local RETRY_DELAY = 1    -- seconds between those retries

local entries = {} -- [texture] = { unit, guid, alpha, round, framed, model, back, cover, fade, shade, tint, ring, desat, r, g, b, dirty, loaded, checking, loadTime, shown, hiding, tinted, blocked, w, h }
local Swapped -- defined with the events below
local Idle -- a party model's own idle loop, defined before Build
local pending = {} -- [texture] = true, waiting for combat to end
local hooked = {}

local function DB() return ns.DB() end

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- A test on a unit that may come back secret: a secret answer counts as no.
local function Is(fn, unit)
	if not fn then return false end
	local v = fn(unit)
	if Secret(v) then return false end
	return v and true or false
end

-- States the model is shown grey for, like the game's own picture (dead,
-- ghost, tapped, offline); a dead mob's picture the game leaves untinted.
local function Tinted(unit)
	return Is(UnitIsDeadOrGhost, unit) or Is(UnitIsTapDenied, unit)
		or (Is(UnitIsPlayer, unit) and UnitIsConnected and not Is(UnitIsConnected, unit))
end

local function Category(unit)
	unit = unit:lower()
	if unit == "npc" or unit == "questnpc" then return "npc" end
	if unit:find("^party") or unit:find("^raid") then return "party" end
	return "units"
end

-- the saved portrait size, kept inside the range that looks right
function ns.Size()
	local size = tonumber(DB().size) or SIZE_DEFAULT
	return math.min(SIZE_MAX * 100, math.max(SIZE_MIN * 100, size))
end

local function BigEnough(texture)
	local w, h = texture:GetSize()
	return w and h and math.min(w, h) >= MIN_SIZE
end

local function Wanted(texture, e)
	local db = DB()
	if not db or not db.enabled or not e.unit then return false end
	if not db[Category(e.unit)] then return false end
	if not texture:IsShown() or not BigEnough(texture) then return false end
	return UnitExists(e.unit) and UnitIsVisible(e.unit)
end

-- The game's tint on the picture (grey dead, blue ghost, red low health,
-- desaturated offline) goes onto the model: grey as the model's desaturation,
-- a colour multiplied over it.
local function ApplyTint(e)
	if not e.model then return end
	e.tinted = e.desat or (e.unit and Tinted(e.unit)) or false
	if e.model.SetDesaturation then e.model:SetDesaturation(e.tinted and 1 or 0) end
	local r, g, b = e.r or 1, e.g or 1, e.b or 1
	local lo, hi = math.min(r, g, b), math.max(r, g, b)
	local colored = lo < 0.99
	-- A multiplied (MOD) texture ignores its mask and would darken the whole
	-- square behind the ring; a plain overlay keeps to the circle. Grey is
	-- exact as black over the model, a colour is laid over it half-way.
	if colored then
		if hi - lo < 0.01 then
			e.tint:SetColorTexture(0, 0, 0, 1 - lo)
		else
			e.tint:SetColorTexture(r, g, b, 0.55)
		end
	end
	e.shade:SetShown(colored and e.shown)
end

-- The background's colour: dark, or (when the player asks for it) a dark shade
-- of the unit's colour: a player's class colour, an NPC's the colour the game
-- gives its name (red hostile, yellow neutral, green friendly). A secret
-- answer stays dark.
local function BackColor(unit)
	local r, g, b = DARK[1], DARK[2], DARK[3]
	if not (DB().classColor and unit) then return r, g, b end
	local cr, cg, cb
	if Is(UnitIsPlayer, unit) then
		local class = UnitClassBase and UnitClassBase(unit)
		-- a secret is checked before any test on it: testing one is an error
		if Secret(class) then class = nil end
		local color = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
		if color then cr, cg, cb = color.r, color.g, color.b end
	elseif UnitSelectionColor then
		cr, cg, cb = UnitSelectionColor(unit)
	end
	if Secret(cr) or Secret(cg) or Secret(cb) or not (cr and cg and cb) then return r, g, b end
	local s = TINT_SHARE
	return r + (cr - r) * s, g + (cg - g) * s, b + (cb - b) * s
end

-- The game keeps some units' identity from addons (SetUnit then fails); a
-- secret answer counts as hidden.
local function Hidden(unit)
	local fn = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
	if not fn then return false end
	local v = fn(unit)
	if Secret(v) then return true end
	return v and true or false
end

-- A unit frame (player, target, focus, pet, party ...) is a secure unit button
-- that carries a "unit" attribute; its portrait sits one or two frames below
-- it. Windows that also draw a unit's portrait (character, talents, inspect,
-- NPC dialogues) have no such attribute.
local function OnUnitFrame(texture)
	local frame = texture:GetParent()
	for _ = 1, 3 do
		if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end
		if frame.GetAttribute and frame:GetAttribute("unit") then return true end
		frame = frame:GetParent()
	end
	return false
end

-- Only for the load check below: the model is cleared before a new unit, so
-- a file ID is the new unit's.
local function Loaded(model)
	if not model.GetModelFileID then return true end
	local id = model:GetModelFileID()
	return id ~= nil and id ~= 0
end

-- Showing --------------------------------------------------------------------------

local function Flat(texture)
	local e = entries[texture]
	if not e then return end
	-- already flat: the game redraws some portraits every frame
	if not e.shown and not (e.model and e.model:IsShown()) then return end
	if e.model then
		e.model:SetAlpha(0)
		e.model:Hide()
		e.back:Hide()
		e.cover:Hide()
		e.shade:Hide()
		if e.ring then e.ring:Hide() end
	end
	e.shown = false
	e.hiding = true
	texture:SetAlpha(e.alpha)
	e.hiding = false
end

local function Show3D(texture)
	local e = entries[texture]
	if e.showing then return end
	-- showing a model can fire its OnModelLoaded at once, which comes back here
	e.showing = true
	if not e.model:IsShown() then e.model:Show() end
	e.showing = false
	e.model:SetAlpha(1)
	e.back:SetShown(DB().background)
	local r, g, b = BackColor(e.unit)
	e.disc:SetColorTexture(r, g, b, 1)
	e.fade:SetVertexColor(r, g, b, 1)
	e.cover:SetShown(e.round and DB().background)
	if e.ring then e.ring:Show() end
	e.shown = true
	ApplyTint(e)
	e.hiding = true
	texture:SetAlpha(0)
	e.hiding = false
end

-- The portrait's own frame holds the ring art, and on a unit frame the level
-- badge and the bars sit in sibling frames. Our frames go under all of that,
-- so the ring and the badge are drawn over the model:
--   back (dark disc) < model < cover (soft fade) < the unit frame's parts.
-- A unit frame lives in its own strata (LOW); one strata down is under every
-- part of it whatever their levels are (the player frame sits at level 1-2,
-- with no room below). A window (character, talents, NPC dialogues) keeps our
-- frames on top of its portrait: one strata down would put them under the
-- window's own background.
local STRATA_BELOW = {
	LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
	FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG",
}

local function Levels(texture, e)
	local host = texture:GetParent()
	local level = host:GetFrameLevel()
	local below = STRATA_BELOW[host:GetFrameStrata()]
	if below and e.framed then
		e.back:SetFrameStrata(below)
		e.model:SetFrameStrata(below)
		e.cover:SetFrameStrata(below)
		e.shade:SetFrameStrata(below)
		e.back:SetFrameLevel(1)
		e.model:SetFrameLevel(2)
		e.cover:SetFrameLevel(3)
		e.shade:SetFrameLevel(4)
		return
	end
	e.back:SetFrameLevel(level + 1)
	e.model:SetFrameLevel(level + 2)
	e.cover:SetFrameLevel(level + 3)
	e.shade:SetFrameLevel(level + 4)
	if e.ring then e.ring:SetFrameLevel(level + 5) end
end

local function Layout(texture, e)
	local model = e.model
	model:ClearAllPoints()
	if e.round then
		local w, h = texture:GetSize()
		local d = math.min(w, h)
		local fill = ns.Size() / 100
		-- on top of a window's ring the model's corners must stay inside the circle
		if not e.framed then fill = SIZE_MIN end
		-- the square stays inside the circle; the camera comes closer for a bigger face
		local square = e.framed and SQUARE or SIZE_MIN
		e.camScale = square / fill
		model:SetPoint("CENTER", texture, "CENTER")
		model:SetSize(d * square, d * square)
		model:SetCamDistanceScale(e.camScale)
		-- The fade picture is opaque from FADE_EDGE of its radius out. It stays the
		-- size of the portrait (a bigger picture runs past the game's mask, whose
		-- edge pixels then smear outward as dark streaks) and is zoomed with
		-- texture coordinates so its opaque edge lands on the model's edge.
		local half = 0.5 * FADE_EDGE / square
		e.fade:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
	else
		model:SetAllPoints(texture)
	end
	Levels(texture, e)
end

-- A party member is often behind the camera, where the game doesn't animate
-- them; a model tied to that (SetUnit's blend) stands still. Party models are
-- loaded on their own and play the idle loop themselves.
local function OwnAnimation(unit)
	return unit and Category(unit) == "party"
end

Idle = function(e)
	if e.model and OwnAnimation(e.unit) and e.model.SetAnimation then pcall(e.model.SetAnimation, e.model, 0) end
end

local function Build(texture, e)
	local host = texture:GetParent()

	local back = CreateFrame("Frame", nil, host)
	back:SetAllPoints(texture)
	local disc = back:CreateTexture(nil, "BACKGROUND")
	disc:SetAllPoints()
	disc:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
	back:Hide()

	local model = CreateFrame("PlayerModel", nil, host)
	model:SetAlpha(0)
	model:Hide()
	model:SetScript("OnModelLoaded", function()
		local entry = entries[texture]
		if not entry then return end
		entry.loaded = true
		Idle(entry)
		if Wanted(texture, entry) then Show3D(texture) end
	end)
	-- hidden (a low-health tint, the frame closed) the model stays loaded, so it
	-- comes back without a reload; a new unit or new looks still reload it
	if model.SetKeepModelOnHide then model:SetKeepModelOnHide(true) end

	-- above the model: fades its square edges into the dark disc
	local cover = CreateFrame("Frame", nil, host)
	cover:SetAllPoints(texture)
	local fade = cover:CreateTexture(nil, "OVERLAY")
	fade:SetAllPoints(texture)
	fade:SetTexture(FADE)
	fade:SetVertexColor(DARK[1], DARK[2], DARK[3], DARK[4])
	cover:Hide()

	-- on top: the game's colour tint (grey tapped, red low health, blue ghost)
	-- laid over the model (see ApplyTint)
	local shade = CreateFrame("Frame", nil, host)
	shade:SetAllPoints(texture)
	local tint = shade:CreateTexture(nil, "OVERLAY")
	tint:SetAllPoints(texture)
	tint:SetColorTexture(0, 0, 0, 0)
	shade:Hide()

	-- A window can keep its ring art in the portrait's own frame (the trade
	-- window's other player): our frames, children of that frame, would cover
	-- it. A copy of that ring goes on top of the model.
	local ring
	if not e.framed then
		local RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
		local layer, sub = texture:GetDrawLayer()
		local rank = (RANK[layer] or 0) * 100 + (sub or 0)
		for _, r in ipairs({ host:GetRegions() }) do
			if r ~= texture and r.IsObjectType and r:IsObjectType("Texture") and r.GetAtlas then
				local atlas = r:GetAtlas()
				local rl, rs = r:GetDrawLayer()
				if atlas and atlas:find("Portrait") and (RANK[rl] or 0) * 100 + (rs or 0) > rank then
					ring = ring or CreateFrame("Frame", nil, host)
					local copy = ring:CreateTexture(nil, "OVERLAY")
					copy:SetAtlas(atlas)
					for i = 1, r:GetNumPoints() do copy:SetPoint(r:GetPoint(i)) end
					copy:SetSize(r:GetSize())
				end
			end
		end
		if ring then ring:Hide() end
	end

	-- the same shape the game cuts the portrait with: its own mask, copied
	if e.round then
		local own = texture.GetMaskTexture and texture:GetMaskTexture(1)
		for _, region in ipairs({ disc, fade, tint }) do
			local mask = region:GetParent():CreateMaskTexture()
			local atlas = own and own.GetAtlas and own:GetAtlas()
			if atlas then
				mask:SetAtlas(atlas)
			else
				mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			end
			if own and own:GetNumPoints() > 0 then
				for i = 1, own:GetNumPoints() do mask:SetPoint(own:GetPoint(i)) end
				mask:SetSize(own:GetSize())
			else
				mask:SetAllPoints(texture)
			end
			region:AddMaskTexture(mask)
		end
	end

	e.model, e.back, e.cover, e.fade, e.shade, e.tint, e.ring, e.disc = model, back, cover, fade, shade, tint, ring, disc
end

local function Refresh(texture, force)
	local e = entries[texture]
	if not e then return end
	if not Wanted(texture, e) then
		Flat(texture)
		return
	end

	if not e.model then
		local parent = texture:GetParent()
		if InCombatLockdown() and parent:IsProtected() then
			pending[texture] = true
			Flat(texture)
			return
		end
		Build(texture, e)
		e.dirty = true
	end

	-- the target of target is redrawn every frame: nothing new, nothing to do
	local w, h = texture:GetSize()
	local resized = w ~= e.w or h ~= e.h
	if e.shown and not e.dirty and not force and not resized then return end

	-- no model for a hidden identity: the picture stays until the next swap
	-- or the end of combat
	if e.dirty and (e.blocked or Hidden(e.unit)) then
		pending[texture] = true
		Flat(texture)
		-- out of combat a failed load may just have come too early: try again
		if e.blocked and not InCombatLockdown() and not e.retrying and (e.retries or 0) < RETRIES then
			e.retrying = true
			e.retries = (e.retries or 0) + 1
			C_Timer.After(RETRY_DELAY, function()
				local entry = entries[texture]
				if not entry then return end
				entry.retrying = nil
				if entry.blocked and not InCombatLockdown() then
					entry.blocked = nil
					pending[texture] = nil
					Refresh(texture)
				end
			end)
		end
		return
	end

	if force or resized then
		e.w, e.h = w, h
		Layout(texture, e)
	end
	local model = e.model
	-- a new unit: nothing of the last one's model may show (cleared before
	-- Show, which can fire OnModelLoaded)
	local fresh = e.dirty and not e.shown
	if fresh then model:ClearModel() end
	if not model:IsShown() then model:Show() end
	if e.dirty then
		e.dirty = false
		e.loaded = false
		local ok, set = pcall(model.SetUnit, model, e.unit, not OwnAnimation(e.unit))
		if not ok or (not Secret(set) and set == false) then
			e.dirty, e.blocked = true, true
			model:ClearModel()
			pending[texture] = true
			Flat(texture)
			return
		end
		-- the game's update and our event may both ask for the same new unit
		if fresh then e.loadTime = GetTime() end
		model:SetPortraitZoom(1)
		model:SetCamDistanceScale(e.camScale or 1)
		model:SetPosition(0, 0, 0)
	end

	-- a model already on screen stays while the same unit loads again
	if e.loaded or e.shown then
		Show3D(texture)
	elseif not e.checking then
		-- keep the flat picture until the model is there; one check at a time,
		-- a few times over (a cached model may never say it loaded)
		e.checking = true
		local tries = 0
		local function Check()
			local entry = entries[texture]
			if not entry then return end
			tries = tries + 1
			if entry.model and not entry.loaded and not entry.dirty and Loaded(entry.model) then
				entry.loaded = true
				Idle(entry)
			end
			if not entry.loaded and not entry.dirty and tries < RETRIES then
				C_Timer.After(LOAD_CHECK * tries * 2, Check)
				return
			end
			entry.checking = nil
			if entry.loaded and Wanted(texture, entry) then Show3D(texture) end
		end
		C_Timer.After(LOAD_CHECK, Check)
	end
end

-- Hooks ---------------------------------------------------------------------------------

local function Hook(texture)
	if hooked[texture] then return end
	hooked[texture] = true

	-- the game put a plain picture here (book, class or buyback icon)
	local function Picture()
		local e = entries[texture]
		if e then
			e.unit = nil
			Flat(texture)
		end
	end
	hooksecurefunc(texture, "SetTexture", Picture)
	hooksecurefunc(texture, "SetAtlas", Picture)

	-- the game sets the portrait's alpha now and then; the flat picture gets it
	-- back later, under a model the texture stays hidden
	hooksecurefunc(texture, "SetAlpha", function(_, alpha)
		local e = entries[texture]
		if not e or e.hiding then return end
		if not Secret(alpha) and type(alpha) == "number" then e.alpha = alpha end
		if e.shown then
			e.hiding = true
			texture:SetAlpha(0)
			e.hiding = false
		end
	end)

	-- the game tints the picture to show a state; the model is tinted the same
	local function Tint()
		local e = entries[texture]
		-- only unit frames tint their portrait to show a state
		if not e or not e.framed then return end
		e.desat = false
		if texture.IsDesaturated then
			local d = texture:IsDesaturated()
			if not Secret(d) and d then e.desat = true end
		end
		e.r, e.g, e.b = 1, 1, 1
		if texture.GetVertexColor then
			local r, g, b = texture:GetVertexColor()
			if not (Secret(r) or Secret(g) or Secret(b)) and r and g and b then
				e.r, e.g, e.b = r, g, b
			end
		end
		ApplyTint(e)
	end
	hooksecurefunc(texture, "SetVertexColor", Tint)
	if texture.SetDesaturated then hooksecurefunc(texture, "SetDesaturated", Tint) end
	if texture.SetDesaturation then hooksecurefunc(texture, "SetDesaturation", Tint) end

	local function Sync() Refresh(texture) end
	hooksecurefunc(texture, "Show", Sync)
	hooksecurefunc(texture, "Hide", Sync)
	hooksecurefunc(texture, "SetShown", Sync)
end

local function OnPortrait(texture, unit)
	if type(texture) ~= "table" or type(unit) ~= "string" or not texture.GetObjectType then return end
	if texture.IsForbidden and texture:IsForbidden() then return end
	-- the character button of the game menu draws your portrait too; a model
	-- there would not fade with a hidden menu bar
	if CharacterMicroButton and texture == CharacterMicroButton.Portrait then return end
	-- nor on the side tabs of the character and inspect windows, which are buttons
	local parent = texture:GetParent()
	if parent and parent.InitializeIconAnchoring then return end
	if PaperDollSidebarTab1 and texture == PaperDollSidebarTab1.Icon then return end
	local e = entries[texture]
	if not e then
		if not BigEnough(texture) then return end
		e = {
			alpha = texture:GetAlpha(),
			-- the game's picture is always round; a square texture with no mask of
			-- its own (the trade window's other player) gets the plain circle
			round = true,
			framed = OnUnitFrame(texture),
		}
		entries[texture] = e
		Hook(texture)
	end
	-- the game redraws portraits all the time; load a model only for a new unit.
	-- Until the new one is there the game's fresh flat picture shows, not the
	-- previous unit's model.
	local guid = UnitGUID(unit)
	-- a hidden identity can't be compared; a new unit is then told by the
	-- target / focus / group events instead (see Swapped)
	if Secret(guid) then guid = nil end
	if e.unit ~= unit or e.guid ~= guid then
		Flat(texture)
		e.unit, e.guid, e.events = unit, guid, nil
		e.dirty, e.blocked, e.retries = true, nil, nil
	end
	-- a party frame can draw its portrait before it is set up as a unit frame
	if not e.framed and OnUnitFrame(texture) then
		e.framed = true
		e.w = nil -- laid out again as a unit frame
	end
	Refresh(texture)
end
ns.OnPortrait = OnPortrait

-- UnitFramePortrait_Update can finish with a class atlas, including EasyFrames'
-- post-hook. Bind the unit frame after that update as well as the texture call.
local function OnUnitPortrait(frame)
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	local unit = frame.unit
	if Secret(unit) or type(unit) ~= "string" or not frame.portrait then return end
	OnPortrait(frame.portrait, unit)
end

local refreshQueued = false
local function QueueUnitPortraits()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		OnUnitPortrait(PlayerFrame)
		OnUnitPortrait(TargetFrame)
		OnUnitPortrait(FocusFrame)
		OnUnitPortrait(PetFrame)
		OnUnitPortrait(TargetFrameToT)
		OnUnitPortrait(FocusFrameToT)
	end)
end

-- /ff debug: the real numbers of every portrait, so the look can be tuned to
-- the game's frames instead of guessed.
function ns.Debug()
	local function name(f) return f and (f.GetDebugName and f:GetDebugName() or f:GetName()) or "-" end
	local function lvl(f) return f and (f:GetFrameStrata() .. " " .. f:GetFrameLevel()) or "-" end
	local count = 0
	for texture, e in pairs(entries) do
		if e.unit and texture:IsVisible() then
			count = count + 1
			local w, h = texture:GetSize()
			ns.Print(("%s [%s] %.1fx%.1f round=%s shown=%s"):format(name(texture), e.unit, w, h, tostring(e.round), tostring(e.shown)))
			local own = texture.GetMaskTexture and texture:GetMaskTexture(1)
			if own then
				local mw, mh = own:GetSize()
				ns.Print(("  mask %s %.1fx%.1f"):format(own.GetAtlas and own:GetAtlas() or "file", mw, mh))
			end
			local host = texture:GetParent()
			local unitFrame = host:GetParent()
			ns.Print(("  host %s %s, unit frame %s %s"):format(name(host), lvl(host), name(unitFrame), lvl(unitFrame)))
			if unitFrame then
				for _, child in ipairs({ unitFrame:GetChildren() }) do
					if not (child.IsForbidden and child:IsForbidden()) then
						ns.Print(("    sibling %s %s"):format(name(child), lvl(child)))
					end
				end
			end
			if e.model then
				local mw = e.model:GetWidth()
				ns.Print(("  ours: back %s, model %s (%.1f), cover %s"):format(lvl(e.back), lvl(e.model), mw, lvl(e.cover)))
			end
		end
	end
	if count == 0 then ns.Print("no 3D portraits on screen") end
end

-- settings change the look; a part switched off and on again loads its models anew
function ns.ApplyAll()
	QueueUnitPortraits()
	for texture, e in pairs(entries) do
		e.w = nil -- laid out again
		if texture:IsVisible() then
			Refresh(texture, true)
		else
			-- a closed window: the picture, and a new model once it is drawn again
			Flat(texture)
			e.dirty = true
		end
	end
end

local function Same(a, b)
	if a == b then return true end
	local same = UnitIsUnit(a, b)
	return not Secret(same) and same and true or false
end

-- Unit events come for each token of a unit (target, party1, nameplate3 ...),
-- so a portrait of such a token only needs its own; one with a token that
-- gets no events (target of target, an NPC window) is compared.
local EVENT_UNITS = { "^player$", "^target$", "^focus$", "^pet$", "^party%d$", "^partypet%d$", "^raid%d+$", "^boss%d$", "^arena%d$" }
local function GetsEvents(unit)
	for _, pattern in ipairs(EVENT_UNITS) do
		if unit:find(pattern) then return true end
	end
	return false
end
local function Concerns(e, unit)
	if e.unit == unit then return true end
	if e.events == nil then e.events = GetsEvents(e.unit) end
	return not e.events and Same(e.unit, unit)
end

-- new gear or shape: load the model again; a portrait update needs no reload

local function UnitChanged(unit, reload)
	if not unit then return end
	for texture, e in pairs(entries) do
		if e.unit and Concerns(e, unit) then
			if reload then e.dirty = true end
			-- a closed window loads it when it is drawn again
			if texture:IsVisible() then Refresh(texture) end
		end
	end
end

-- Another unit on a portrait whose identity is hidden (no GUID to compare):
-- the flat picture first, then the new model.
Swapped = function(pattern)
	for texture, e in pairs(entries) do
		-- not when the game's own update for this event loaded it fresh already
		if e.unit and e.guid == nil and e.unit:find(pattern) and e.loadTime ~= GetTime() then
			Flat(texture)
			e.dirty, e.blocked = true, nil
			Refresh(texture)
		end
	end
end

-- Died, released, came back, went offline, got tapped: only a change of that
-- look retints the model (health events come often).
local function StateChanged(unit)
	if not unit then return end
	for texture, e in pairs(entries) do
		if e.unit and e.model and Concerns(e, unit) and texture:IsVisible() then
			if (e.desat or Tinted(e.unit)) ~= e.tinted then ApplyTint(e) end
		end
	end
end

function ns.InitPortraits()
	hooksecurefunc("SetPortraitTexture", OnPortrait)
	hooksecurefunc("UnitFramePortrait_Update", OnUnitPortrait)
	QueueUnitPortraits()

	-- The Edit Mode party background sits at level 1 of the party frames'
	-- strata, where the models (one strata down) would be under it. It is a
	-- plain backdrop, so it moves to the bottom instead, after the game has
	-- placed it each time it shows.
	local bg = PartyFrame and PartyFrame.Background
	if bg and not (bg.IsProtected and bg:IsProtected()) then
		bg:HookScript("OnShow", function(self)
			self:SetFrameStrata("BACKGROUND")
			self:SetFrameLevel(0)
		end)
		if bg:IsShown() then
			bg:SetFrameStrata("BACKGROUND")
			bg:SetFrameLevel(0)
		end
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("UNIT_MODEL_CHANGED")
	watcher:RegisterEvent("UNIT_PORTRAIT_UPDATE")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_FACTION",
		"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", "UNIT_PET", "GROUP_ROSTER_UPDATE" }) do
		watcher:RegisterEvent(event)
	end
	watcher:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "UNIT_CONNECTION" or event == "UNIT_FACTION" then
			StateChanged(unit)
		elseif event == "PLAYER_TARGET_CHANGED" then
			Swapped("^target")
			QueueUnitPortraits()
		elseif event == "PLAYER_FOCUS_CHANGED" then
			Swapped("^focus")
			QueueUnitPortraits()
		elseif event == "PLAYER_ENTERING_WORLD" then
			QueueUnitPortraits()
		elseif event == "UNIT_TARGET" then
			if unit == "target" then Swapped("^targettarget$") end
		elseif event == "UNIT_PET" then
			if unit == "player" then Swapped("^pet$") end
		elseif event == "GROUP_ROSTER_UPDATE" then
			Swapped("^party")
		elseif event == "PLAYER_REGEN_ENABLED" then
			-- a refresh may put a texture back on the list
			local list = {}
			for texture in pairs(pending) do list[#list + 1] = texture end
			wipe(pending)
			for _, texture in ipairs(list) do
				local e = entries[texture]
				if e then e.blocked = nil end
				Refresh(texture)
			end
		else
			UnitChanged(unit, event == "UNIT_MODEL_CHANGED")
		end
	end)
end
