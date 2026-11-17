WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Bestiary window. Presents NPC drops or item sources without modifying tracking history.
-- Hover locking, pinning, scrolling and tooltip ownership are local UI state.

local _, Addon = ...
local T = Addon.Text
local bestiaryFrame, selectedSubject, showingPreview, isPinned, scrollOffset = nil, nil, false, false, 0
local sourceRows, visibleEntries, requestedItems = {}, {}, {}
local itemLockedForAlt = false
local rowTooltipLevel, rowTooltipStrata

-- Tooltip ownership and layering
local function hideRowTooltip()
    GameTooltip:Hide()
    if rowTooltipLevel then
        GameTooltip:SetFrameLevel(rowTooltipLevel)
        if rowTooltipStrata then
            GameTooltip:SetFrameStrata(rowTooltipStrata)
        end
        rowTooltipLevel, rowTooltipStrata = nil, nil
    end
end
local titleColor = Addon.Theme.gold
local function isReadableValue(value)
    return not issecretvalue or not issecretvalue(value)
end
local function createLabel(parent, size, x, y, width, value)
    local label = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    label:SetFont(STANDARD_TEXT_FONT, size)
    label:SetPoint('TOPLEFT', x, y)
    label:SetWidth(width)
    label:SetJustifyH('LEFT')
    label:SetWordWrap(false)
    label:SetTextColor(unpack(Addon.Theme.text))
    label:SetText(value or '')
    return label
end
local function button(parent, label, x, y, width, callback)
    local control = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    control:SetSize(width, 22)
    control:SetPoint('TOPLEFT', x, y)
    control:SetText(label)
    control:SetScript('OnClick', callback)
    return control
end

-- Render the selected NPC or item and its visible source rows
local function refreshWindow()
    if not bestiaryFrame or not selectedSubject then
        return
    end
    Addon.SetBestiaryPortrait(bestiaryFrame.portrait, selectedSubject.npcID, selectedSubject.itemID)
    bestiaryFrame.name:SetText(
        (selectedSubject.itemID and selectedSubject.quest and ('|cffffd100' .. T('[Quest]') .. '|r ') or '')
            .. selectedSubject.name
    )
    local quests = selectedSubject.itemID and Addon.ItemQuests(selectedSubject.itemID) or {}
    selectedSubject.quests = quests
    local questSpace = #quests > 0 and 16 or 0
    bestiaryFrame.questLine:SetShown(#quests > 0)
    bestiaryFrame.questLine:SetText(
        #quests > 0
                and (T('Quest: ') .. quests[1].name .. (#quests > 1 and (' (+' .. (#quests - 1) .. ')') or ''))
            or ''
    )
    bestiaryFrame.section:ClearAllPoints()
    bestiaryFrame.section:SetPoint('TOPLEFT', 10, -68 - questSpace)
    bestiaryFrame.scrollbar:ClearAllPoints()
    bestiaryFrame.scrollbar:SetPoint('TOPRIGHT', -3, -83 - questSpace)
    bestiaryFrame.empty:ClearAllPoints()
    bestiaryFrame.empty:SetPoint('TOPLEFT', 10, -85 - questSpace)
    bestiaryFrame.context:SetText(
        selectedSubject.itemID
                and ((selectedSubject.quest and T('Quest item') or T('Item sources')) .. ' / ' .. T('Reference databases'))
            or (
                T('Level ')
                .. Addon.LevelText(selectedSubject)
                .. ' / ' .. T(selectedSubject.mixedReference and 'Forever + Classic' or selectedSubject.foreverReference and 'Forever reference' or 'Classic reference')
                .. (showingPreview and ('  /  ' .. T('Preview')) or '')
            )
    )
    bestiaryFrame.footer:SetText(
        selectedSubject.itemID
                and T('Sources: Classic DB / source metadata / Forever records\nCoverage varies; ? = unknown chance')
            or (
                selectedSubject.mixedReference
                    and T('Forever sources + Classic fallback rates\nClassic % unverified for Forever; ? unknown')
                or selectedSubject.foreverReference and T('Icy Veins Forever / 2026-11-13\nPartial snapshot; * conditional chance')
                or T('cMaNGOS Classic 1.12 - not verified for Forever\n* Conditional drop chance')
            )
    )
    bestiaryFrame.pin:SetText(isPinned and T('Unpin') or T('Pin'))
    visibleEntries = {}
    for id, drop in pairs(selectedSubject.drops or {}) do
        table.insert(visibleEntries, { id = id, drop = drop })
    end
    table.sort(visibleEntries, function(a, control)
        if (a.drop.rate or -1) ~= (control.drop.rate or -1) then
            return (a.drop.rate or -1) > (control.drop.rate or -1)
        end
        return tostring(a.id) < tostring(control.id)
    end)
    scrollOffset = math.max(0, math.min(scrollOffset, #visibleEntries - 7))
    bestiaryFrame.section:SetText(
        (selectedSubject.itemID and T('SOURCES  /  ') or T('POSSIBLE DROPS  /  ')) .. #visibleEntries
    )
    bestiaryFrame.empty:SetShown(#visibleEntries == 0)
    bestiaryFrame.empty:SetText(
        selectedSubject.itemID
                and T('No known source in the loaded databases.\nCoverage is incomplete for Forever.')
            or T('No source data for this creature ID.\nYour personal loot log is not used here.')
    )
    local shownRows = math.max(1, math.min(7, #visibleEntries))
    local rowHeight = selectedSubject.itemID and 36 or 24
    bestiaryFrame:SetHeight(116 + questSpace + shownRows * rowHeight)
    bestiaryFrame.footer:ClearAllPoints()
    bestiaryFrame.footer:SetPoint('BOTTOMLEFT', 10, 8)
    bestiaryFrame.scrollbar:Update(#visibleEntries, 7, scrollOffset, shownRows * rowHeight)
    for i, row in ipairs(sourceRows) do
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', 10, -83 - questSpace - (i - 1) * rowHeight)
        row.location:SetShown(not not selectedSubject.itemID)
        row.entry = visibleEntries[scrollOffset + i]
        row:SetShown(row.entry ~= nil)
        if row.entry then
            local item, sourceRecord = row.entry.id, row.entry.drop
            if selectedSubject.itemID then
                row.icon:Hide()
                local creatureSource = not sourceRecord.kind or sourceRecord.kind == 'Skinning'
                local npcID = sourceRecord.npcID
                    or (sourceRecord.kind == 'Vendor' and tonumber(tostring(item):match('vendor:(%d+)')))
                    or (not sourceRecord.kind and item)
                row.portrait:SetShown(not not npcID)
                if npcID then
                    Addon.SetBestiaryPortrait(row.portrait, npcID)
                end
                local inset = npcID and 32 or 0
                row.name:ClearAllPoints()
                row.name:SetPoint('TOPLEFT', inset, -5)
                row.name:SetWidth(205 - inset)
                row.location:ClearAllPoints()
                row.location:SetPoint('TOPLEFT', inset, -21)
                row.location:SetWidth(273 - inset)
                row.name:SetText(sourceRecord.name)
                sourceRecord.zones = creatureSource and Addon.MonsterZones(npcID) or T(sourceRecord.details)
                local location = creatureSource
                    and (T('Lv ') .. Addon.LevelText(sourceRecord) .. ' / ' .. sourceRecord.zones)
                    or T(sourceRecord.details)
                if sourceRecord.kind == 'Skinning' then
                    location = T('Skinning') .. ' / ' .. location
                end
                row.location:SetText(location)
                row.detail:SetText(
                    not creatureSource and T(sourceRecord.kind)
                        or (
                            sourceRecord.rate
                                and Addon.DropChance(sourceRecord, true)
                            or '?'
                        )
                )
            else
                row.portrait:Hide()
                row.icon:Show()
                row.name:ClearAllPoints()
                row.name:SetPoint('TOPLEFT', 24, -5)
                row.name:SetWidth(181)
                local name, link, quality, _, _, _, _, _, _, icon, _, classID
                if C_Item and C_Item.GetItemInfo then
                    name, link, quality, _, _, _, _, _, _, icon, _, classID = C_Item.GetItemInfo(item)
                end
                if not icon and C_Item and C_Item.GetItemIconByID then
                    icon = C_Item.GetItemIconByID(item)
                end
                row.icon:SetTexture(icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
                row.name:SetText(
                    ((sourceRecord.quest or classID == 12) and ('|cffffd100' .. T('[Quest]') .. '|r ') or '')
                        .. (link or sourceRecord.name or sourceRecord.link or (T('Item ') .. item))
                )
                row.detail:SetText(
                    sourceRecord.kind and T(sourceRecord.kind)
                        or (
                            sourceRecord.rate
                                and Addon.DropChance(sourceRecord, true)
                            or '?'
                        )
                )
                if not name and not requestedItems[item] and C_Item and C_Item.RequestLoadItemDataByID then
                    requestedItems[item] = true
                    C_Item.RequestLoadItemDataByID(item)
                end
            end
        end
    end
end

-- Open, position and raise the window
function Addon.ShowBestiary(monster, demo, pin)
    if not bestiaryFrame then
        return
    end
    selectedSubject, showingPreview, isPinned, scrollOffset = monster, not not demo, not not pin, 0
    Addon.HideDrops(true)
    refreshWindow()
    if not isPinned then
        bestiaryFrame:ClearAllPoints()
        local x, y = GetCursorPosition()
        local s = bestiaryFrame:GetEffectiveScale()
        bestiaryFrame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x / s + 16, y / s - 12)
    end
    local level = GameTooltip:GetFrameLevel()
    for _, tooltip in pairs({
        ShoppingTooltip1,
        ShoppingTooltip2,
        ItemRefShoppingTooltip1,
        ItemRefShoppingTooltip2,
    }) do
        level = math.max(level, tooltip:GetFrameLevel())
    end
    bestiaryFrame:SetFrameLevel(level + 20)
    bestiaryFrame:Show()
end
function Addon.BestiaryDemo()
    Addon.ShowBestiary(Addon.ReferenceMonster(587), true, true)
end

-- Alt-hover selection and item locking
local function showHoveredItem(tooltipItemID)
    if Addon.db.bestiary.itemHover == false then
        return false
    end
    if not IsAltKeyDown() then
        itemLockedForAlt = false
        return false
    end
    -- Keep the first item stable while crossing other bag slots to reach the list.
    if itemLockedForAlt then
        return true
    end
    if isPinned or (bestiaryFrame:IsShown() and bestiaryFrame:IsMouseOver()) then
        return false
    end
    -- Item post-calls can run before the tooltip is shown or GetItem is updated.
    local id = isReadableValue(tooltipItemID) and tonumber(tooltipItemID) or nil
    if not id then
        if not GameTooltip:IsShown() then
            return false
        end
        local ok, _, link = pcall(GameTooltip.GetItem, GameTooltip)
        if not ok or not isReadableValue(link) or type(link) ~= 'string' then
            return false
        end
        id = tonumber(link:match('item:(%d+)'))
    end
    if not id then
        return false
    end
    itemLockedForAlt = true
    if not bestiaryFrame:IsShown() or not selectedSubject or selectedSubject.itemID ~= id then
        Addon.ShowBestiary(Addon.ReferenceItem(id), false, false)
    end
    return true
end
local function showMouseoverCreature()
    if Addon.db.bestiary.npcHover == false then
        return
    end
    if isPinned or itemLockedForAlt or bestiaryFrame:IsMouseOver() or not IsAltKeyDown() then
        return
    end
    local guid, name, level = UnitGUID('mouseover'), UnitName('mouseover'), UnitLevel('mouseover')
    if not isReadableValue(guid) or not isReadableValue(name) or not isReadableValue(level) then
        return
    end
    if type(guid) ~= 'string' or not guid:match('^Creature%-') or not name then
        return
    end
    local id = tonumber(guid:match('^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-'))
    if not id then
        return
    end
    local monster = Addon.ReferenceMonster(id, name, type(level) == 'number' and level > 0 and level or nil)
    if
        bestiaryFrame:IsShown()
        and selectedSubject
        and selectedSubject.npcID == id
        and selectedSubject.minLevel == monster.minLevel
        and not showingPreview
    then
        return
    end
    Addon.ShowBestiary(monster, false, false)
end

-- Construct the compact window
function Addon.BuildBestiary()
    Addon.db.bestiary = Addon.db.bestiary or {}
    bestiaryFrame = CreateFrame('Frame', 'RaynnaBestiaryFrame', UIParent, 'BackdropTemplate')
    Addon.detailFrame = bestiaryFrame
    bestiaryFrame:SetSize(300, 284)
    bestiaryFrame:SetClampedToScreen(true)
    bestiaryFrame:SetFrameStrata('TOOLTIP')
    bestiaryFrame:SetMovable(true)
    bestiaryFrame:EnableMouse(true)
    bestiaryFrame:EnableMouseWheel(true)
    Addon.SkinPanel(bestiaryFrame, true)
    local p = Addon.db.bestiary.position
    if p then
        bestiaryFrame:SetPoint(p.point, UIParent, p.relative, p.x, p.y)
    else
        bestiaryFrame:SetPoint('CENTER', -60, 0)
    end
    local title = CreateFrame('Frame', nil, bestiaryFrame)
    title:SetPoint('TOPLEFT', 6, -4)
    title:SetSize(195, 26)
    title:EnableMouse(true)
    title:RegisterForDrag('LeftButton')
    title:SetScript('OnDragStart', function()
        bestiaryFrame:StartMoving()
    end)
    title:SetScript('OnDragStop', function()
        bestiaryFrame:StopMovingOrSizing()
        local point, _, relative, x, y = bestiaryFrame:GetPoint()
        Addon.db.bestiary.position = { point = point, relative = relative, x = x, y = y }
    end)
    createLabel(title, 11, 4, -7, 188, T("RAYNNA'S BESTIARY")):SetTextColor(unpack(titleColor))
    bestiaryFrame.pin = button(bestiaryFrame, T('Pin'), 207, -6, 49, function()
        isPinned = not isPinned
        refreshWindow()
    end)
    bestiaryFrame.close = button(bestiaryFrame, 'x', 264, -6, 23, function()
        isPinned = false
        bestiaryFrame:Hide()
    end)
    bestiaryFrame.pin:SetHeight(18)
    bestiaryFrame.close:SetHeight(18)
    bestiaryFrame.pin:ClearAllPoints()
    bestiaryFrame.pin:SetPoint('TOPRIGHT', -44, -6)
    bestiaryFrame.pin:SetWidth(72)
    bestiaryFrame.close:ClearAllPoints()
    bestiaryFrame.close:SetPoint('TOPRIGHT', -13, -6)
    bestiaryFrame.portrait = CreateFrame('Frame', nil, bestiaryFrame)
    bestiaryFrame.portrait:SetSize(32, 32)
    bestiaryFrame.portrait:SetPoint('TOPLEFT', 10, -31)
    bestiaryFrame.name = createLabel(bestiaryFrame, 14, 50, -31, 240)
    bestiaryFrame.context = createLabel(bestiaryFrame, 9, 50, -49, 240)
    bestiaryFrame.context:SetTextColor(unpack(Addon.Theme.muted))
    bestiaryFrame.questLine = createLabel(bestiaryFrame, 10, 10, -65, 280)
    bestiaryFrame.questLine:SetTextColor(1, 0.82, 0.2)
    bestiaryFrame.section = createLabel(bestiaryFrame, 9, 10, -68, 280)
    bestiaryFrame.scrollbar = Addon.Scrollbar(bestiaryFrame, function(value)
        scrollOffset = value
        hideRowTooltip()
        refreshWindow()
    end)
    bestiaryFrame.scrollbar:SetPoint('TOPRIGHT', -3, -83)

    -- Source rows and their detailed tooltips
    for i = 1, 7 do
        local row = CreateFrame('Button', nil, bestiaryFrame)
        row:SetSize(278, 24)
        row:SetPoint('TOPLEFT', 10, -83 - (i - 1) * 24)
        row:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight', 'ADD')
        row.portrait = CreateFrame('Frame', nil, row)
        row.portrait:SetSize(28, 28)
        row.portrait:SetPoint('TOPLEFT', 0, -4)
        row.icon = row:CreateTexture(nil, 'ARTWORK')
        row.icon:SetSize(18, 18)
        row.icon:SetPoint('TOPLEFT', 0, -3)
        row.name = createLabel(row, 11, 24, -5, 181)
        row.detail = createLabel(row, 10, 208, -5, 65)
        row.detail:SetTextColor(unpack(Addon.Theme.text))
        row.detail:SetJustifyH('RIGHT')
        row.location = createLabel(row, 9, 0, -21, 273)
        row.location:SetTextColor(unpack(Addon.Theme.muted))
        row:SetScript('OnClick', function(self)
            if not self.entry or not selectedSubject or selectedSubject.itemID then
                return
            end
            hideRowTooltip()
            Addon.ShowBestiary(Addon.ReferenceItem(self.entry.id), false, true)
        end)
        row:SetScript('OnEnter', function(self)
            if self.entry then
                if not rowTooltipLevel then
                    rowTooltipLevel = GameTooltip:GetFrameLevel()
                    rowTooltipStrata = GameTooltip:GetFrameStrata()
                end
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
                if selectedSubject.itemID then
                    GameTooltip:SetText(self.entry.drop.name)
                    if not self.entry.drop.kind or self.entry.drop.kind == 'Skinning' then
                        GameTooltip:AddLine(T('Level ') .. Addon.LevelText(self.entry.drop), 0.8, 0.8, 0.8)
                    end
                    GameTooltip:AddLine(
                        T(self.entry.drop.zones or Addon.MonsterZones(self.entry.id)),
                        0.6,
                        0.8,
                        0.8,
                        true
                    )
                    GameTooltip:AddLine(
                        T('Source: ')
                            .. T(self.entry.drop.source or 'cMaNGOS Classic; locations: source metadata'),
                        0.6,
                        0.6,
                        0.6
                    )
                else
                    GameTooltip:SetHyperlink(self.entry.drop.link)
                end
                GameTooltip:AddLine(
                    self.entry.drop.kind == 'Skinning'
                        and (T('Skinning') .. ' / ' .. Addon.DropChance(self.entry.drop))
                        or self.entry.drop.kind and (T(self.entry.drop.kind) .. T(' source - no drop roll'))
                        or Addon.DropChance(self.entry.drop),
                    0.7,
                    0.8,
                    0.7
                )
                if self.entry.drop.quest then
                    GameTooltip:AddLine(
                        T('Quest-only drop: requires eligibility for its quest.'),
                        1,
                        0.82,
                        0.2,
                        true
                    )
                elseif self.entry.drop.conditional then
                    GameTooltip:AddLine(
                        T('This chance depends on additional loot conditions.'),
                        1,
                        0.82,
                        0.2,
                        true
                    )
                end
                for _, quest in ipairs(selectedSubject.quests or {}) do
                    GameTooltip:AddLine(
                        (quest.starts and T('Starts quest: ') or T('Related quest: ')) .. quest.name,
                        1,
                        0.82,
                        0.2,
                        true
                    )
                end
                if not selectedSubject.itemID then
                    GameTooltip:AddLine(
                        T('Click to view item sources'),
                        0.4,
                        0.9,
                        0.6,
                        true
                    )
                end
                GameTooltip:Show()
                GameTooltip:SetFrameStrata('TOOLTIP')
                GameTooltip:SetFrameLevel(bestiaryFrame:GetFrameLevel() + 20)
            end
        end)
        row:SetScript('OnLeave', hideRowTooltip)
        sourceRows[i] = row
    end
    bestiaryFrame.empty = createLabel(bestiaryFrame, 10, 10, -85, 278)
    bestiaryFrame.empty:SetWordWrap(true)
    bestiaryFrame.footer = createLabel(
        bestiaryFrame,
        9,
        10,
        -250,
        280,
        T('cMaNGOS Classic 1.12 - not verified for Forever\n* Conditional drop chance')
    )
    bestiaryFrame.footer:SetWordWrap(true)
    bestiaryFrame.footer:SetTextColor(0.65, 0.65, 0.55)
    bestiaryFrame:SetScript('OnMouseWheel', function(_, delta)
        scrollOffset = scrollOffset - delta
        hideRowTooltip()
        refreshWindow()
    end)
    bestiaryFrame:SetScript('OnHide', function()
        local owner = GameTooltip:GetOwner()
        for _, row in ipairs(sourceRows) do
            if owner == row then
                hideRowTooltip()
                break
            end
        end
    end)

    -- Lifetime rules and native tooltip hooks
    local function dismissOutside()
        if not IsAltKeyDown() then
            itemLockedForAlt = false
        end
        if isPinned or bestiaryFrame:IsMouseOver() or bestiaryFrame.scrollbar.dragging or IsAltKeyDown() then
            return
        end
        bestiaryFrame:Hide()
    end
    bestiaryFrame:SetScript('OnUpdate', dismissOutside)
    bestiaryFrame:SetScript('OnLeave', dismissOutside)
    bestiaryFrame:RegisterEvent('UPDATE_MOUSEOVER_UNIT')
    bestiaryFrame:RegisterEvent('MODIFIER_STATE_CHANGED')
    bestiaryFrame:RegisterEvent('GET_ITEM_INFO_RECEIVED')
    bestiaryFrame:SetScript('OnEvent', function(_, event, key, state)
        if event == 'MODIFIER_STATE_CHANGED' and (key == 'LALT' or key == 'RALT') and state == 0 then
            itemLockedForAlt = false
            dismissOutside()
            return
        end
        if event == 'GET_ITEM_INFO_RECEIVED' then
            if bestiaryFrame:IsShown() then
                refreshWindow()
            end
        else
            if not showHoveredItem() then
                showMouseoverCreature()
            end
            dismissOutside()
        end
    end)
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip == GameTooltip then
                showHoveredItem(data and data.id)
            end
        end)
    elseif hooksecurefunc then
        hooksecurefunc(GameTooltip, 'SetBagItem', function()
            showHoveredItem()
        end)
    end
    GameTooltip:HookScript('OnShow', function()
        showHoveredItem()
    end)
    SLASH_RAYNNABESTIARY1 = '/rb'
    SlashCmdList.RAYNNABESTIARY = function(message)
        if message == 'settings' then
            Addon.OpenSettings()
        elseif message == 'hide' then
            isPinned = false
            bestiaryFrame:Hide()
            if Addon.browser then
                Addon.browser:Hide()
            end
        elseif message == 'demo' then
            Addon.BestiaryDemo()
        else
            Addon.OpenBrowser(nil, true)
        end
    end
    bestiaryFrame:Hide()
    Addon.SetBestiaryScale = function(value)
        if Addon.browser then
            Addon.browser:SetScale(math.max(0.4, math.min(1.8, value)))
        end
        Addon.db.bestiary.scale = math.max(0.4, math.min(1.8, value))
        bestiaryFrame:SetScale(Addon.db.bestiary.scale)
    end
    Addon.SetBestiaryScale(Addon.db.bestiary.scale or 1)
end
end)
