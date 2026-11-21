WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Questie area IDs are not UI map IDs. Resolve through the client's localized names.
local _, A = ...
local T = A.Text
local mapsByName

local function resolveMap(area)
    if not (C_Map and C_Map.GetAreaInfo and C_Map.GetMapInfo) then
        return nil
    end
    local name = C_Map.GetAreaInfo(area)
    if not name then
        return nil
    end
    if not mapsByName then
        mapsByName = {}
        local scores = {}
        for id = 1, 3000 do
            local info = C_Map.GetMapInfo(id)
            if info and info.name then
                local score = info.mapType == 3 and 100 or 10
                if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(id) then
                    score = score + 50
                end
                if not scores[info.name] or score > scores[info.name] then
                    mapsByName[info.name], scores[info.name] = id, score
                end
            end
        end
    end
    return mapsByName[name]
end

-- Shared with the overlay: different area records may resolve to the same map.
A.SpawnMapID = resolveMap

function A.SourceLocations(npcID, objectID)
    if not npcID and not objectID then
        return {}
    end
    local spawns
    if objectID then
        spawns = A.Relation('Object', objectID, 'spawns')
    else
        spawns = A.ReferenceMetadata.Npc.Get(npcID, 'spawns')
    end
    if spawns == false or (type(spawns) == 'table' and next(spawns) == nil) then
        return {}
    end
    local hasCoordinates = false
    for _, points in pairs(type(spawns) == 'table' and spawns or {}) do
        if type(points) == 'table' then
            hasCoordinates = true
            break
        end
    end
    if not hasCoordinates then
        spawns = npcID and A.NpcLocations[npcID]
    end
    local result = {}
    for area, points in pairs(type(spawns) == 'table' and spawns or {}) do
        if type(points) == 'table' then
            for _, point in ipairs(points) do
                if
                    type(point) == 'table'
                    and type(point[1]) == 'number'
                    and type(point[2]) == 'number'
                    and point[1] >= 0
                    and point[1] <= 100
                    and point[2] >= 0
                    and point[2] <= 100
                then
                    result[#result + 1] = { area = area, x = point[1], y = point[2] }
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.area ~= b.area then
            return a.area < b.area
        end
        if a.x ~= b.x then
            return a.x < b.x
        end
        return a.y < b.y
    end)
    return result
end

-- Compare world coordinates across zones, never unrelated map percentages.
local function coordinates(vector)
    if not vector or type(vector.GetXY) ~= 'function' then
        return
    end
    local ok, x, y = pcall(vector.GetXY, vector)
    if ok and A.IsReadableValue(x) and A.IsReadableValue(y) and type(x) == 'number' and type(y) == 'number' then
        return x, y
    end
end
local function worldPosition(map, vector)
    if not (C_Map and C_Map.GetWorldPosFromMapPos) then
        return
    end
    local ok, continent, position = pcall(C_Map.GetWorldPosFromMapPos, map, vector)
    if ok and A.IsReadableValue(continent) then
        local x, y = coordinates(position)
        if x then
            return continent, x, y
        end
    end
end
function A.NearestSpawn(locations)
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
        return
    end
    local ok, playerMap = pcall(C_Map.GetBestMapForUnit, 'player')
    if not ok or not A.IsReadableValue(playerMap) or type(playerMap) ~= 'number' then
        return
    end
    local success, position = pcall(C_Map.GetPlayerMapPosition, playerMap, 'player')
    if not success then
        return
    end
    local px, py = coordinates(position)
    if not px then
        return
    end
    local continent, wx, wy = worldPosition(playerMap, position)
    local best, distance, localBest, localDistance
    local resolved = {}
    for _, spot in ipairs(locations) do
        if resolved[spot.area] == nil then
            resolved[spot.area] = resolveMap(spot.area) or false
        end
        local map = resolved[spot.area]
        if map == playerMap then
            -- Zone maps are wider than tall; prefer precise world distances below.
            local d = ((spot.x / 100 - px) * 1.5) ^ 2 + (spot.y / 100 - py) ^ 2
            if not localDistance or d < localDistance then
                localBest, localDistance = spot, d
            end
        end
        if continent and wx and map and CreateVector2D then
            local targetContinent, x, y = worldPosition(map, CreateVector2D(spot.x / 100, spot.y / 100))
            if targetContinent == continent and x then
                local d = (x - wx) ^ 2 + (y - wy) ^ 2
                if not distance or d < distance then
                    best, distance = spot, d
                end
            end
        end
    end
    return best or localBest
end

function A.ShowSourceLocation(entry)
    local points = A.SourceLocations(entry.npcID, entry.objectID)
    if #points == 0 then
        return false, T('No recorded coordinates for this source.')
    end
    local spot, density, unique = A.DensestSpawn(points)
    local nearest = A.NearestSpawn(unique)
    spot = nearest or spot
    local map = spot and resolveMap(spot.area)
    if not map then
        return false, T('This location has no matching client map.')
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, T('Open the map after combat.')
    end
    local canPin = C_Map.SetUserWaypoint
        and UiMapPoint
        and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(map))
    local pinned = false
    if canPin then
        local ok, result =
            pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, spot.x / 100, spot.y / 100))
        pinned = ok and result ~= false
        if pinned and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
    local open = C_Map.OpenWorldMap or OpenWorldMap
    local ok, opened = false, false
    if open then ok, opened = pcall(open, map) end
    local position = string.format('%.1f, %.1f', spot.x, spot.y)
    if not nearest then
        position = position .. string.format(T(' / %d nearby records'), density)
    end
    if not ok or opened == false then
        return false, T('Could not open the map. Coordinates: ') .. position
    end
    local highlights = A.ShowSpawnHighlights(map, unique, spot.area, entry, spot)
    local label = nearest and T('Nearest recorded spawn: ') or T('Position unavailable; densest cluster: ')
    return true,
        label
            .. position
            .. (not pinned and T(' (pin unavailable)') or '')
            .. (not highlights and T(' (overlay unavailable)') or '')
end
end)
