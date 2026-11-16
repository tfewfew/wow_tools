WoWTools.prr.RegisterSource(function(...)
-- glow.lua -- a pulsing gold border with rounded corners over a frame: the
-- favorite items in the loot window.
--
-- The game has no rounded rectangles: every layer is drawn of strips, the rows
-- (columns) near a corner start a little further from the edge.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local GLOW_COLOR = { 1, 0.82, 0.2 }
local EDGE_LAYERS = { -- from the sharp line inwards: thickness, alpha
    { size = 2, alpha = 0.9 },
    { size = 5, alpha = 0.35 },
    { size = 9, alpha = 0.15 },
}
local CORNER_RADIUS = 4
local FILL_ALPHA = 0.06          -- a faint tint of the frame itself
local PULSE_PERIOD = 1.2         -- seconds of one breath
local PULSE_MIN = 0.45           -- the glow fades down to this, and back to 1
local OVERLAY_LEVEL_ABOVE = 20   -- above the content of the frame

-- How far from the side the row (column) number line of a rounded corner
-- starts: the circle of CORNER_RADIUS through the middle of the line.
local function CornerInset(line)
    if line >= CORNER_RADIUS then return 0 end
    local fromCenter = CORNER_RADIUS - line - 0.5
    return math.floor(CORNER_RADIUS - math.sqrt(CORNER_RADIUS ^ 2 - fromCenter ^ 2) + 0.5)
end

-- Lines 0..count-1 grouped into runs of the same value: { first, length, value }.
local function Runs(count, valueOf)
    local runs = {}
    for line = 0, count - 1 do
        local value = valueOf(line)
        local last = runs[#runs]
        if last and last.value == value then
            last.length = last.length + 1
        else
            table.insert(runs, { first = line, length = 1, value = value })
        end
    end
    return runs
end

local function NewTexture(overlay, textures, layer, alpha)
    local texture = overlay:CreateTexture(nil, layer)
    texture:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], 1)
    texture:SetBlendMode("ADD")
    texture.baseAlpha = alpha
    table.insert(textures, texture)
    return texture
end

-- Horizontal strips at the top and the bottom: from the edge run.first lines
-- in, run.length thick, run.value away from the sides.
local function AddRows(overlay, textures, runs, layer, alpha)
    for _, run in ipairs(runs) do
        local top = NewTexture(overlay, textures, layer, alpha)
        top:SetPoint("TOPLEFT", run.value, -run.first)
        top:SetPoint("TOPRIGHT", -run.value, -run.first)
        top:SetHeight(run.length)
        local bottom = NewTexture(overlay, textures, layer, alpha)
        bottom:SetPoint("BOTTOMLEFT", run.value, run.first)
        bottom:SetPoint("BOTTOMRIGHT", -run.value, run.first)
        bottom:SetHeight(run.length)
    end
end

-- One border layer: the rows of the top and the bottom, and the columns of the
-- sides between them (the rows already cover the corners).
local function AddLayer(overlay, textures, size, alpha)
    AddRows(overlay, textures, Runs(size, CornerInset), "OVERLAY", alpha)
    local columns = Runs(size, function(column)
        return math.max(size, CornerInset(column))
    end)
    for _, run in ipairs(columns) do
        local left = NewTexture(overlay, textures, "OVERLAY", alpha)
        left:SetPoint("TOPLEFT", run.first, -run.value)
        left:SetPoint("BOTTOMLEFT", run.first, run.value)
        left:SetWidth(run.length)
        local right = NewTexture(overlay, textures, "OVERLAY", alpha)
        right:SetPoint("TOPRIGHT", -run.first, -run.value)
        right:SetPoint("BOTTOMRIGHT", -run.first, run.value)
        right:SetWidth(run.length)
    end
end

-- The tint: rounded rows near the top and the bottom, a block between them.
local function AddFill(overlay, textures)
    AddRows(overlay, textures, Runs(CORNER_RADIUS, CornerInset), "BACKGROUND", FILL_ALPHA)
    local middle = NewTexture(overlay, textures, "BACKGROUND", FILL_ALPHA)
    middle:SetPoint("TOPLEFT", 0, -CORNER_RADIUS)
    middle:SetPoint("BOTTOMRIGHT", 0, CORNER_RADIUS)
end

-- The glow over target, inset pixels inside its edges; hidden at first.
function ns.UI.Glow(target, inset)
    local overlay = CreateFrame("Frame", nil, target)
    overlay:SetPoint("TOPLEFT", inset, -inset)
    overlay:SetPoint("BOTTOMRIGHT", -inset, inset)
    overlay:SetFrameLevel(target:GetFrameLevel() + OVERLAY_LEVEL_ABOVE)

    local textures = {}
    for _, layer in ipairs(EDGE_LAYERS) do
        AddLayer(overlay, textures, layer.size, layer.alpha)
    end
    AddFill(overlay, textures)

    -- the pulse ticks only while the glow is shown
    overlay:SetScript("OnUpdate", function()
        local wave = (math.sin(GetTime() * 2 * math.pi / PULSE_PERIOD) + 1) / 2
        local strength = PULSE_MIN + (1 - PULSE_MIN) * wave
        for _, texture in ipairs(textures) do
            texture:SetAlpha(texture.baseAlpha * strength)
        end
    end)
    overlay:Hide()
    return overlay
end
end)
