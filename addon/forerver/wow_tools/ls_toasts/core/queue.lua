local addonTable = WoWTools.lsToasts
local E, P, C, D, L = addonTable.E, addonTable.P, addonTable.C, addonTable.D, addonTable.L

-- Lua
local _G = getfenv(0)
local next = _G.next
local t_insert = _G.table.insert
local t_remove = _G.table.remove
local t_sort = _G.table.sort

-- Mine
local activeToasts = {}
local queuedToasts = {}

function P:RefreshQueues()
    for anchorID, queued in next, queuedToasts do
        local config = C.db.profile.anchors[anchorID]
        if not config then
            return
        end

        local active = activeToasts[anchorID]

        if #active < config.max_active_toasts then
            for _ = 1, config.max_active_toasts - #active do
                if not queued[1] then
                    break
                end

                if not InCombatLockdown() or not queued[1]._data.dnd then
                    t_insert(active, t_remove(queued, 1))
                end
            end
        end

        for i = 1, #active do
            local toast = active[i]
            local point, relativeTo, relativePoint, x, y = "TOPLEFT", P:GetAnchor(anchorID), "TOPLEFT", 0, 0
            if i > 1 then
                if config.growth_direction == "DOWN" then
                    point, relativeTo, relativePoint, y =
                        "TOP", active[i - 1], "BOTTOM", -config.growth_offset_y
                elseif config.growth_direction == "UP" then
                    point, relativeTo, relativePoint, y =
                        "BOTTOM", active[i - 1], "TOP", config.growth_offset_y
                elseif config.growth_direction == "LEFT" then
                    point, relativeTo, relativePoint, x =
                        "RIGHT", active[i - 1], "LEFT", -config.growth_offset_x
                elseif config.growth_direction == "RIGHT" then
                    point, relativeTo, relativePoint, x =
                        "LEFT", active[i - 1], "RIGHT", config.growth_offset_x
                end
            end

            local oldPoint, oldRelativeTo, oldRelativePoint, oldX, oldY = toast:GetPoint()
            if
                toast:GetNumPoints() ~= 1
                or oldPoint ~= point
                or oldRelativeTo ~= relativeTo
                or oldRelativePoint ~= relativePoint
                or oldX ~= x
                or oldY ~= y
            then
                toast:ClearAllPoints()
                toast:SetPoint(point, relativeTo, relativePoint, x, y)
            end

            if not toast:IsShown() then
                toast:Show()
            end
        end
    end
end

function P:SetUpQueues(anchorID)
    if not queuedToasts[anchorID] then
        queuedToasts[anchorID] = {}
    end

    if not activeToasts[anchorID] then
        activeToasts[anchorID] = {}
    end
end

local function sortFunc(a, b)
    if a._data.dnd == b._data.dnd then
        return a._data.order < b._data.order
    elseif not a._data.dnd and b._data.dnd then
        return true
    elseif a._data.dnd and not b._data.dnd then
        return false
    end
end

function P:Queue(toast, anchorID)
    t_insert(queuedToasts[anchorID], toast)
    t_sort(queuedToasts[anchorID], sortFunc)

    self:RefreshQueues()
end

function P:Dequeue(toast, anchorID)
    for i, queuedToast in next, queuedToasts[anchorID] do
        if toast == queuedToast then
            t_remove(queuedToasts[anchorID], i)

            break
        end
    end

    for i, activeToast in next, activeToasts[anchorID] do
        if toast == activeToast then
            t_remove(activeToasts[anchorID], i)

            self:RefreshQueues()

            break
        end
    end
end

local function flush(t)
    for _ = #t, 1, -1 do
        if t[1] then
            t_remove(t, 1):Release()
        end
    end
end

function P:FlushQueue(anchorID)
    if anchorID then
        if queuedToasts[anchorID] then
            flush(queuedToasts[anchorID])
        end

        if activeToasts[anchorID] then
            flush(activeToasts[anchorID])
        end
    else
        for _, queued in next, queuedToasts do
            flush(queued)
        end

        for _, active in next, activeToasts do
            flush(active)
        end
    end
end

function P:GetActiveToasts(anchorID)
    return anchorID and activeToasts[anchorID] or activeToasts
end

function P:GetQueuedToasts(anchorID)
    return anchorID and queuedToasts[anchorID] or queuedToasts
end

E:RegisterEvent("PLAYER_REGEN_ENABLED", P.RefreshQueues)
