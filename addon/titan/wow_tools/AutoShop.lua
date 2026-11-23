-- Automatic purchases run only in an explicitly activated shopping mode.
local mode, session, canBuy, merchantOpen, selectedGossip, buyUntil
local rules, pending, receipt, skipped = {}, nil, nil, {}
local exitOnPurchase = false
local menuReadyAt, updateAt = 0, 0
local stateText, loadSavedRules
local events = CreateFrame("Frame")
local signal = CreateFrame("Frame", nil, UIParent)
signal:SetSize(16, 16)
signal:SetPoint("CENTER", WoWTools.detectorAnchor, "CENTER")
signal:SetFrameStrata("TOOLTIP")
signal:SetFrameLevel(10000)
signal:EnableMouse(false)
if signal.SetIgnoreParentAlpha then signal:SetIgnoreParentAlpha(true) end
local main = signal:CreateTexture(nil, "OVERLAY")
main:SetAllPoints(signal)
signal:Hide()

-- Match the three observed states in wowAuto.Rotation.Native.cs.
local shopColors = {
    closed = {52, 120, 230},
    open = {154, 211, 67},
    bought = {71, 218, 181},
}
local popupKinds = {
    "CONFIRM_HIGH_COST_ITEM",
    "CONFIRM_PURCHASE_TOKEN_ITEM",
    "CONFIRM_PURCHASE_NONREFUNDABLE_ITEM",
}
local function Number(value, minimum)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value >= minimum and value <= 2147483647 and value == math.floor(value)
end

local function SingleRuleID(list)
    local id = next(list)
    if id and not next(list, id) then return id end
end

local function Say(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("wow_tools 购物：" .. text) end
end

local function RefreshStatus()
    if session then
        local _, physicalHeight = GetPhysicalScreenSize()
        local ratio = physicalHeight and physicalHeight > 0 and UIParent:GetHeight() / physicalHeight or 1
        signal:SetSize(16 * ratio, 16 * ratio)
        local state = session.bought and "bought" or merchantOpen and "open" or "closed"
        local color = shopColors[state]
        main:SetColorTexture(color[1]/255, color[2]/255, color[3]/255, 1)
        signal:Show()
    else
        signal:Hide()
    end
    if stateText then
        local text = "自动购物模式已关闭"
        if mode == "manual" then text = "自动购物模式已开启"
        elseif session then
            if session.bought then text = "已买到，等待 wowAuto 下线"
            elseif merchantOpen then text = "商店已打开"
            else text = "商店已关闭" end
        end
        stateText:SetText(text)
    end
end

local function OwnsPopup(transaction)
    local popup = transaction.popup
    return popup and popup:IsShown() and popup.which == transaction.which and popup.data == transaction.popupData
        and MerchantFrame.itemIndex == transaction.index and MerchantFrame.count == transaction.amount
end

local function FinishPurchases()
    local popup = pending and OwnsPopup(pending) and pending.popup
    pending, canBuy, skipped, selectedGossip, buyUntil = nil, false, {}, false, nil
    if not session then events:SetScript("OnUpdate", nil) end
    if popup then popup:Hide() end
end

local function CloseStore()
    FinishPurchases()
    if merchantOpen and MerchantFrame and MerchantFrame:IsShown() then CloseMerchant() end
end

local function Stop()
    local wasScripted = session ~= nil
    mode, session = nil, nil
    if wasScripted then CloseStore() else FinishPurchases() end
    RefreshStatus()
end

local function MarkBought(transaction)
    receipt = nil
    session.bought = true
    CloseStore()
    events:SetScript("OnUpdate", nil)
    RefreshStatus()
    Say(transaction.link .. " 已买到，等待 wowAuto 下线。")
end

local function AtMerchant()
    return MerchantFrame and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1
        and not InCombatLockdown() and not UnitIsDeadOrGhost("player") and not CursorHasItem()
end

local function CountBags()
    local counts = {}
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        if not Number(slots, 0) then return end
        for slot = 1, slots do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if issecretvalue and issecretvalue(item) then return end
            if item then
                local id, count = item.itemID, item.stackCount
                if not Number(id, 1) or not Number(count, 1) then return end
                if rules[id] then counts[id] = (counts[id] or 0) + count end
            end
        end
    end
    return counts
end

local function MerchantItem(index, id)
    local name, texture, price, stackCount, numAvailable, isPurchasable, _, hasExtendedCost = GetMerchantItemInfo(index)
    if not name then return end
    local heirloom = ClassicExpansionAtLeast(LE_EXPANSION_WRATH_OF_THE_LICH_KING) and C_Heirloom.IsItemHeirloom(id)
    return {name = name, texture = texture, price = price, stackCount = stackCount,
        numAvailable = numAvailable, isPurchasable = isPurchasable, hasExtendedCost = hasExtendedCost,
        showNonrefundablePrompt = heirloom}
end

local function VisiblePurchasePopup()
    for _, which in ipairs(popupKinds) do
        local popup = StaticPopup_FindVisible(which)
        if popup then return popup end
    end
end

local function Buy(index, link, id, item, count, amount)
    local product = {
        GetID = function() return index end,
        link = link, name = item.name, texture = item.texture,
        price = item.price, count = item.stackCount,
        showNonrefundablePrompt = item.showNonrefundablePrompt,
    }
    local transaction = {id = id, index = index, link = link, count = count, amount = amount, expires = GetTime() + 4}
    if session and session.exitItemID == id then transaction.exitSession = session end
    pending = transaction
    if product.showNonrefundablePrompt or (item.hasExtendedCost and GetMerchantItemCostInfo(index) > 0) then
        MerchantFrame_ConfirmExtendedItemCost(product, amount)
    elseif item.price * amount / item.stackCount >= MERCHANT_HIGH_PRICE_COST then
        product.price = item.price / item.stackCount
        MerchantFrame_ConfirmHighCostItem(product, amount)
    else
        BuyMerchantItem(index, amount)
    end
    local popup = VisiblePurchasePopup()
    if popup then
        transaction.popup, transaction.which, transaction.popupData = popup, popup.which, popup.data
        transaction.expires = GetTime() + 8
    else
        receipt = transaction
    end
end

local function WaitForPurchase(now, counts)
    local transaction = pending
    if not transaction then
        if receipt and (counts[receipt.id] or 0) < receipt.count + receipt.amount and now < receipt.expires then return true end
        receipt = nil
        return false
    end
    local count = counts[transaction.id] or 0
    if OwnsPopup(transaction) then
        if count + transaction.amount > (rules[transaction.id] or 0)
            or GetMerchantItemLink(transaction.index) ~= transaction.link or now >= transaction.expires then
            transaction.popup:Hide()
        else
            local confirm = transaction.popup:GetButton1()
            if confirm and confirm:IsEnabled() then
                transaction.popup = nil
                transaction.expires = now + 4
                receipt = transaction
                confirm:Click()
            end
            return true
        end
    elseif not transaction.popup then
        if count >= transaction.count + transaction.amount then
            pending, receipt = nil, nil
            Say(transaction.link .. " 已补到 " .. count .. " 个。")
            return false
        end
        if now < transaction.expires then return true end
    end
    skipped[transaction.id], pending = true, nil
    Say(transaction.link .. " 未收到完整购买结果，本次访问停止购买该商品。")
    return false
end

local function AwaitingExitReceipt(now)
    return session and receipt and receipt.exitSession == session and now < receipt.expires
end

local function Update(now)
    -- A submitted purchase can reach the bags after the merchant window closes.
    local awaitingExitReceipt = AwaitingExitReceipt(now)
    if awaitingExitReceipt and now >= updateAt then
        updateAt = now + 0.05
        local counts = CountBags()
        if counts and (counts[receipt.id] or 0) > receipt.count then
            MarkBought(receipt)
            return
        end
    end
    if session and session.finishing then
        if not awaitingExitReceipt then Stop() end
        return
    end
    if buyUntil and now >= buyUntil then FinishPurchases() end
    if awaitingExitReceipt or not merchantOpen or not canBuy or now < menuReadyAt or now < updateAt then return end
    updateAt = now + 0.05
    if not AtMerchant() then FinishPurchases(); return end
    local counts = CountBags()
    if not counts then
        if now >= menuReadyAt + 1.5 then FinishPurchases() end
        return
    end
    if WaitForPurchase(now, counts) then return end
    if VisiblePurchasePopup() then FinishPurchases(); return end

    local total = GetMerchantNumItems()
    if not Number(total, 0) then FinishPurchases(); return end
    local loading = total == 0
    for index = 1, total do
        local link = GetMerchantItemLink(index)
        if issecretvalue and issecretvalue(link) then link = nil end
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        local limit = id and rules[id]
        loading = loading or not link
        if limit and not skipped[id] then
            local item, count = MerchantItem(index, id), counts[id] or 0
            if item and count < limit and item.isPurchasable and Number(item.stackCount, 1)
                and Number(item.price, 0) and (item.numAvailable == -1 or Number(item.numAvailable, 0)) then
                local maxStack = GetMerchantItemMaxStack(index)
                if Number(maxStack, 1) then
                    local amount = math.min(limit - count, maxStack)
                    if item.numAvailable >= 0 then amount = math.min(amount, item.numAvailable) end
                    if item.price > 0 then amount = math.min(amount, math.floor(GetMoney() * item.stackCount / item.price)) end
                    amount = amount - amount % item.stackCount
                    if amount > 0 then Buy(index, link, id, item, count, amount); return end
                end
            end
        end
    end
    if not loading or now >= menuReadyAt + 1.5 then FinishPurchases() end
end

local function Tick()
    local ok, err = pcall(Update, GetTime())
    if not ok then
        Stop()
        Say("本次购物已停止，客户端返回：" .. tostring(err))
    end
end

local function StartManual()
    if not next(rules) then Say("请先保存物品 ID 和背包上限。"); return end
    Stop()
    WoWTools.ActivateDetector("auto_shop")
    mode = "manual"
    RefreshStatus()
end

local function StartScripted()
    if not next(rules) or InCombatLockdown() or UnitIsDeadOrGhost("player")
        or not UnitExists("target") or UnitIsPlayer("target") then
        if session then Stop() end
        return
    end
    -- Re-arm the current client without closing a store that is already visible.
    FinishPurchases()
    WoWTools.ActivateDetector("auto_shop")
    mode = "script"
    session = { exitItemID = exitOnPurchase and SingleRuleID(rules) }
    merchantOpen = MerchantFrame and MerchantFrame:IsShown() or false
    events:SetScript("OnUpdate", Tick)
    RefreshStatus()
end

local function OpenVendorOption()
    if not session or selectedGossip or not buyUntil or GetTime() >= buyUntil then return end
    for _, option in ipairs(C_GossipInfo.GetOptions()) do
        -- vendorgossipicon.blp is the interaction icon used by item vendors.
        if option.icon == 132060 and option.status == 0 then
            selectedGossip = true
            if option.gossipOptionID then C_GossipInfo.SelectOption(option.gossipOptionID)
            else C_GossipInfo.SelectOptionByIndex(option.orderIndex) end
            return
        end
    end
end

for _, event in ipairs({"ADDON_LOADED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "GOSSIP_SHOW",
    "PLAYER_DEAD", "PLAYER_REGEN_DISABLED", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT",
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= "wow_tools" then return end
        if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
        local stored = wowDetectorDB.autoShop
        if type(stored) == "table" then
            for id, limit in pairs(stored) do
                if Number(id, 1) and Number(limit, 1) then rules[id] = limit end
            end
        end
        exitOnPurchase = SingleRuleID(rules) ~= nil and wowDetectorDB.autoShopExitOnPurchase == true
        if loadSavedRules then loadSavedRules() end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        RefreshStatus()
    elseif event == "MERCHANT_SHOW" then
        if not merchantOpen then
            merchantOpen = true
            local now = GetTime()
            menuReadyAt, updateAt = now + 0.05, now
            if mode == "manual" then
                canBuy = true
                events:SetScript("OnUpdate", Tick)
            elseif session and not session.bought then
                canBuy = buyUntil and now < buyUntil
                buyUntil = nil
                RefreshStatus()
            end
        end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        FinishPurchases()
        RefreshStatus()
    elseif event == "GOSSIP_SHOW" then
        OpenVendorOption()
    elseif event == "PLAYER_REGEN_DISABLED" and session then
        CloseStore()
    else
        Stop()
    end
end)

local function ItemName(id)
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not getter then return end
    local ok, name = pcall(getter, id)
    if ok and not (issecretvalue and issecretvalue(name)) and type(name) == "string" and name ~= "" then
        return name
    end
end

local function CursorItemID()
    local ok, kind, value = pcall(GetCursorInfo)
    if not ok or (issecretvalue and issecretvalue(kind)) then return end
    if kind == "item" and Number(value, 1) then return value end
    if kind == "merchant" and Number(value, 1) then
        local link = GetMerchantItemLink(value)
        if issecretvalue and issecretvalue(link) then return end
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if Number(id, 1) then return id end
    end
end

local function NumericInput(parent, width)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetSize(width, 24)
    input:SetAutoFocus(false)
    input:SetNumeric(true)
    input:SetMaxLetters(10)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    input:SetScript("OnEnterPressed", input.ClearFocus)
    return input
end

local function BuildSettings(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    local idLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    idLabel:SetPoint("TOPLEFT", 16, -22)
    idLabel:SetText("物品 ID")
    local idInput = NumericInput(panel, 116)
    idInput:SetPoint("LEFT", idLabel, "RIGHT", 12, 0)
    local limitLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    limitLabel:SetPoint("LEFT", idInput, "RIGHT", 16, 0)
    limitLabel:SetText("数量")
    local limitInput = NumericInput(panel, 96)
    limitInput:SetPoint("LEFT", limitLabel, "RIGHT", 12, 0)
    local add = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    add:SetSize(72, 24)
    add:SetPoint("LEFT", limitInput, "RIGHT", 12, 0)
    add:SetText("添加")

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -52)
    hint:SetText("可将背包或商店物品拖入下方清单。数量为背包上限，可直接在表内修改。")

    local list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 16, -78)
    list:SetPoint("BOTTOMRIGHT", -16, 124)
    list:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    list:SetBackdropColor(0.07, 0.07, 0.08, 1)
    list:SetBackdropBorderColor(0.48, 0.51, 0.56, 1)

    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 2, -30)
    scroll:SetPoint("BOTTOMRIGHT", -25, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local nameHeader = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameHeader:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", 8, 8)
    nameHeader:SetText("物品名称")
    local quantityHeader = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    quantityHeader:SetPoint("BOTTOMLEFT", scroll, "TOPRIGHT", -102, 8)
    quantityHeader:SetText("数量")
    local idHeader = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    idHeader:SetPoint("LEFT", quantityHeader, "LEFT", -128, 0)
    idHeader:SetText("ID")

    local delete = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    delete:SetSize(112, 24)
    delete:SetPoint("BOTTOMRIGHT", -16, 86)
    delete:SetText("删除选中项")
    delete:Disable()
    local exitCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    exitCheck:SetSize(24, 24)
    exitCheck:SetPoint("BOTTOMLEFT", 12, 82)
    exitCheck.Text:SetText("买到后下线并关闭游戏（仅限 wowAuto 单商品任务）")
    local rows, rowsByID, spareRows = {}, {}, {}
    local selected
    local rowHeight = 30

    local function ResizeList()
        content:SetSize(math.max(1, scroll:GetWidth()), math.max(1, scroll:GetHeight(), #rows * rowHeight))
        scroll:UpdateScrollChildRect()
    end
    scroll:HookScript("OnSizeChanged", ResizeList)
    panel:SetScript("OnShow", ResizeList)

    local function LayoutRows()
        for index, row in ipairs(rows) do
            local y = -(index - 1) * rowHeight
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
        end
        ResizeList()
        exitCheck:SetEnabled(#rows == 1)
    end

    local function SelectRow(row)
        if selected then selected.highlight:Hide() end
        selected = row
        if selected then selected.highlight:Show() end
        delete:SetEnabled(selected ~= nil)
    end

    local AddDroppedItem
    local function BindDrop(target, row)
        target:EnableMouse(true)
        target:SetScript("OnReceiveDrag", function() AddDroppedItem() end)
        target:HookScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and not AddDroppedItem() and row then SelectRow(row) end
        end)
    end

    local nameEvents = CreateFrame("Frame", nil, panel)
    nameEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    nameEvents:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    nameEvents:SetScript("OnEvent", function(_, _, id, success)
        if not Number(id, 1) then return end
        local row = rowsByID[id]
        if row then
            row.nameLabel:SetText(ItemName(id) or (success and "名称加载中…" or "未知物品"))
        end
    end)

    local function InsertRow(id, limit)
        local row = table.remove(spareRows)
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(rowHeight)
            row.highlight = row:CreateTexture(nil, "BACKGROUND")
            row.highlight:SetAllPoints(row)
            row.highlight:SetColorTexture(0.2, 0.45, 0.7, 0.45)
            row.highlight:Hide()

            row.quantity = NumericInput(row, 92)
            row.quantity:SetPoint("RIGHT", -10, 0)
            row.quantity:HookScript("OnEditFocusGained", function() SelectRow(row) end)
            row.idLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.idLabel:SetPoint("LEFT", row.quantity, "LEFT", -128, 0)
            row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.nameLabel:SetPoint("LEFT", 8, 0)
            row.nameLabel:SetPoint("RIGHT", row.idLabel, "LEFT", -14, 0)
            row.nameLabel:SetJustifyH("LEFT")
            row.nameLabel:SetWordWrap(false)
            row.nameLabel:SetMaxLines(1)
            BindDrop(row, row)
            BindDrop(row.quantity, row)
        end
        row.itemID = id
        row.idLabel:SetText(tostring(id))
        row.quantity:SetText(tostring(limit))
        rows[#rows + 1], rowsByID[id] = row, row
        local name = ItemName(id)
        row.nameLabel:SetText(name or "名称加载中…")
        if not name and C_Item and C_Item.RequestLoadItemDataByID then
            local ok, requested = pcall(C_Item.RequestLoadItemDataByID, id)
            if not ok or requested == false then row.nameLabel:SetText(ItemName(id) or "未知物品") end
        end
        row:Show()
        return row
    end

    local function AddItem(id, limit)
        local row = rowsByID[id]
        if row then
            Say("该物品已在清单中，可直接修改该行数量。")
        else
            row = InsertRow(id, limit)
            LayoutRows()
        end
        SelectRow(row)
    end

    AddDroppedItem = function()
        local id = CursorItemID()
        if not id then return false end
        ClearCursor()
        AddItem(id, 1)
        return true
    end
    BindDrop(list)
    BindDrop(scroll)
    BindDrop(content)

    local function AddFromInputs()
        local id, limit = tonumber(idInput:GetText()), tonumber(limitInput:GetText())
        if not Number(id, 1) or not Number(limit, 1) then
            Say("请输入有效的正整数物品 ID 和数量。")
            return
        end
        AddItem(id, limit)
        idInput:SetText("")
        limitInput:SetText("")
        idInput:ClearFocus()
        limitInput:ClearFocus()
    end
    add:SetScript("OnClick", AddFromInputs)
    limitInput:SetScript("OnEnterPressed", AddFromInputs)

    delete:SetScript("OnClick", function()
        if not selected then return end
        local row = selected
        SelectRow(nil)
        row.quantity:ClearFocus()
        row:Hide()
        rowsByID[row.itemID] = nil
        for index, activeRow in ipairs(rows) do
            if activeRow == row then
                table.remove(rows, index)
                break
            end
        end
        spareRows[#spareRows + 1] = row
        LayoutRows()
    end)

    loadSavedRules = function()
        local ids = {}
        for id in pairs(rules) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do InsertRow(id, rules[id]) end
        exitCheck:SetChecked(exitOnPurchase)
        LayoutRows()
    end
    loadSavedRules()

    stateText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    stateText:SetPoint("BOTTOMLEFT", 16, 57)
    local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    save:SetSize(112, 24)
    save:SetPoint("BOTTOMLEFT", 16, 18)
    save:SetText("保存购物清单")
    save:SetScript("OnClick", function()
        local draft = {}
        for _, row in ipairs(rows) do
            local limit = tonumber(row.quantity:GetText())
            if not Number(limit, 1) then
                Say("物品 " .. row.itemID .. " 的数量必须为有效的正整数。")
                return
            end
            draft[row.itemID] = limit
            row.quantity:ClearFocus()
        end
        Stop()
        rules, wowDetectorDB.autoShop = draft, draft
        exitOnPurchase = SingleRuleID(draft) ~= nil and not not exitCheck:GetChecked()
        wowDetectorDB.autoShopExitOnPurchase = exitOnPurchase
        exitCheck:SetChecked(exitOnPurchase)
        Say("购物清单已保存。")
    end)
    local start = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    start:SetSize(112, 24)
    start:SetPoint("LEFT", save, "RIGHT", 10, 0)
    start:SetText("开启购物模式")
    start:SetScript("OnClick", StartManual)
    local stop = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    stop:SetSize(112, 24)
    stop:SetPoint("LEFT", start, "RIGHT", 10, 0)
    stop:SetText("停止购物模式")
    stop:SetScript("OnClick", Stop)
    RefreshStatus()
    return panel
end

WoWTools.modules.auto_shop = {
    IsEnabled = function() return mode ~= nil end,
    IsShown = function() return false end,
    Show = StartManual,
    Hide = Stop,
    Toggle = function() if mode then Stop() else StartManual() end end,
    BuildSettings = BuildSettings,
}

SLASH_WOWTOOLSAUTOSHOP1 = "/autoshop"
SlashCmdList.WOWTOOLSAUTOSHOP = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$")
    if command == "on" then StartManual()
    elseif command == "prepare" then StartScripted()
    elseif command == "off" or (command == "cancel" and mode == "script") then Stop()
    elseif command == "finish" then
        if not session or session.bought then return end
        if AwaitingExitReceipt(GetTime()) then
            session.finishing = true
            CloseStore()
        else
            Stop()
        end
    elseif command == "close" then
        if session and not session.bought then CloseStore() end
    elseif command == "buy" then
        local now = GetTime()
        if session and not session.bought and not session.finishing and not InCombatLockdown() then
            canBuy = true
            if not merchantOpen then
                -- Authorization expires if this interaction never opens a merchant.
                selectedGossip, buyUntil = false, now + 4
                if GossipFrame and GossipFrame:IsShown() then OpenVendorOption() end
            end
        end
    end
end
