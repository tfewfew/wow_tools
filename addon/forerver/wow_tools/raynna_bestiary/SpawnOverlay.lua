WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Spawn highlights belong to the map canvas, so zoom and pan move them together.
local _, A = ...
local T = A.Text
local points, dots, mapID, canvas, layer = {}, {}, nil, nil, nil
local areas, spans, outlines = {}, {}, {}
local pinSpot, pinText
local focusPending, pulseTime = false, 0
function A.DensestSpawn(locations)
    local unique, seen, buckets = {}, {}, {}
    for _, p in ipairs(locations) do
        local key = p.area .. ':' .. math.floor(p.x * 10 + 0.5) .. ':' .. math.floor(p.y * 10 + 0.5)
        if not seen[key] then
            seen[key] = true
            unique[#unique + 1] = p
            local cell = p.area .. ':' .. math.floor(p.x / 5) .. ':' .. math.floor(p.y / 5)
            buckets[cell] = buckets[cell] or {}
            table.insert(buckets[cell], p)
        end
    end
    local best, score = nil, -1
    for _, p in ipairs(unique) do
        local count = 0
        local cx, cy = math.floor(p.x / 5), math.floor(p.y / 5)
        for x = cx - 1, cx + 1 do
            for y = cy - 1, cy + 1 do
                for _, q in ipairs(buckets[p.area .. ':' .. x .. ':' .. y] or {}) do
                    if (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 <= 25 then
                        count = count + 1
                    end
                end
            end
        end
        if count > score then
            best, score = p, count
        end
    end
    return best, score, unique
end
-- Infer compact regions from nearby records; these are not server boundary data.
-- Separate connected groups before taking a hull, so distant camps stay separate.
function A.BuildSpawnAreas(records)
    local buckets, visited, result = {}, {}, {}
    local function key(x, y, area)
        return tostring(area) .. ':' .. x .. ':' .. y
    end
    for i, p in ipairs(records) do
        local k = key(math.floor(p.x / (10 / 1.5)), math.floor(p.y / 10), p.area)
        buckets[k] = buckets[k] or {}
        table.insert(buckets[k], i)
    end
    local function cross(o, a, b)
        return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    end
    for seed in ipairs(records) do
        if not visited[seed] then
            local queue, padded, head = { seed }, {}, 1
            visited[seed] = true
            while head <= #queue do
                local p = records[queue[head]]
                head = head + 1
                for step = 0, 31 do
                    local angle = step * math.pi / 16
                    padded[#padded + 1] = {
                        x = math.max(0, math.min(100, p.x + math.cos(angle) * 2.4)),
                        y = math.max(0, math.min(100, p.y + math.sin(angle) * 3.6)),
                    }
                end
                local cx, cy = math.floor(p.x / (10 / 1.5)), math.floor(p.y / 10)
                for x = cx - 1, cx + 1 do
                    for y = cy - 1, cy + 1 do
                        for _, index in ipairs(buckets[key(x, y, p.area)] or {}) do
                            local q = records[index]
                            if not visited[index] and ((p.x - q.x) * 1.5) ^ 2 + (p.y - q.y) ^ 2 <= 100 then
                                visited[index] = true
                                queue[#queue + 1] = index
                            end
                        end
                    end
                end
            end
            table.sort(padded, function(a, b)
                return a.x == b.x and a.y < b.y or a.x < b.x
            end)
            local lower, upper = {}, {}
            for _, p in ipairs(padded) do
                while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do
                    table.remove(lower)
                end
                lower[#lower + 1] = p
            end
            for i = #padded, 1, -1 do
                local p = padded[i]
                while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do
                    table.remove(upper)
                end
                upper[#upper + 1] = p
            end
            table.remove(lower)
            table.remove(upper)
            for _, p in ipairs(upper) do
                lower[#lower + 1] = p
            end
            lower.recordCount = #queue
            result[#result + 1] = lower
        end
    end
    return result
end
-- Horizontal strips provide a filled polygon without requiring client triangle APIs.
-- Union overlapping intervals to keep the same translucent opacity everywhere.
function A.SpawnAreaSpans(polygons)
    local result, step = {}, 100 / 768
    for row = 0, 767 do
        local y, intervals = (row + 0.5) * step, {}
        for _, polygon in ipairs(polygons) do
            local hits = {}
            for i, a in ipairs(polygon) do
                local b = polygon[i % #polygon + 1]
                if (a.y <= y and b.y > y) or (b.y <= y and a.y > y) then
                    hits[#hits + 1] = a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)
                end
            end
            table.sort(hits)
            for i = 1, #hits - 1, 2 do
                intervals[#intervals + 1] = { hits[i], hits[i + 1] }
            end
        end
        table.sort(intervals, function(a, b)
            return a[1] < b[1]
        end)
        local current
        for _, interval in ipairs(intervals) do
            if current and interval[1] <= current.right then
                current.right = math.max(current.right, interval[2])
            else
                current = { left = interval[1], right = interval[2], top = row * step, height = step }
                result[#result + 1] = current
            end
        end
    end
    return result
end
local function focusSelectedSpawn()
    if not focusPending or not pinSpot or WorldMapFrame:GetMapID() ~= mapID then
        return
    end
    local scroll = WorldMapFrame.ScrollContainer
    if not scroll or type(scroll.SetPanTarget) ~= 'function' then
        focusPending = false
        return
    end
    focusPending = false
    if type(scroll.SetZoomTarget) == 'function' and type(scroll.GetScaleForMinZoom) == 'function' then
        local ok, minimum = pcall(scroll.GetScaleForMinZoom, scroll)
        local current = 1
        if type(scroll.GetCanvasScale) == 'function' then
            local read, value = pcall(scroll.GetCanvasScale, scroll)
            if read and type(value) == 'number' then
                current = value
            end
        end
        if ok and type(minimum) == 'number' then
            pcall(scroll.SetZoomTarget, scroll, math.max(current, minimum * 1.25))
        end
    end
    pcall(scroll.SetPanTarget, scroll, pinSpot.x / 100, pinSpot.y / 100)
end
-- Area-weighted centres stay inside these convex spawn regions, unlike the pin.
function A.SpawnAreaLabelBounds(polygon)
    local area, cx, cy = 0, 0, 0
    local minX, minY, maxX, maxY = 100, 100, 0, 0
    for i, a in ipairs(polygon) do
        local b = polygon[i % #polygon + 1]
        local cross = a.x * b.y - b.x * a.y
        area = area + cross
        cx = cx + (a.x + b.x) * cross
        cy = cy + (a.y + b.y) * cross
        minX, minY = math.min(minX, a.x), math.min(minY, a.y)
        maxX, maxY = math.max(maxX, a.x), math.max(maxY, a.y)
    end
    if math.abs(area) > 0.00001 then
        cx, cy = cx / (3 * area), cy / (3 * area)
    else
        cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
    end
    return cx, cy, maxX - minX, maxY - minY
end
function A.SpawnAreaContains(polygon, x, y)
    local inside = false
    for i, a in ipairs(polygon) do
        local b = polygon[i % #polygon + 1]
        if (a.y > y) ~= (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x then
            inside = not inside
        end
    end
    return inside
end
local hoveredArea
local function updateAreaTooltip()
    if not layer.areaTooltip then
        return
    end
    if layer.legend:IsMouseOver() then
        return
    end
    local mapShown = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == mapID
    local host = WorldMapFrame.ScrollContainer
    if (type(host) ~= 'table' and type(host) ~= 'userdata') or type(host.IsMouseOver) ~= 'function' then
        host = WorldMapFrame
    end
    if not mapShown or not host:IsMouseOver() or (GameTooltip and GameTooltip:IsShown()) then
        hoveredArea = nil
        layer.areaTooltip:Hide()
        return
    end
    local mx, my = GetCursorPosition()
    local scale = canvas:GetEffectiveScale()
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then
        return
    end
    local x, y = (mx / scale - left) / canvas:GetWidth() * 100, (top - my / scale) / canvas:GetHeight() * 100
    local found
    for index, polygon in ipairs(areas) do
        if A.SpawnAreaContains(polygon, x, y) then
            found = index
            break
        end
    end
    if not found then
        hoveredArea = nil
        layer.areaTooltip:Hide()
        return
    end
    if hoveredArea ~= found or not layer.areaTooltip:IsShown() then
        hoveredArea = found
        local tip = layer.areaTooltip
        tip:SetOwner(WorldMapFrame, 'ANCHOR_CURSOR')
        tip:ClearLines()
        tip:AddLine(pinText or T('Known spawn area'), 1, 0.88, 0.35, true)
        tip:AddLine(T('%d recorded spawn locations', areas[found].recordCount or 0), 0.8, 0.9, 1)
        tip:AddLine(T('Estimated area, not live monster positions.'), 0.8, 0.75, 0.65, true)
        tip:AddLine(T('Use Clear below to remove these highlights.'), 0.6, 0.85, 1, true)
        tip:Show()
    end
end
local function redraw()
    if layer and layer.pulse then
        layer.pulse:Hide()
    end
    hoveredArea = nil
    if layer and layer.areaTooltip then
        layer.areaTooltip:Hide()
    end
    for _, label in ipairs(layer and layer.regionLabels or {}) do
        label:Hide()
    end
    for _, dot in ipairs(dots) do
        dot:Hide()
    end
    for _, line in ipairs(outlines) do
        line:Hide()
    end
    if layer and layer.legend then
        layer.legend:SetShown(WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == mapID)
    end
    if not layer or not WorldMapFrame:IsShown() or WorldMapFrame:GetMapID() ~= mapID then
        return
    end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then
        return
    end
    layer:SetFrameStrata(WorldMapFrame:GetFrameStrata())
    layer:SetFrameLevel(math.max(canvas:GetFrameLevel() + 500, 9980))
    layer:Show()
    if pinSpot and pinText then
        if not layer.pulse then
            layer.pulse = layer:CreateTexture(nil, 'OVERLAY')
            layer.pulse:SetTexture('Interface\\AddOns\\wow_tools\\raynna_bestiary\\Media\\SpawnGlow.tga')
            layer.pulse:SetVertexColor(1, 0.85, 0.25, 1)
            layer.pulse:SetBlendMode('ADD')
        end
        layer.pulse:ClearAllPoints()
        layer.pulse:SetPoint('CENTER', canvas, 'TOPLEFT', width * pinSpot.x / 100, -height * pinSpot.y / 100)
        layer.pulse:SetSize(36, 36)
        layer.pulse:SetShown(pulseTime > 0)
    end
    layer.regionLabels = layer.regionLabels or {}
    if pinText then
        for index, polygon in ipairs(areas) do
            local label = layer.regionLabels[index]
            if not label then
                label = layer:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
                layer.regionLabels[index] = label
                label:SetJustifyH('CENTER')
                label:SetJustifyV('MIDDLE')
                label:SetWordWrap(true)
                label:SetTextColor(1, 0.92, 0.55)
                label:SetShadowColor(0, 0, 0, 1)
                label:SetShadowOffset(1, -1)
            end
            local x, y, w, h = A.SpawnAreaLabelBounds(polygon)
            w, h = width * w / 100, height * h / 100
            local fontSize = math.max(8, math.min(18, w / 9, h / 4))
            label:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', fontSize, 'OUTLINE')
            label:SetSize(math.max(35, w * 0.85), math.max(28, h * 0.85))
            label:ClearAllPoints()
            label:SetPoint('CENTER', canvas, 'TOPLEFT', width * x / 100, -height * y / 100)
            label:SetText(pinText)
            label:Show()
        end
    end
    for index, span in ipairs(spans) do
        local fill = dots[index]
        if not fill then
            fill = layer:CreateTexture(nil, 'ARTWORK')
            dots[index] = fill
            fill:SetColorTexture(0.16, 0.22, 0.85, 0.38)
        end
        fill:ClearAllPoints()
        fill:SetPoint('TOPLEFT', canvas, 'TOPLEFT', width * span.left / 100, -height * span.top / 100)
        fill:SetSize(width * (span.right - span.left) / 100, height * span.height / 100)
        fill:Show()
    end
    local index = 0
    if type(layer.CreateLine) == 'function' then
        for _, polygon in ipairs(areas) do
            for i, a in ipairs(polygon) do
                local b = polygon[i % #polygon + 1]
                index = index + 1
                local line = outlines[index] or layer:CreateLine(nil, 'OVERLAY')
                if line then
                    outlines[index] = line
                    line:SetColorTexture(0.15, 0.65, 1, 0.9)
                    line:SetThickness(1.2)
                    line:SetStartPoint('TOPLEFT', canvas, width * a.x / 100, -height * a.y / 100)
                    line:SetEndPoint('TOPLEFT', canvas, width * b.x / 100, -height * b.y / 100)
                    line:Show()
                end
            end
        end
    end
end
function A.ShowSpawnHighlights(map, locations, area, entry, selectedSpot)
    if not WorldMapFrame or type(WorldMapFrame.GetMapID) ~= 'function' then
        return false
    end
    local ok, found
    if type(WorldMapFrame.GetCanvas) == 'function' then
        ok, found = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
    end
    canvas = ok and found or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
    if not canvas then
        return false
    end
    if not layer then
        layer = CreateFrame('Frame', nil, canvas)
        A.spawnOverlay = layer
        layer:SetAllPoints(canvas)
        layer:EnableMouse(false)
        if hooksecurefunc and type(WorldMapFrame.OnMapChanged) == 'function' then
            hooksecurefunc(WorldMapFrame, 'OnMapChanged', redraw)
        end
        WorldMapFrame:HookScript('OnShow', redraw)
        canvas:HookScript('OnSizeChanged', redraw)
        -- The map may finish switching after OpenWorldMap returns. Only poll while
        -- this map is visible; the cheap state check avoids rebuilding textures.
        local elapsed, lastMap, lastWidth, lastHeight = 0
        layer:SetScript('OnUpdate', function(_, delta)
            focusSelectedSpawn()
            if pulseTime > 0 then
                pulseTime = math.max(0, pulseTime - delta)
                if layer.pulse then
                    local phase = (math.sin(pulseTime * math.pi * 2) + 1) / 2
                    layer.pulse:SetAlpha(0.25 + phase * 0.65)
                    layer.pulse:SetSize(30 + phase * 16, 30 + phase * 16)
                    layer.pulse:SetShown(pulseTime > 0 and WorldMapFrame:GetMapID() == mapID)
                end
            end
            elapsed = elapsed + delta
            if elapsed < 0.1 then
                return
            end
            elapsed = 0
            updateAreaTooltip()
            local current = WorldMapFrame:GetMapID()
            local width, height = canvas:GetWidth(), canvas:GetHeight()
            if current ~= lastMap or width ~= lastWidth or height ~= lastHeight then
                lastMap, lastWidth, lastHeight = current, width, height
                redraw()
            end
        end)
        layer.legend = CreateFrame('Button', nil, WorldMapFrame, 'UIPanelButtonTemplate')
        layer.legend:SetPoint('BOTTOMLEFT', WorldMapFrame, 'BOTTOMLEFT', 20, 24)
        layer.legend:SetSize(250, 22)
        layer.legend:SetText(T('Estimated spawn areas | Clear'))
        layer.legend:SetFrameLevel(10010)
        layer.areaTooltip =
            CreateFrame('GameTooltip', 'RaynnaBestiarySpawnAreaTooltip', UIParent, 'GameTooltipTemplate')
        layer.areaTooltip:SetFrameStrata('TOOLTIP')
        layer.areaTooltip:SetFrameLevel(10030)
        layer.legend:SetScript('OnEnter', function(self)
            hoveredArea = nil
            local tip = layer.areaTooltip
            tip:SetOwner(self, 'ANCHOR_TOP')
            tip:ClearLines()
            tip:AddLine(T('Clear spawn highlights'), 1, 0.88, 0.35)
            tip:AddLine(
                T('Remove the blue areas, NPC labels and pulse from this map. Your waypoint is kept.'),
                0.9,
                0.85,
                0.7,
                true
            )
            tip:Show()
        end)
        layer.legend:SetScript('OnLeave', function()
            layer.areaTooltip:Hide()
        end)
        WorldMapFrame:HookScript('OnHide', function()
            hoveredArea = nil
            layer.areaTooltip:Hide()
        end)
        layer.legend:SetScript('OnClick', function()
            points, areas, spans, mapID = {}, {}, {}, nil
            focusPending, pulseTime = false, 0
            hoveredArea = nil
            layer.areaTooltip:Hide()
            layer:Hide()
            layer.legend:Hide()
        end)
    end
    mapID, points = map, {}
    pinSpot = selectedSpot
    focusPending, pulseTime = selectedSpot ~= nil, selectedSpot and 6 or 0
    pinText = entry
            and ((entry.title or T('Selected source')) .. (entry.levelText and ('\n' .. entry.levelText) or ''))
        or nil
    local areaMaps = {}
    for _, p in ipairs(locations) do
        if areaMaps[p.area] == nil then
            areaMaps[p.area] = p.area == area and map or (A.SpawnMapID and A.SpawnMapID(p.area)) or false
        end
        if areaMaps[p.area] == map then
            -- Coordinates already refer to this map; normalize the grouping key
            -- so adjacent records from equivalent area IDs share one region.
            points[#points + 1] = { area = map, x = p.x, y = p.y }
        end
    end
    areas = A.BuildSpawnAreas(points)
    spans = A.SpawnAreaSpans(areas)
    layer:Show()
    redraw()
    return true
end
end)
