WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Session portrait cache. Keeps rendered textures alive and reuses them across row hosts.
-- Saved monster IDs survive reloads; rendered textures and this pool do not.

local _, Addon = ...
local stagingFrame, portraitsByDisplay = nil, {}
local loadingPortraits = {}
local preloadQueue, queuedDisplays = {}, {}
local warmupSeconds = 3
local recentPortraitLimit = 512

local function rememberPortrait(npcID)
    if not Addon.db then
        return
    end
    local recent = Addon.db.recentPortraitNPCs or {}
    Addon.db.recentPortraitNPCs = recent
    for i = #recent, 1, -1 do
        if recent[i] == npcID then
            table.remove(recent, i)
        end
    end
    table.insert(recent, 1, npcID)
    while #recent > recentPortraitLimit do
        table.remove(recent)
    end
end
local createPortrait

local function ensureStagingFrame()
    if not stagingFrame then
        stagingFrame = CreateFrame('Frame', nil, UIParent)
        stagingFrame:SetSize(32, 32)
        stagingFrame:SetPoint('TOPLEFT', UIParent, 'TOPRIGHT', 400, 0)
    end
    stagingFrame:SetScript('OnUpdate', function(_, elapsed)
        Addon.UpdatePortraitCache(elapsed)
    end)
end
local creatureIDsByName

-- Resolve recorded IDs and legacy/demo names
function Addon.TrackerPortraitID(monster)
    if monster.npcID then
        return monster.npcID
    end
    if not creatureIDsByName then
        creatureIDsByName = {}
        for id, npc in pairs(Addon.LootReference.creatures) do
            if
                Addon.PortraitDisplays[id]
                and (not creatureIDsByName[npc[2]] or id < creatureIDsByName[npc[2]])
            then
                creatureIDsByName[npc[2]] = id
            end
        end
    end
    return creatureIDsByName[monster.name]
end

-- Move cached textures between off-screen storage and row hosts
local function parkPortrait(entry)
    entry.picture:SetParent(stagingFrame)
    entry.picture:ClearAllPoints()
    entry.picture:SetAllPoints(stagingFrame)
    entry.picture:Show()
end
local function attachPortrait(entry)
    local host = entry.owner
    if not host or host.portraitEntry ~= entry then
        return
    end
    entry.picture:SetParent(host)
    entry.picture:ClearAllPoints()
    entry.picture:SetAllPoints(host)
    entry.picture:Show()
    host.placeholder:Hide()
end
local function restorePortrait(host)
    if host.portraitEntry and host.portraitEntry.ready then
        attachPortrait(host.portraitEntry)
    elseif host.portraitKey and host.portraitKey:match('^item:') and host.itemPicture then
        host.itemPicture:Show()
        host.placeholder:Hide()
    end
end

-- Finish pending renders; stop ticking when the queue is empty
function Addon.UpdatePortraitCache(elapsed)
    for i = #loadingPortraits, 1, -1 do
        local entry = loadingPortraits[i]
        entry.elapsed = entry.elapsed + elapsed
        if entry.elapsed >= warmupSeconds then
            entry.ready = true
            attachPortrait(entry)
            table.remove(loadingPortraits, i)
        end
    end
    -- Spread background requests across frames; visible rows acquire immediately.
    for _ = 1, 2 do
        local display = table.remove(preloadQueue)
        if not display then
            break
        end
        local wanted = queuedDisplays[display] or 1
        queuedDisplays[display] = nil
        local list = portraitsByDisplay[display]
        if not list or #list < wanted then
            local entry = createPortrait(display)
            if entry and #portraitsByDisplay[display] < wanted then
                queuedDisplays[display] = wanted
                preloadQueue[#preloadQueue + 1] = display
            end
        end
    end
    if stagingFrame and #loadingPortraits == 0 and #preloadQueue == 0 then
        stagingFrame:SetScript('OnUpdate', nil)
    end
end

-- Keep unfinished native renders off-screen for the full safety interval.
createPortrait = function(display)
    ensureStagingFrame()
    local entry = { picture = stagingFrame:CreateTexture(nil, 'ARTWORK'), elapsed = 0 }
    parkPortrait(entry)
    local ok = pcall(SetPortraitTextureFromCreatureDisplayID, entry.picture, display)
    if not ok then
        entry.picture:Hide()
        return nil
    end
    local list = portraitsByDisplay[display] or {}
    portraitsByDisplay[display] = list
    list[#list + 1] = entry
    loadingPortraits[#loadingPortraits + 1] = entry
    return entry
end

-- Prime saved monsters, including off-screen rows, without creating visible hosts.
function Addon.PreloadTrackerPortraits()
    if not SetPortraitTextureFromCreatureDisplayID then
        return
    end
    local function enqueue(monsters)
        for _, monster in pairs(monsters or {}) do
            local npcID = Addon.TrackerPortraitID(monster)
            local display = npcID and Addon.PortraitDisplays[npcID]
            if
                display
                and not queuedDisplays[display]
                and (not portraitsByDisplay[display] or #portraitsByDisplay[display] == 0)
            then
                queuedDisplays[display] = 1
                preloadQueue[#preloadQueue + 1] = display
            end
        end
    end
    enqueue(Addon.db.mobs)
    if Addon.demo then
        enqueue(Addon.demo.mobs)
    end
    -- Two independent textures allow a tracker row and Bestiary header to coexist.
    -- The queue pops from the end, so append most recently viewed IDs last.
    local recent = Addon.db.recentPortraitNPCs or {}
    for i = math.min(#recent, recentPortraitLimit), 1, -1 do
        local display = Addon.PortraitDisplays[recent[i]]
        if display and (not portraitsByDisplay[display] or #portraitsByDisplay[display] < 2) then
            if not queuedDisplays[display] then
                preloadQueue[#preloadQueue + 1] = display
            end
            queuedDisplays[display] = 2
        end
    end
    if #preloadQueue > 0 then
        ensureStagingFrame()
    end
end

-- Bind an item icon or acquire a reusable NPC portrait
function Addon.SetBestiaryPortrait(host, npcID, itemID)
    local display = npcID and Addon.PortraitDisplays[npcID]
    local key = itemID and ('item:' .. itemID) or ('npc:' .. tostring(display))
    if host.portraitKey == key then
        restorePortrait(host)
        return
    end
    if display and not itemID then
        rememberPortrait(npcID)
    end
    host.portraitKey = key
    if host.portraitEntry then
        host.portraitEntry.owner = nil
        parkPortrait(host.portraitEntry)
        host.portraitEntry = nil
    end
    if host.itemPicture then
        host.itemPicture:Hide()
    end
    if not host.placeholder then
        host.placeholder = host:CreateTexture(nil, 'BACKGROUND')
        host.placeholder:SetAllPoints(host)
        host.placeholder:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
        host:SetScript('OnShow', restorePortrait)
    end
    host.placeholder:Show()
    if itemID then
        if not host.itemPicture then
            host.itemPicture = host:CreateTexture(nil, 'ARTWORK')
            host.itemPicture:SetAllPoints(host)
        end
        host.picture = host.itemPicture
        host.picture:SetTexture(
            C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
                or 'Interface\\Icons\\INV_Misc_QuestionMark'
        )
        host.picture:Show()
        host.placeholder:Hide()
    elseif display and SetPortraitTextureFromCreatureDisplayID then
        local list = portraitsByDisplay[display] or {}
        portraitsByDisplay[display] = list
        local entry
        for _, candidate in ipairs(list) do
            if not candidate.owner and (not entry or candidate.ready) then
                entry = candidate
            end
            if entry and entry.ready then
                break
            end
        end
        if not entry then
            entry = createPortrait(display)
            if not entry then
                return
            end
        end
        entry.owner = host
        host.portraitEntry = entry
        host.picture = entry.picture
        if entry.ready then
            attachPortrait(entry)
        end
    end
end
end)
