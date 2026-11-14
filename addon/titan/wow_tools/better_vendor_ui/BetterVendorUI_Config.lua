local ns = WoWTools.betterVendorUI

function ns.InitializeConfig()

    local configFrame

    local function CreateDropTarget(parent, name, title, x, y, isWhitelist)
        local target = CreateFrame('Button', name, parent)
        target:SetSize(220, 60)
        target:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
        target:SetNormalTexture('Interface\\Tooltips\\UI-Tooltip-Background')
        target:GetNormalTexture():SetVertexColor(0, 0, 0, 0.5)

        local text = target:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        text:SetPoint('CENTER')
        text:SetText('Drop Item Here to\n' .. title)
        target.text = text

        target:SetScript('OnReceiveDrag', function(self)
            local infoType, itemID = GetCursorInfo()
            if infoType == 'item' and itemID then
                if isWhitelist then
                    ns.DB.whitelist[itemID] = true
                    ns.DB.blacklist[itemID] = nil
                else
                    ns.DB.blacklist[itemID] = true
                    ns.DB.whitelist[itemID] = nil
                end
                ClearCursor()
                ns.UpdateConfigLists()
            end
        end)
        target:SetScript('OnClick', function(self)
            target:GetScript('OnReceiveDrag')(self)
        end)
        return target
    end

    local ROW_HEIGHT = 24
    local LIST_HEIGHT = 300
    local LIST_PADDING = 4  -- above and below the list, inside its container

    local function CreateListContainer(parent, name, x, y)
        local frame = CreateFrame('Frame', name, parent)
        frame:SetSize(220, LIST_HEIGHT)
        frame:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)

        -- Named, so older templates can create their "$parentScrollBar" child
        local scroll = CreateFrame('ScrollFrame', name .. 'Scroll', frame, 'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT', 0, -LIST_PADDING)
        scroll:SetPoint('BOTTOMRIGHT', -24, LIST_PADDING)
        local content = CreateFrame('Frame', nil, scroll)
        content:SetSize(196, 1)
        scroll:SetScrollChild(content)

        frame.scroll, frame.content, frame.rows = scroll, content, {}
        return frame
    end

    local function GetListScrollBar(container)
        local scroll = container.scroll
        return scroll.ScrollBar or _G[scroll:GetName() .. 'ScrollBar']
    end

    local GetItemInfoSafe = ns.GetItemInfoSafe

    local listButtons = {}  -- every row of both lists, for skinning

    -- EllesmereUI look (see ns.OnSkin in BetterVendorUI.lua). The window and its rows are
    -- built later than the facade arrives, so keep it and skin each piece as it's created.
    -- Every primitive is a no-op on an already skinned frame.
    local skin

    local function SkinDropTarget(target)
        target:GetNormalTexture():SetAlpha(0)  -- the panel replaces the dark tooltip fill
        skin.Panel(target, { inset = true })
        skin.Font(target.text, skin.GetAccentColor())
    end

    local function SkinListRow(btn)
        if not skin then return end
        skin.SquareIcon(btn.icon, btn)
        skin.Font(btn.nameText)  -- item links keep their quality color
        skin.CloseButton(btn.delBtn)
    end

    local function SkinListContainer(container)
        skin.Panel(container, { inset = true })
        local scrollBar = GetListScrollBar(container)
        if scrollBar then skin.ScrollBar(scrollBar) end
    end

    local function SkinConfigWindow()
        if not (skin and configFrame) then return end
        skin.Shell(configFrame)
        local close = configFrame.CloseButton or _G['BetterVendorUIConfigFrameClose']
        if close then skin.CloseButton(close) end
        skin.Font(configFrame.title)
        skin.White(configFrame.title)
        SkinDropTarget(configFrame.whitelistDrop)
        SkinDropTarget(configFrame.blacklistDrop)
        SkinListContainer(configFrame.whitelistContainer)
        SkinListContainer(configFrame.blacklistContainer)
        for _, btn in ipairs(listButtons) do SkinListRow(btn) end
    end

    ns.OnSkin(function(S)
        skin = S
        SkinConfigWindow()
        -- Drop target labels use the accent color, which can change live
        S.OnLooksChanged(function()
            if configFrame then
                S.Font(configFrame.whitelistDrop.text, S.GetAccentColor())
                S.Font(configFrame.blacklistDrop.text, S.GetAccentColor())
            end
        end)
    end)

    local function GetListRow(container, n)
        local btn = container.rows[n]
        if btn then return btn end

        btn = CreateFrame('Button', nil, container.content)
        btn:SetSize(180, ROW_HEIGHT)
        btn:SetPoint('TOPLEFT', container.content, 'TOPLEFT', 10, -(n - 1) * ROW_HEIGHT)

        local icon = btn:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(20, 20)
        icon:SetPoint('LEFT', 2, 0)
        btn.icon = icon

        local nameText = btn:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        nameText:SetPoint('LEFT', icon, 'RIGHT', 5, 0)
        nameText:SetPoint('RIGHT', btn, 'RIGHT', -25, 0)
        nameText:SetJustifyH('LEFT')
        btn.nameText = nameText

        local delBtn = CreateFrame('Button', nil, btn, 'UIPanelCloseButton')
        delBtn:SetSize(24, 24)
        delBtn:SetPoint('RIGHT', btn, 'RIGHT', 0, 0)
        delBtn:SetScript('OnClick', function()
            btn.dbList[btn.itemID] = nil
            ns.UpdateConfigLists()
        end)
        btn.delBtn = delBtn

        SkinListRow(btn)
        container.rows[n] = btn
        table.insert(listButtons, btn)
        return btn
    end

    -- Loaded items by name, then the ones still loading by ID
    local function CompareEntries(a, b)
        if a.name and b.name then
            if a.name ~= b.name then return a.name < b.name end
        elseif a.name or b.name then
            return a.name ~= nil
        end
        return a.id < b.id
    end

    local function DrawList(dbList, container)
        local entries = {}
        for itemID in pairs(dbList) do
            local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = GetItemInfoSafe(itemID)
            table.insert(entries, { id = itemID, name = itemName, link = itemLink, icon = itemIcon })
        end
        table.sort(entries, CompareEntries)

        for n, entry in ipairs(entries) do
            local btn = GetListRow(container, n)
            btn.dbList, btn.itemID = dbList, entry.id
            if entry.name then
                btn.icon:SetTexture(entry.icon)
                btn.nameText:SetText(entry.link)
            else
                btn.icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
                btn.nameText:SetText('Loading ' .. entry.id .. '...')
                ns.RequestItem(entry.id)  -- the list redraws itself when it arrives
            end
            btn:Show()
        end
        for n = #entries + 1, #container.rows do container.rows[n]:Hide() end

        local height = #entries * ROW_HEIGHT
        container.content:SetHeight(math.max(height, 1))
        -- Scrollbar only when there's something to scroll
        local fits = height <= LIST_HEIGHT - 2 * LIST_PADDING
        local scrollBar = GetListScrollBar(container)
        if scrollBar then scrollBar:SetShown(not fits) end
        if fits then container.scroll:SetVerticalScroll(0) end
    end

    function ns.UpdateConfigLists()
        ns.SyncLeatrix()
        ns.RefreshEllesmereBags()  -- junk badges follow our lists
        if ns.RefreshOptions then ns.RefreshOptions() end
        if not configFrame or not configFrame:IsShown() then return end

        DrawList(ns.DB.whitelist, configFrame.whitelistContainer)
        DrawList(ns.DB.blacklist, configFrame.blacklistContainer)
    end

    -- Next to the merchant window; it has no position of its own while closed
    local function SetDefaultPosition()
        configFrame:ClearAllPoints()
        if MerchantFrame:IsShown() then
            configFrame:SetPoint('TOPLEFT', MerchantFrame, 'TOPRIGHT', -30, 0)
        else
            configFrame:SetPoint('CENTER', UIParent, 'CENTER')
        end
    end

    function ns.ResetConfigPosition()
        ns.DB.configPos = nil
        if configFrame then SetDefaultPosition() end
    end

    function ns.ToggleConfig()
        if not configFrame then
            configFrame = CreateFrame('Frame', 'BetterVendorUIConfigFrame', UIParent, 'UIPanelDialogTemplate')
            configFrame:Hide()
            configFrame:SetSize(480, 420)
            table.insert(UISpecialFrames, 'BetterVendorUIConfigFrame')  -- Escape closes it

            configFrame:SetFrameStrata('DIALOG')
            configFrame:SetMovable(true)
            configFrame:EnableMouse(true)
            configFrame:RegisterForDrag('LeftButton')
            configFrame:SetScript('OnDragStart', configFrame.StartMoving)
            configFrame:SetScript('OnDragStop', function(self)
                self:StopMovingOrSizing()
                local point, _, relPoint, x, y = self:GetPoint()
                ns.DB.configPos = { point, relPoint, x, y }
            end)
            configFrame:SetClampedToScreen(true)
            local pos = ns.DB.configPos
            if pos then
                configFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
            end

            local title = configFrame.Title or _G['BetterVendorUIConfigFrameTitleText']
            if not title then
                title = configFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
                title:SetPoint('TOP', configFrame, 'TOP', 0, -9)
            end
            title:SetText('Better Vendor UI Lists')
            configFrame.title = title

            configFrame.whitelistDrop = CreateDropTarget(configFrame, 'BetterVendorUIWhitelistDrop', 'ALWAYS SELL', 15, -40, true)
            configFrame.blacklistDrop = CreateDropTarget(configFrame, 'BetterVendorUIBlacklistDrop', 'NEVER SELL', 245, -40, false)

            configFrame.whitelistContainer = CreateListContainer(configFrame, 'BetterVendorUIWhitelistContainer', 15, -110)
            configFrame.blacklistContainer = CreateListContainer(configFrame, 'BetterVendorUIBlacklistContainer', 245, -110)

            configFrame:SetScript('OnShow', function()
                ns.UpdateConfigLists()
            end)
            SkinConfigWindow()  -- EllesmereUI look, when its skinning is on
        end

        if configFrame:IsShown() then
            configFrame:Hide()
        else
            -- The merchant window may have opened or closed since the last time
            if not ns.DB.configPos then SetDefaultPosition() end
            configFrame:Show()
        end
    end

end
