local ns = WoWTools.foreverFaces
local L = ns.L

-- The settings window: one dark panel with a gold accent, built from plain
-- colour textures so it needs no Blizzard templates. /ff and the host's
-- third-party settings page open it.

local WIDTH = 380
local PAD = 18
local INNER = WIDTH - PAD * 2

local C = {
	bg = { 0.071, 0.086, 0.133, 0.97 },
	panel = { 0.106, 0.125, 0.192, 1 },
	raised = { 0.145, 0.170, 0.255, 1 },
	hover = { 0.185, 0.215, 0.315, 1 },
	line = { 1, 1, 1, 0.07 },
	text = { 0.96, 0.97, 0.99, 1 },
	dim = { 0.71, 0.74, 0.82, 1 },
	muted = { 0.52, 0.56, 0.65, 1 },
	accent = { 0.92, 0.74, 0.38, 1 },
	onAccent = { 0.06, 0.07, 0.10, 1 },
	on = { 0.42, 0.85, 0.60, 1 },
	warn = { 0.98, 0.75, 0.30, 1 },
	off = { 0.55, 0.59, 0.68, 1 },
	danger = { 0.96, 0.45, 0.45, 1 },
}

local win
local widgets = {}

-- Helpers ----------------------------------------------------------------

local function Tex(parent, color, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return t
end

local function Paint(t, color)
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

local function Border(frame, color)
	local edges = {}
	for i, spec in ipairs({
		{ "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
	}) do
		local t = Tex(frame, color, "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then t:SetHeight(1) else t:SetWidth(1) end
		edges[i] = t
	end
	return edges
end

local function Text(parent, template, color, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	fs:SetJustifyH("LEFT")
	-- Every label is one line in a fixed box: a long translation is cut with
	-- "..." instead of wrapping, so the window keeps its size in any language.
	if width then
		fs:SetWidth(width)
		fs:SetWordWrap(false)
		if fs.SetMaxLines then fs:SetMaxLines(1) end
	end
	return fs
end

local LINE = 16 -- height of one line of GameFontHighlight / GameFontNormal

local function SetTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- Switch -------------------------------------------------------------------

local function Switch(parent, onToggle)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(36, 18)
	b.track = Tex(b, C.raised, "ARTWORK")
	b.track:SetAllPoints()
	b.knob = Tex(b, C.text, "OVERLAY")
	b.knob:SetSize(14, 14)
	b.checked = false

	function b:SetChecked(on)
		self.checked = on and true or false
		self.knob:ClearAllPoints()
		if self.checked then
			self.knob:SetPoint("RIGHT", -2, 0)
			Paint(self.track, C.accent)
			Paint(self.knob, C.onAccent)
		else
			self.knob:SetPoint("LEFT", 2, 0)
			Paint(self.track, self:IsMouseOver() and C.hover or C.raised)
			Paint(self.knob, C.dim)
		end
	end

	b:SetScript("OnClick", function(self)
		if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
		onToggle(not self.checked)
	end)
	b:SetScript("OnEnter", function(self) if not self.checked then Paint(self.track, C.hover) end end)
	b:SetScript("OnLeave", function(self) if not self.checked then Paint(self.track, C.raised) end end)
	return b
end

-- Help lives in a tooltip on hover, so the window itself stays short.
-- body may be a function, for text that changes (the status line).
local function Tooltip(frame, title, body)
	frame:EnableMouse(true)
	frame:HookScript("OnEnter", function(self)
		local text = type(body) == "function" and body() or body
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
		if text and text ~= "" then GameTooltip:AddLine(text, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A row: label on the left, switch on the right, help in the tooltip.
local function ToggleRow(parent, y, label, help, key)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", PAD, y)
	row:SetWidth(INNER)

	row.label = Text(row, "GameFontHighlight", C.text, INNER - 52)
	row.label:SetPoint("LEFT")
	row.label:SetText(label)

	row.switch = Switch(row, function(on) ns.Set(key, on) end)
	row.switch:SetPoint("RIGHT")

	row:SetHeight(20)
	Tooltip(row, label, help)
	Tooltip(row.switch, label, help)
	row.key = key

	function row:SetActive(active)
		self:SetAlpha(active and 1 or 0.4)
		self.switch:EnableMouse(active)
	end
	return row, row:GetHeight()
end

-- Slider ---------------------------------------------------------------------

local function Slider(parent, y, label, help, key, min, max, format)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", PAD, y)
	row:SetWidth(INNER)

	row.label = Text(row, "GameFontHighlight", C.text, INNER - 90)
	row.label:SetPoint("TOPLEFT")
	row.label:SetText(label)

	row.value = Text(row, "GameFontHighlight", C.accent)
	row.value:SetPoint("TOPRIGHT")
	row.value:SetJustifyH("RIGHT")

	local s = CreateFrame("Slider", nil, row)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(INNER, 16)
	s:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -8)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouseWheel(true)

	s.track = Tex(s, C.raised, "BACKGROUND")
	s.track:SetPoint("LEFT")
	s.track:SetPoint("RIGHT")
	s.track:SetHeight(4)
	s.fill = Tex(s, C.accent, "ARTWORK")
	s.fill:SetPoint("LEFT")
	s.fill:SetHeight(4)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(C.text[1], C.text[2], C.text[3], 1)
	thumb:SetSize(8, 16)
	s:SetThumbTexture(thumb)

	local function Show(v)
		row.value:SetText(format(v))
		local frac = (max > min) and (v - min) / (max - min) or 0
		s.fill:SetWidth(math.max(1, frac * (INNER - 8) + 4))
	end

	s:SetScript("OnValueChanged", function(_, v, userInput)
		v = math.floor(v + 0.5)
		Show(v)
		if userInput then ns.Set(key, v) end
	end)
	s:SetScript("OnMouseWheel", function(self, delta)
		local v = math.min(max, math.max(min, (ns.DB()[key] or min) + delta))
		self:SetValue(v)
		ns.Set(key, v)
	end)

	function row:SetNumber(v)
		s:SetValue(v)
		Show(v)
	end
	function row:SetActive(active)
		self:SetAlpha(active and 1 or 0.4)
		s:EnableMouse(active)
		s:EnableMouseWheel(active)
	end

	local h = LINE + 8 + 16
	row:SetHeight(h)
	Tooltip(row, label, help)
	return row, h
end

-- Text button ----------------------------------------------------------------

local function TextButton(parent, label, onClick)
	local b = CreateFrame("Button", nil, parent)
	b.bg = Tex(b, C.raised, "ARTWORK")
	b.bg:SetAllPoints()
	Border(b, C.line)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	SetTextColor(b.text, C.dim)
	b:SetSize(b.text:GetStringWidth() + 28, 24)
	b:SetScript("OnClick", function()
		if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
		onClick()
	end)
	b:SetScript("OnEnter", function(self) Paint(self.bg, C.hover); SetTextColor(self.text, C.text) end)
	b:SetScript("OnLeave", function(self) Paint(self.bg, C.raised); SetTextColor(self.text, C.dim) end)
	return b
end

-- Close button: an X drawn from two rotated bars.
local function CloseButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	b.bars = {}
	for i, angle in ipairs({ math.rad(45), math.rad(-45) }) do
		local t = Tex(b, C.dim, "OVERLAY")
		t:SetSize(14, 2)
		t:SetPoint("CENTER")
		t:SetRotation(angle)
		b.bars[i] = t
	end
	local function Color(c) for _, t in ipairs(b.bars) do Paint(t, c) end end
	b:SetScript("OnEnter", function() Color(C.text) end)
	b:SetScript("OnLeave", function() Color(C.dim) end)
	b:SetScript("OnClick", function() parent:Hide() end)
	return b
end

-- Language menu --------------------------------------------------------------

local function LanguageMenu(parent)
	-- The language the window is in now; picking the game's own language
	-- stores nothing, so the addon keeps following the client.
	local current = ns.activeLocale
	local client = ns.ClientLocale()

	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(22)
	button.bg = Tex(button, C.panel, "ARTWORK")
	button.bg:SetAllPoints()
	Border(button, C.line)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 10, 0)
	SetTextColor(button.text, C.dim)

	-- One width for every language, so the header doesn't shift on a switch.
	local label, widest = "English", 0
	for _, lang in ipairs(ns.LANGUAGES) do
		if ns.LanguageAvailable(lang) then
			button.text:SetText(lang.name)
			widest = math.max(widest, button.text:GetStringWidth())
		end
		if lang.code == current then label = lang.name end
	end
	button.text:SetText(label)
	button:SetWidth(math.ceil(widest) + 36)
	local chevron = {}
	for i, angle in ipairs({ math.rad(-45), math.rad(45) }) do -- a "v" pointing down
		local t = Tex(button, C.dim, "OVERLAY")
		t:SetSize(6, 1.5)
		t:SetRotation(angle)
		chevron[i] = t
	end
	chevron[1]:SetPoint("CENTER", button, "RIGHT", -15, 0)
	chevron[2]:SetPoint("CENTER", button, "RIGHT", -11, 0)

	-- The list, and a catcher behind it that closes it on any outside click.
	local catcher = CreateFrame("Button", nil, parent)
	catcher:SetAllPoints(parent)
	catcher:SetFrameLevel(parent:GetFrameLevel() + 40)
	catcher:Hide()

	local menu = CreateFrame("Frame", nil, parent)
	menu:SetFrameLevel(parent:GetFrameLevel() + 50)
	menu:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
	menu.bg = Tex(menu, C.raised)
	menu.bg:SetAllPoints()
	Border(menu, C.line)
	menu:Hide()

	local entries = {}
	for _, lang in ipairs(ns.LANGUAGES) do
		if ns.LanguageAvailable(lang) then entries[#entries + 1] = lang end
	end

	local ITEM_H, width = 20, 120
	for i, entry in ipairs(entries) do
		local item = CreateFrame("Button", nil, menu)
		item:SetHeight(ITEM_H)
		item:SetPoint("TOPLEFT", 1, -4 - (i - 1) * ITEM_H)
		item:SetPoint("TOPRIGHT", -1, -4 - (i - 1) * ITEM_H)
		item.bg = Tex(item, C.raised, "ARTWORK")
		item.bg:SetAllPoints()
		item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		item.text:SetPoint("LEFT", 12, 0)
		item.text:SetText(entry.name)
		local selected = entry.code == current
		SetTextColor(item.text, selected and C.accent or C.text)
		width = math.max(width, item.text:GetStringWidth() + 32)
		item:SetScript("OnEnter", function(self) Paint(self.bg, C.hover) end)
		item:SetScript("OnLeave", function(self) Paint(self.bg, C.raised) end)
		item:SetScript("OnClick", function()
			menu:Hide()
			catcher:Hide()
			if not selected then ns.SetLanguage(entry.code ~= client and entry.code or nil) end
		end)
	end
	menu:SetSize(width, #entries * ITEM_H + 8)

	local function Close()
		menu:Hide()
		catcher:Hide()
	end
	catcher:SetScript("OnClick", Close)
	button:SetScript("OnClick", function()
		if menu:IsShown() then Close() else catcher:Show(); menu:Show() end
	end)
	button:SetScript("OnEnter", function(self) Paint(self.bg, C.hover); SetTextColor(self.text, C.text) end)
	button:SetScript("OnLeave", function(self) Paint(self.bg, C.panel); SetTextColor(self.text, C.dim) end)
	parent:HookScript("OnHide", Close)
	return button
end

-- Window -------------------------------------------------------------------

local function SavePosition()
	local point, _, relPoint, x, y = win:GetPoint(1)
	ns.DB().win = { point, relPoint, x, y }
end

local ROWS = { "units", "party", "npc", "background", "classColor" }

local function Refresh()
	if not win or not win:IsShown() then return end
	local db = ns.DB()
	local enabled = db.enabled

	widgets.enabled:SetChecked(enabled)
	widgets.showOn:SetAlpha(enabled and 1 or 0.4)
	for _, key in ipairs(ROWS) do
		widgets[key].switch:SetChecked(db[key])
		widgets[key]:SetActive(enabled)
	end
	widgets.minimap.switch:SetChecked(db.minimapShow)
	widgets.size:SetNumber(ns.Size())
	widgets.size:SetActive(enabled)
	widgets.classColor:SetActive(enabled and db.background)
end
ns.RefreshUI = Refresh

local function Build()
	win = CreateFrame("Frame", "ForeverFacesWindow", UIParent)
	win:SetWidth(WIDTH)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:Hide()
	if not tContains(UISpecialFrames, "ForeverFacesWindow") then
		tinsert(UISpecialFrames, "ForeverFacesWindow")
	end

	win.bg = Tex(win, C.bg)
	win.bg:SetAllPoints()
	Border(win, C.line)
	local top = Tex(win, C.accent, "ARTWORK")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(2)

	-- Header (drag handle)
	local header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(58)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() win:StartMoving() end)
	header:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		SavePosition()
	end)

	local title = Text(header, "GameFontNormalLarge", C.text)
	title:SetPoint("TOPLEFT", PAD, -16)
	title:SetText(L.TITLE)
	local subtitle = Text(header, "GameFontHighlightSmall", C.muted, INNER)
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	local version = ns.sourceVersion
	subtitle:SetText("v" .. version)

	-- Above the header, which takes the mouse for dragging.
	local close = CloseButton(win)
	close:SetPoint("TOPRIGHT", -10, -12)
	close:SetFrameLevel(header:GetFrameLevel() + 10)

	local language = LanguageMenu(win)
	language:SetPoint("TOPRIGHT", -40, -12)
	language:SetFrameLevel(header:GetFrameLevel() + 10)

	-- The addon's own on/off switch sits in the header; off dims the rest.
	widgets.enabled = Switch(win, function(on) ns.SetEnabled(on) end)
	widgets.enabled:SetPoint("RIGHT", language, "LEFT", -10, 0)
	widgets.enabled:SetFrameLevel(header:GetFrameLevel() + 10)
	Tooltip(widgets.enabled, L.ENABLED, L.ENABLED_HELP)

	local y = -66

	widgets.showOn = Text(win, "GameFontNormal", C.accent)
	widgets.showOn:SetPoint("TOPLEFT", PAD, y)
	widgets.showOn:SetText(L.SHOW_ON)
	y = y - LINE - 10

	local row, h
	row, h = ToggleRow(win, y, L.UNITS, L.UNITS_HELP, "units")
	widgets.units = row
	y = y - h - 10
	row, h = ToggleRow(win, y, L.PARTY, L.PARTY_HELP, "party")
	widgets.party = row
	y = y - h - 10
	row, h = ToggleRow(win, y, L.NPC, L.NPC_HELP, "npc")
	widgets.npc = row
	y = y - h - 18
	row, h = ToggleRow(win, y, L.BACKGROUND, L.BACKGROUND_HELP, "background")
	widgets.background = row
	y = y - h - 10
	row, h = ToggleRow(win, y, L.CLASS_COLOR, L.CLASS_COLOR_HELP, "classColor")
	widgets.classColor = row
	y = y - h - 10
	row, h = ToggleRow(win, y, L.MINIMAP, L.MINIMAP_HELP, "minimapShow")
	widgets.minimap = row
	y = y - h - 16

	-- limited to 70-85%: smaller looks lost in the ring, bigger lets the model's corners out of the ring
	widgets.size, h = Slider(win, y, L.SIZE, L.SIZE_HELP, "size", 70, 85, function(v)
		return L.SIZE_PCT:format(v)
	end)
	y = y - h - 18

	-- Footer
	local footerLine = Tex(win, C.line, "ARTWORK")
	footerLine:SetPoint("TOPLEFT", 0, y)
	footerLine:SetSize(WIDTH, 1)
	local footerBg = Tex(win, { 0, 0, 0, 0.18 }, "BORDER")
	footerBg:SetPoint("TOPLEFT", 0, y)
	footerBg:SetPoint("BOTTOMRIGHT")
	y = y - 12

	local reset = TextButton(win, L.RESET, function() ns.Reset() end)
	reset:SetPoint("TOPLEFT", PAD, y)

	-- Which command opens this window, at the right of the footer.
	local command = Text(win, "GameFontHighlightSmall", C.muted, INNER - reset:GetWidth() - 12)
	command:SetJustifyH("RIGHT")
	command:SetPoint("RIGHT", win, "TOPRIGHT", -PAD, y - 12)
	command:SetText(L.CMD_HINT .. " |cffebbd61/ff|r")
	y = y - 24 - 12

	win:SetHeight(-y)

	local pos = ns.DB().win
	if pos then
		win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		win:SetPoint("CENTER", 0, 60)
	end

	local fade = win:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.15)
	win:SetScript("OnShow", function()
		fade:Play()
		Refresh()
	end)
end

function ns.ToggleWindow()
	if not win then Build() end
	if win:IsShown() then win:Hide() else win:Show() end
end

-- After a language change: drop the old window and build it again in the
-- new language, at the same place and with the same visibility.
function ns.RebuildWindow()
	if not win then return end
	local shown = win:IsShown()
	win:Hide()
	win = nil
	Build()
	if shown then win:Show() end
end

function ns.InitUI()
	ns.OnChange(Refresh)
	if ns.UpdateMinimapButton then
		ns.OnChange(ns.UpdateMinimapButton)
		ns.UpdateMinimapButton()
	end
end
