local _, addon = ...
local E, P, C, D, L = addon.E, addon.P, addon.C, addon.D, addon.L

-- Lua
local _G = getfenv(0)
local hooksecurefunc = _G.hooksecurefunc
local next = _G.next
local t_insert = _G.table.insert
local t_remove = _G.table.remove
local t_sort = _G.table.sort

-- Mine
local activeToasts = {}
local queuedToasts = {}
local fullscreenParent = UIParent

function P:RefreshQueues()
	if not fullscreenParent:IsShown() then return end

	local inCombat = InCombatLockdown()

	for anchorID, queued in next, queuedToasts do
		local anchor = addon.Anchor:Get(anchorID)
		if not anchor then return end

		local config = addon:GetAnchorConfigByID(anchorID)
		local active = activeToasts[anchorID]

		if #active < config.max_active_toasts then
			for _ = 1, config.max_active_toasts - #active do
				if not queued[1] then
					break
				end

				if not inCombat or not queued[1]._data.dnd then
					t_insert(active, t_remove(queued, 1))
				else
					break
				end
			end
		end

		for i = 1, #active do
			local toast = active[i]
			-- Release clears the layout cache together with the rest of the toast data.
			local data = toast._data
			local relative = i == 1 and anchor or active[i - 1]
			local direction = i == 1 and "ANCHOR" or config.growth_direction
			local offsetX = config.growth_offset_x
			local offsetY = config.growth_offset_y

			if data.queue_parent ~= fullscreenParent then
				toast:SetParent(fullscreenParent)
				data.queue_parent = fullscreenParent
			end

			if data.queue_strata ~= C.db.profile.strata then
				toast:SetFrameStrata(C.db.profile.strata)
				data.queue_strata = C.db.profile.strata
			end

			if data.queue_relative ~= relative or data.queue_direction ~= direction
			or data.queue_offset_x ~= offsetX or data.queue_offset_y ~= offsetY then
				toast:ClearAllPoints()

				if direction == "ANCHOR" then
					toast:SetPoint("TOPLEFT", relative, "TOPLEFT", 0, 0)
				elseif direction == "DOWN" then
					toast:SetPoint("TOP", relative, "BOTTOM", 0, -offsetY)
				elseif direction == "UP" then
					toast:SetPoint("BOTTOM", relative, "TOP", 0, offsetY)
				elseif direction == "LEFT" then
					toast:SetPoint("RIGHT", relative, "LEFT", -offsetX, 0)
				elseif direction == "RIGHT" then
					toast:SetPoint("LEFT", relative, "RIGHT", offsetX, 0)
				end

				data.queue_relative = relative
				data.queue_direction = direction
				data.queue_offset_x = offsetX
				data.queue_offset_y = offsetY
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
	local queued = queuedToasts[anchorID]
	local previous = queued[#queued]
	t_insert(queued, toast)

	if previous and sortFunc(toast, previous) then
		t_sort(queued, sortFunc)
	end

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

UIParent:HookScript("OnShow", P.RefreshQueues)

hooksecurefunc(AlertFrame, "SetFullScreenFrame", function(_, frame)
	fullscreenParent = frame
end)

hooksecurefunc(AlertFrame, "ClearFullScreenFrame", function()
	fullscreenParent = UIParent
end)
