WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Explicit NPC browser. Search and selection are separate from Alt-hover state.
local _, A = ...
local T = A.Text
local frame, search, scrollbar, countLabel
local results, rows, offset = {}, {}, 0
local tracked, scope = {}, 'all'
local trackerOnly = false
local names, englishNames

function A.FindNPCs(query, source)
    if not names then
        names, englishNames = {}, {}
        for id, npc in pairs(A.BundledMetadata.Npc) do
            if npc.name and (npc.maxLevel or 0) > 0 then
                names[id] = npc.name
            end
        end
        for id, npc in pairs(A.LootReference.creatures) do
            names[id] = names[id] or npc[2]
        end
        for _, dungeon in pairs(A.DungeonReference or {}) do
            for id, boss in pairs(dungeon.bosses) do
                names[id] = boss.name
            end
        end
        for id, npc in pairs(A.ForeverReference or {}) do
            names[id] = npc.name
        end
        for id, name in pairs(names) do
            englishNames[id] = name
            names[id] = A.EntityName('Npc', id, name)
        end
    end
    local allowed
    if source == 'tracked' then
        allowed = tracked
    elseif source == 'recent' then
        allowed = {}
        for _, id in ipairs(A.db.recentPortraitNPCs or {}) do
            allowed[id] = true
        end
    end
    query = string.lower(query or '')
    local result = {}
    for id, name in pairs(names) do
        if
            (not allowed or allowed[id])
            and (query == '' or tostring(id) == query or string.find(string.lower(name), query, 1, true)
                or string.find(string.lower(englishNames[id] or ''), query, 1, true))
        then
            result[#result + 1] = { id = id, name = name }
        end
    end
    for id, name in pairs(tracked) do
        if
            not names[id]
            and (not allowed or allowed[id])
            and (query == '' or tostring(id) == query or string.find(string.lower(name), query, 1, true))
        then
            result[#result + 1] = { id = id, name = name }
        end
    end
    table.sort(result, function(a, b)
        if a.name == b.name then
            return a.id < b.id
        end
        return a.name < b.name
    end)
    return result
end

local function render()
    offset = math.max(0, math.min(offset, math.max(0, #results - 8)))
    for index, row in ipairs(rows) do
        local entry = results[index + offset]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(entry.name)
            local npc = A.ReferenceMonster(entry.id, entry.name)
            local level = npc.minLevel or A.ReferenceMetadata.Npc.Get(entry.id, 'minLevel')
            row.detail:SetText((level and (T('Lv ') .. level .. ' / ') or '') .. A.MonsterZones(entry.id))
            A.SetBestiaryPortrait(row.portrait, entry.id)
        end
    end
    scrollbar:Update(#results, 8, offset, 304)
    countLabel:SetText(
        #results > 0 and (#results .. T(' NPCs / click one to view drops'))
            or (
                trackerOnly and T('No matching tracked monsters.')
                or T('No matching NPCs. Try another name or All.')
            )
    )
end
local function refresh()
    if trackerOnly then
        scope = 'tracked'
    end
    results = A.FindNPCs(search:GetText(), scope)
    offset = 0
    render()
end
local function label(parent, x, y, width)
    local text = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    text:SetPoint('TOPLEFT', x, y)
    text:SetWidth(width)
    text:SetJustifyH('LEFT')
    text:SetTextColor(unpack(A.Theme.text))
    return text
end
local function button(text, x, y, width, action)
    local control = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    control:SetPoint('TOPLEFT', x, y)
    control:SetSize(width, 20)
    control:SetText(text)
    control:SetScript('OnClick', action)
    return control
end

function A.OpenBrowser(monsters, fullBrowser)
    if fullBrowser then
        trackerOnly = false
        scope = 'all'
    end
    if monsters then
        trackerOnly = true
        scope = 'tracked'
        tracked = {}
        for _, monster in pairs(monsters) do
            local id = A.TrackerPortraitID(monster)
            if id then
                tracked[id] = A.EntityName('Npc', id, monster.name or ('NPC ' .. id))
            end
        end
    end
    if not frame then
        frame = CreateFrame('Frame', 'RaynnaBestiaryBrowser', UIParent, 'BackdropTemplate')
        A.browser = frame
        frame:SetSize(340, 437)
        local position = A.db.bestiary.browserPosition
        if position then
            frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
        else
            frame:SetPoint('CENTER', -180, 0)
        end
        frame:SetClampedToScreen(true)
        frame:SetFrameStrata('TOOLTIP')
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag('LeftButton')
        frame:SetScript('OnDragStart', function()
            frame:StartMoving()
        end)
        frame:SetScript('OnDragStop', function()
            frame:StopMovingOrSizing()
            local point, _, relative, x, y = frame:GetPoint()
            A.db.bestiary.browserPosition = { point, relative, x, y }
        end)
        A.SkinPanel(frame, true)
        frame.heading = label(frame, 12, -9, 280)
        button('x', 307, -5, 22, function()
            frame:Hide()
        end)
        label(frame, 12, -35, 300):SetText(T('Search NPC name or ID, then press Enter'))
        search = CreateFrame('EditBox', nil, frame, 'InputBoxTemplate')
        search:SetPoint('TOPLEFT', 18, -53)
        search:SetSize(236, 22)
        search:SetAutoFocus(false)
        search:SetText('')
        search:SetScript('OnEnterPressed', function(self)
            refresh()
            self:ClearFocus()
        end)
        search:SetScript('OnEscapePressed', function(self)
            self:ClearFocus()
        end)
        button(T('Search'), 263, -54, 64, refresh)
        frame.all = button(T('All'), 12, -83, 66, function()
            scope = 'all'
            refresh()
        end)
        frame.clear = button(T('Clear'), 85, -83, 70, function()
            A.OpenBrowser(nil, true)
        end)
        frame.clear:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetText(T('Clear search and Tracker filter'))
            GameTooltip:AddLine(T('Show all monsters. Your Tracker history is unchanged.'), 0.9, 0.85, 0.7, true)
            GameTooltip:Show()
        end)
        frame.clear:SetScript('OnLeave', function()
            GameTooltip:Hide()
        end)
        frame.recent = button(T('Recent'), 162, -83, 70, function()
            scope = 'recent'
            refresh()
        end)
        frame.target = button(T('Target'), 239, -83, 88, function()
            local guid = UnitGUID('target')
            if (not issecretvalue or not issecretvalue(guid)) and type(guid) == 'string' then
                local id = guid:match('^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-')
                if id then
                    search:SetText(id)
                    scope = 'all'
                    refresh()
                    return
                end
            end
            countLabel:SetText(T('Target a creature to find it in the browser.'))
        end)
        for index = 1, 8 do
            local row = CreateFrame('Button', nil, frame)
            row:SetPoint('TOPLEFT', 12, -112 - (index - 1) * 38)
            row:SetSize(300, 37)
            row:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight', 'ADD')
            row.portrait = CreateFrame('Frame', nil, row)
            row.portrait:SetSize(30, 30)
            row.portrait:SetPoint('TOPLEFT', 0, -3)
            row.name = label(row, 37, -3, 260)
            row.detail = label(row, 37, -20, 260)
            row.detail:SetTextColor(unpack(A.Theme.muted))
            row:SetScript('OnClick', function()
                if row.entry then
                    A.ShowBestiary(A.ReferenceMonster(row.entry.id, row.entry.name), false, true)
                    local detail = _G.RaynnaBestiaryFrame
                    detail:ClearAllPoints()
                    detail:SetPoint('TOPLEFT', frame, 'TOPRIGHT', 6, 0)
                end
            end)
            rows[index] = row
        end
        scrollbar = A.Scrollbar(frame, function(value)
            offset = value
            render()
        end)
        scrollbar:SetPoint('TOPRIGHT', -5, -112)
        frame:EnableMouseWheel(true)
        frame:SetScript('OnMouseWheel', function(_, delta)
            offset = offset - delta
            render()
        end)
        countLabel = label(frame, 12, -418, 315)
    end
    if monsters or fullBrowser then
        search:SetText('')
    end
    frame.heading:SetText(trackerOnly and T('BESTIARY / TRACKER MONSTERS') or T("RAYNNA'S BESTIARY / BROWSE"))
    frame.all:SetShown(not trackerOnly)
    frame.recent:SetShown(not trackerOnly)
    frame.target:SetShown(not trackerOnly)
    frame:SetScale(A.db.bestiary.scale or 1)
    frame:Show()
    refresh()
end
end)
