WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Bestiary window. Presents NPC drops or item sources without modifying tracking history.
-- Hover locking, pinning, scrolling and tooltip ownership are local UI state.

local _, Addon = ...
local T = Addon.Text
local bestiaryFrame, selectedSubject, showingPreview, isPinned = nil, nil, false, false
local sourceRows, requestedItems = {}, {}
local columns = { { rows = {}, offset = 0 }, { rows = {}, offset = 0 } }
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
local isReadableValue = Addon.IsReadableValue

local function sourceNPC(entry)
    if entry.drop.npcID then return entry.drop.npcID end
    if not entry.drop.kind then return entry.id end
    return entry.drop.kind == 'Vendor' and tonumber(tostring(entry.id):match('^vendor:(%d+)$')) or nil
end

local function showSourceOnMap(npcID, objectID, name, levelText)
    hideRowTooltip()
    local opened, message = Addon.ShowSourceLocation({
        npcID = npcID, objectID = objectID, title = name, levelText = levelText,
    })
    if opened then bestiaryFrame:Hide() end
    if message then print(T("Raynna's Bestiary") .. ': ' .. message) end
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

local function positionBesideCursor()
    bestiaryFrame:SetScale(Addon.db.bestiary.scale or 1)
    local x, y = GetCursorPosition()
    local parentScale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * parentScale, UIParent:GetHeight() * parentScale
    local scale = bestiaryFrame:GetEffectiveScale()
    local gap, margin = 16, 8
    local rightSpace = screenWidth - margin - x - gap
    local leftSpace = x - gap - margin
    local width, height = bestiaryFrame:GetWidth() * scale, bestiaryFrame:GetHeight() * scale
    -- Fit the whole window on one side, including both columns at larger saved scales.
    local fit = math.min(1, math.max(leftSpace, rightSpace) / width, (screenHeight - 2 * margin) / height)
    bestiaryFrame:SetScale((Addon.db.bestiary.scale or 1) * fit)
    scale = bestiaryFrame:GetEffectiveScale()
    width, height = bestiaryFrame:GetWidth() * scale, bestiaryFrame:GetHeight() * scale
    local left = width <= rightSpace and (x + gap) or (x - gap - width)
    local top = math.max(margin + height, math.min(screenHeight - margin, y - 12))
    bestiaryFrame:ClearAllPoints()
    bestiaryFrame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left / scale, top / scale)
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
    local hasSkinning = not selectedSubject.itemID and next(selectedSubject.skinning or {}) ~= nil
    bestiaryFrame:SetWidth(hasSkinning and 600 or 300)
    bestiaryFrame.name:SetWidth((hasSkinning and 540 or 240) - (selectedSubject.mapAvailable and 90 or 0))
    bestiaryFrame.context:SetWidth(hasSkinning and 540 or 240)
    bestiaryFrame.skinningFooter:SetShown(hasSkinning)
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
    bestiaryFrame.map:SetShown(selectedSubject.mapAvailable)
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
    local rowHeight = selectedSubject.itemID and 36 or 24
    local maximumRows = 1
    for index, column in ipairs(columns) do
        column.frame:SetShown(index == 1 or hasSkinning)
        column.frame:ClearAllPoints()
        column.frame:SetPoint('TOPLEFT', (index - 1) * 300, -68 - questSpace)
        local entries = {}
        for id, drop in pairs((index == 1 and selectedSubject.drops or selectedSubject.skinning) or {}) do
            entries[#entries + 1] = { id = id, drop = drop }
        end
        table.sort(entries, function(a, b)
            if selectedSubject.recipeItem then
                local aVendor, bVendor = a.drop.kind == 'Vendor', b.drop.kind == 'Vendor'
                if aVendor ~= bVendor then
                    return aVendor
                end
            end
            if (a.drop.rate or -1) ~= (b.drop.rate or -1) then
                return (a.drop.rate or -1) > (b.drop.rate or -1)
            end
            return tostring(a.id) < tostring(b.id)
        end)
        column.offset = math.max(0, math.min(column.offset, #entries - 7))
        local heading = index == 2 and T('SKINNING  /  ')
            or selectedSubject.itemID and T('SOURCES  /  ') or T('POSSIBLE DROPS  /  ')
        column.section:SetText(heading .. #entries)
        column.empty:SetShown(#entries == 0)
        column.empty:SetText(
            selectedSubject.itemID
                and T('No known source in the loaded databases.\nCoverage is incomplete for Forever.')
                or T('No source data for this creature ID.\nYour personal loot log is not used here.')
        )
        local shownRows = math.max(1, math.min(7, #entries))
        maximumRows = math.max(maximumRows, shownRows)
        column.frame:SetHeight(15 + shownRows * rowHeight)
        column.scrollbar:Update(#entries, 7, column.offset, shownRows * rowHeight)
        for i, row in ipairs(column.rows) do
            row:SetHeight(rowHeight)
            row:ClearAllPoints()
            row:SetPoint('TOPLEFT', 10, -15 - (i - 1) * rowHeight)
            row.location:SetShown(not not selectedSubject.itemID)
            row.entry = entries[column.offset + i]
            row:SetShown(row.entry ~= nil)
            if row.entry then
                local item, sourceRecord = row.entry.id, row.entry.drop
                if selectedSubject.itemID then
                    row.icon:Hide()
                    local creatureSource = not sourceRecord.kind or sourceRecord.kind == 'Skinning'
                    local npcID = sourceNPC(row.entry)
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
                    sourceRecord.zones = creatureSource and (sourceRecord.details or Addon.MonsterZones(npcID))
                        or T(sourceRecord.details or 'Zone unavailable')
                    local location = creatureSource
                        and (T('Lv ') .. Addon.LevelText(sourceRecord) .. ' / ' .. sourceRecord.zones)
                        or sourceRecord.zones
                    if sourceRecord.kind == 'Skinning' then
                        location = T('Skinning') .. ' / ' .. location
                    end
                    row.location:SetText(location)
                    row.detail:SetText(
                        selectedSubject.recipeItem and sourceRecord.kind == 'Vendor' and T('Vendor sale')
                            or not creatureSource and T(sourceRecord.kind)
                            or (sourceRecord.rate and Addon.DropChance(sourceRecord, true) or '?')
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
                    row.detail:SetText(sourceRecord.rate and Addon.DropChance(sourceRecord, true) or '?')
                    if not name and not requestedItems[item] and C_Item and C_Item.RequestLoadItemDataByID then
                        requestedItems[item] = true
                        C_Item.RequestLoadItemDataByID(item)
                    end
                end
            end
        end
    end
    bestiaryFrame:SetHeight(116 + questSpace + maximumRows * rowHeight)
    bestiaryFrame.footer:ClearAllPoints()
    bestiaryFrame.footer:SetPoint('BOTTOMLEFT', 10, 8)
end

-- Open, position and raise the window
function Addon.ShowBestiary(monster, demo, pin)
    if not bestiaryFrame then
        return
    end
    selectedSubject, showingPreview, isPinned = monster, not not demo, not not pin
    monster.mapAvailable = monster.npcID ~= nil and #Addon.SourceLocations(monster.npcID) > 0
    for _, column in ipairs(columns) do column.offset = 0 end
    Addon.HideDrops(true)
    refreshWindow()
    if not isPinned then
        positionBesideCursor()
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
local function itemID(value)
    if isReadableValue(value) and type(value) == 'number' and value > 0 then
        return value
    end
end

local function linkItemID(link)
    if isReadableValue(link) and type(link) == 'string' then
        return itemID(tonumber(link:match('item:(%d+)')))
    end
end

local function hoveredItemID()
    local info = GameTooltip.GetPrimaryTooltipInfo and GameTooltip:GetPrimaryTooltipInfo()
    if info then
        local data = info.tooltipData
        if info.append or not data or not isReadableValue(data.type) or data.type ~= Enum.TooltipDataType.Item then
            return nil
        end
        local args = info.getterArgs
        -- A recipe tooltip can report the crafted item's ID in its rendered data.
        local requestedID
        if args and info.getterName == 'GetItemByID' then
            requestedID = itemID(args[1])
        elseif args and info.getterName == 'GetHyperlink' then
            requestedID = linkItemID(args[1])
        elseif args and info.getterName == 'GetBagItem' and C_Container and C_Container.GetContainerItemID then
            local bag, slot = args[1], args[2]
            if isReadableValue(bag) and type(bag) == 'number' and itemID(slot) then
                requestedID = itemID(C_Container.GetContainerItemID(bag, slot))
            end
        end
        return requestedID or linkItemID(data.hyperlink) or itemID(data.id)
    end
    if GameTooltip:IsShown() then
        local ok, _, link = pcall(GameTooltip.GetItem, GameTooltip)
        return ok and linkItemID(link)
    end
end

local function showHoveredItem()
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
    local id = hoveredItemID()
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
    local ok, guid = pcall(UnitGUID, 'mouseover')
    if not ok or not isReadableValue(guid) or type(guid) ~= 'string' then
        return
    end
    local id = tonumber(guid:match('^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-'))
    if not id then
        return
    end
    local nameOK, name = pcall(UnitName, 'mouseover')
    local levelOK, level = pcall(UnitLevel, 'mouseover')
    name = nameOK and isReadableValue(name) and type(name) == 'string' and name or nil
    level = levelOK and isReadableValue(level) and type(level) == 'number' and level > 0 and level or nil
    local monster = Addon.ReferenceMonster(id, name, level)
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
    bestiaryFrame.map = button(bestiaryFrame, T('Show on map'), 0, 0, 86, function()
        if not selectedSubject or not selectedSubject.npcID then return end
        showSourceOnMap(selectedSubject.npcID, nil, selectedSubject.name, T('Lv ') .. Addon.LevelText(selectedSubject))
    end)
    bestiaryFrame.map:ClearAllPoints()
    bestiaryFrame.map:SetPoint('TOPRIGHT', -13, -29)
    bestiaryFrame.map:SetHeight(18)
    bestiaryFrame.questLine = createLabel(bestiaryFrame, 10, 10, -65, 280)
    bestiaryFrame.questLine:SetTextColor(1, 0.82, 0.2)
    bestiaryFrame.columns = columns
    for index, column in ipairs(columns) do
        column.frame = CreateFrame('Frame', nil, bestiaryFrame)
        column.frame:SetSize(300, 200)
        column.frame:SetPoint('TOPLEFT', (index - 1) * 300, -68)
        column.frame:EnableMouseWheel(true)
        column.section = createLabel(column.frame, 9, 10, 0, 280)
        column.scrollbar = Addon.Scrollbar(column.frame, function(value)
            column.offset = value
            hideRowTooltip()
            refreshWindow()
        end)
        column.scrollbar:SetPoint('TOPRIGHT', -3, -15)
        column.empty = createLabel(column.frame, 10, 10, -17, 278)
        column.empty:SetWordWrap(true)
        column.frame:SetScript('OnMouseWheel', function(_, delta)
            column.offset = column.offset - delta
            hideRowTooltip()
            refreshWindow()
        end)

        -- Source rows and their detailed tooltips
        for i = 1, 7 do
            local row = CreateFrame('Button', nil, column.frame)
            row:SetSize(278, 24)
            row:SetPoint('TOPLEFT', 10, -15 - (i - 1) * 24)
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
            row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            row:SetScript('OnClick', function(self, mouseButton)
                if not self.entry or not selectedSubject then
                    return
                end
                if selectedSubject.itemID then
                    local source = self.entry.drop
                    if mouseButton == 'RightButton' then
                        local npcID = sourceNPC(self.entry)
                        if npcID or source.objectID then
                            showSourceOnMap(npcID, source.objectID, source.name, nil)
                        end
                    elseif source.itemID then
                        hideRowTooltip()
                        Addon.ShowBestiary(Addon.ReferenceItem(source.itemID), false, true)
                    end
                    return
                end
                if mouseButton ~= 'LeftButton' then return end
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
                        if #Addon.SourceLocations(sourceNPC(self.entry), self.entry.drop.objectID) > 0 then
                            GameTooltip:AddLine(T('Right-click to show on map'), 0.4, 0.9, 0.6, true)
                        end
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
            sourceRows[#sourceRows + 1] = row
            column.rows[i] = row
        end
    end
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
    bestiaryFrame.skinningFooter = createLabel(bestiaryFrame, 9, 310, 0, 280,
        T('cMaNGOS Classic 1.12 - not verified for Forever\n* Conditional drop chance'))
    bestiaryFrame.skinningFooter:ClearAllPoints()
    bestiaryFrame.skinningFooter:SetPoint('BOTTOMLEFT', 310, 8)
    bestiaryFrame.skinningFooter:SetWordWrap(true)
    bestiaryFrame.skinningFooter:SetTextColor(0.65, 0.65, 0.55)
    bestiaryFrame:SetScript('OnMouseWheel', function(_, delta)
        columns[1].offset = columns[1].offset - delta
        hideRowTooltip()
        refreshWindow()
    end)
    bestiaryFrame:SetScript('OnHide', function()
        isPinned, itemLockedForAlt = false, false
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
        if isPinned or bestiaryFrame:IsMouseOver() or columns[1].scrollbar.dragging
            or columns[2].scrollbar.dragging or IsAltKeyDown() then
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
            -- Appended item previews must not take the first selection in an Alt press.
            if tooltip == GameTooltip and data == tooltip:GetPrimaryTooltipData() then
                showHoveredItem()
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
        if bestiaryFrame:IsShown() and not isPinned then
            positionBesideCursor()
        end
    end
    Addon.SetBestiaryScale(Addon.db.bestiary.scale or 1)
end
end)
