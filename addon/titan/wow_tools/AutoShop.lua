-- Automatic purchases run only in an explicitly activated shopping visit.
local mode, visit, canBuy, opened, selectedGossip, merchantOpen
local rules, pending, receipt, skipped = {}, nil, nil, {}
local exitOnPurchase = false
local menuReadyAt, updateAt = 0, 0
local stateText, editor
local events = CreateFrame("Frame")
local signal = CreateFrame("Frame", nil, UIParent)
signal:SetSize(16, 16)
signal:SetPoint("CENTER", WoWTools.detectorAnchor, "CENTER")
signal:SetFrameStrata("TOOLTIP")
signal:EnableMouse(false)
local main = signal:CreateTexture(nil, "OVERLAY")
main:SetAllPoints(signal)
local signature = signal:CreateTexture(nil, "OVERLAY")
signature:SetSize(16, 16)
signature:SetPoint("CENTER", signal, "CENTER", 32, 0)
signature:SetColorTexture(183/255, 96/255, 152/255, 1)
signal:Hide()

-- The PC operator waits for the next visit to be due before sending the interaction key.
local visitColors = {
    ready = {107, 29, 193},
    busy = {125, 202, 57},
    cooldown = {44, 161, 230},
    reopen = {233, 139, 45},
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

local function ParseRules(text)
    local draft = {}
    for line in text:gmatch("[^\r\n]+") do
        if line:match("%S") then
            local id, limit = line:match("^%s*(%d+)%s+(%d+)%s*$")
            id, limit = tonumber(id), tonumber(limit)
            if not Number(id, 1) or not Number(limit, 1) or draft[id] then return end
            draft[id] = limit
        end
    end
    return draft
end

local function Say(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("wow_tools 购物：" .. text) end
end

local function RefreshStatus()
    if visit then
        local _, physicalHeight = GetPhysicalScreenSize()
        local ratio = physicalHeight and physicalHeight > 0 and UIParent:GetHeight() / physicalHeight or 1
        signal:SetSize(16 * ratio, 16 * ratio)
        signature:SetSize(16 * ratio, 16 * ratio)
        signature:ClearAllPoints()
        signature:SetPoint("CENTER", signal, "CENTER", 32 * ratio, 0)
        local color = visitColors[visit.phase]
        main:SetColorTexture(color[1]/255, color[2]/255, color[3]/255, 1)
        signal:Show()
    else
        signal:Hide()
    end
    if stateText then
        local text = "自动购物模式已关闭"
        if mode == "manual" then text = "自动购物模式已开启"
        elseif visit then
            if visit.phase == "bought" then text = "已买到，等待 wowAuto 下线"
            elseif visit.phase == "cooldown" then text = "商店已关闭，等待下次访问"
            else text = "wowAuto 正在访问商人" end
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
    pending, canBuy, skipped = nil, false, {}
    if not visit then
        opened = false
        events:SetScript("OnUpdate", nil)
    end
    if popup then popup:Hide() end
end

local function Stop()
    local closeMerchant = visit and opened
    mode, visit, selectedGossip = nil, nil, false
    FinishPurchases()
    RefreshStatus()
    if closeMerchant and MerchantFrame and MerchantFrame:IsShown() then CloseMerchant() end
end

local function MarkBought(transaction)
    local closeMerchant = opened
    receipt = nil
    FinishPurchases()
    opened = false
    visit.phase = "bought"
    visit.closeAt, visit.openTimeout, visit.reopenAt = nil, nil, nil
    events:SetScript("OnUpdate", nil)
    RefreshStatus()
    Say(transaction.link .. " 已买到，等待 wowAuto 下线。")
    if closeMerchant and MerchantFrame and MerchantFrame:IsShown() then CloseMerchant() end
end

local function SampleDelaySeconds(baseMs, jitterMs)
    if jitterMs == 0 then return baseMs / 1000 end
    local lower = math.max(1, baseMs - jitterMs)
    local upper = baseMs + jitterMs
    -- The integer-argument form of math.random is limited to signed 32-bit bounds.
    local sampled = lower + math.floor(math.random() * (upper - lower + 1))
    return math.min(sampled, upper) / 1000
end

local function WaitToReopen(now)
    FinishPurchases()
    opened = false
    visit.closeAt, visit.openTimeout = nil, nil
    visit.phase, visit.reopenAt = "cooldown", now + SampleDelaySeconds(visit.closedWaitMs, visit.jitterMs)
    RefreshStatus()
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
    if visit and visit.exitItemID == id then transaction.exitVisit = visit end
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

local function Update(now)
    -- A submitted purchase can reach the bags after the merchant window closes.
    local awaitingExitReceipt = visit and receipt and receipt.exitVisit == visit and now < receipt.expires
    if awaitingExitReceipt and now >= updateAt then
        updateAt = now + 0.05
        local counts = CountBags()
        if counts and (counts[receipt.id] or 0) > receipt.count then
            MarkBought(receipt)
            return
        end
    end
    if visit then
        if now >= visit.deadline and not awaitingExitReceipt then Stop(); return end
        if visit.closeAt and (now >= visit.closeAt or now >= visit.deadline) then
            visit.closeAt = nil
            FinishPurchases()
            CloseMerchant()
            return
        end
        if visit.openTimeout and now >= visit.openTimeout then WaitToReopen(now); return end
        if visit.reopenAt and now >= visit.reopenAt and not awaitingExitReceipt then
            visit.phase, visit.reopenAt = "reopen", nil
            RefreshStatus()
        end
    end
    if awaitingExitReceipt or not opened or not canBuy or now < menuReadyAt or now < updateAt then return end
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

local function PrepareVisit(leaseMs, closedWaitMs, openHoldMs, jitterMs)
    if visit and visit.phase ~= "reopen" and visit.phase ~= "bought" then return end
    Stop()
    if not next(rules) or InCombatLockdown() or UnitIsDeadOrGhost("player") or not UnitExists("target") or UnitIsPlayer("target") then return end
    WoWTools.ActivateDetector("auto_shop")
    local now = GetTime()
    mode = "script"
    visit = { phase = "ready", deadline = now + leaseMs / 1000, openTimeout = now + 30,
        closedWaitMs = closedWaitMs, openHoldMs = openHoldMs, jitterMs = jitterMs,
        exitItemID = exitOnPurchase and SingleRuleID(rules) }
    events:SetScript("OnUpdate", Tick)
    if MerchantFrame and MerchantFrame:IsShown() then
        -- An existing window must close and finish the full wait before the next interaction.
        opened, merchantOpen = true, true
        visit.phase, visit.openTimeout = "busy", nil
        visit.closeAt = now + SampleDelaySeconds(visit.openHoldMs, visit.jitterMs)
    end
    RefreshStatus()
end

local function OpenVendorOption()
    if not visit or selectedGossip or not visit.openTimeout or GetTime() >= math.min(visit.openTimeout, visit.deadline) then return end
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
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        RefreshStatus()
    elseif event == "MERCHANT_SHOW" then
        if mode and not merchantOpen and not (visit and visit.phase == "bought") then
            local now = GetTime()
            opened, menuReadyAt, updateAt = true, now + 0.05, now
            if visit then
                visit.openTimeout, visit.reopenAt = nil, nil
                visit.closeAt = now + SampleDelaySeconds(visit.openHoldMs, visit.jitterMs)
                if visit.phase == "cooldown" or visit.phase == "reopen" then
                    visit.phase = "busy"
                    RefreshStatus()
                end
            else
                canBuy = true
            end
            events:SetScript("OnUpdate", Tick)
        end
        merchantOpen = true
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        if opened then
            if visit then WaitToReopen(GetTime())
            else FinishPurchases() end
        end
    elseif event == "GOSSIP_SHOW" then
        OpenVendorOption()
    elseif event == "PLAYER_REGEN_DISABLED" and visit then
        if opened then
            FinishPurchases()
            visit.closeAt = nil
            CloseMerchant()
        elseif visit.openTimeout then
            WaitToReopen(GetTime())
        end
    else
        Stop()
    end
end)

local function BuildSettings(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOPLEFT", 16, -18)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -18)
    hint:SetJustifyH("LEFT")
    hint:SetText("每行输入两个数字：物品 ID  背包上限。开启模式后，打开商店会补货并确认购买。")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -54)
    scroll:SetPoint("BOTTOMRIGHT", -40, 124)
    editor = CreateFrame("EditBox", nil, scroll)
    editor:SetMultiLine(true)
    editor:SetAutoFocus(false)
    editor:SetFontObject("ChatFontNormal")
    editor:SetSize(400, 120)
    editor:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function SizeEditor()
        local _, fontHeight = editor:GetFont()
        local lines = math.max(1, editor:GetNumLines())
        editor:SetHeight(math.max(scroll:GetHeight(), lines * (fontHeight + editor:GetSpacing()) + 20))
    end
    local exitCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    exitCheck:SetSize(24, 24)
    exitCheck:SetPoint("BOTTOMLEFT", 12, 82)
    exitCheck.Text:SetText("买到后下线并关闭游戏（仅限 wowAuto 单商品任务）")
    exitCheck:SetChecked(exitOnPurchase)
    local function RefreshExitCheck()
        local draft = ParseRules(editor:GetText())
        exitCheck:SetEnabled(draft ~= nil and SingleRuleID(draft) ~= nil)
    end
    editor:SetScript("OnTextChanged", function()
        SizeEditor()
        RefreshExitCheck()
    end)
    scroll:SetScript("OnSizeChanged", function(self, width)
        editor:SetWidth(math.max(1, width))
        SizeEditor()
    end)
    scroll:SetScrollChild(editor)
    local values, ids = {}, {}
    for id in pairs(rules) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do values[#values + 1] = id .. "  " .. rules[id] end
    editor:SetText(table.concat(values, "\n"))
    RefreshExitCheck()

    stateText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    stateText:SetPoint("BOTTOMLEFT", 16, 57)
    local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    save:SetSize(112, 24)
    save:SetPoint("BOTTOMLEFT", 16, 18)
    save:SetText("保存购物清单")
    save:SetScript("OnClick", function()
        local draft = ParseRules(editor:GetText())
        if not draft then
            Say("每行填写唯一的物品 ID 和正整数上限。")
            return
        end
        Stop()
        rules, wowDetectorDB.autoShop = draft, draft
        exitOnPurchase = SingleRuleID(draft) ~= nil and not not exitCheck:GetChecked()
        wowDetectorDB.autoShopExitOnPurchase = exitOnPurchase
        exitCheck:SetChecked(exitOnPurchase)
        editor:ClearFocus()
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
    elseif command == "off" or (command == "cancel" and mode == "script") then Stop()
    elseif command == "buy" then
        local now = GetTime()
        if visit and visit.phase == "ready" and now < visit.deadline
            and (not visit.closeAt or now < visit.closeAt) and (not visit.openTimeout or now < visit.openTimeout) then
            visit.phase, canBuy = "busy", true
            if not opened then visit.openTimeout = now + 4 end
            RefreshStatus()
        end
    else
        local leaseMs, closedWaitMs, openHoldMs, jitterMs = command:match("^preparems (%d+) (%d+) (%d+) (%d+)$")
        leaseMs, closedWaitMs, openHoldMs, jitterMs = tonumber(leaseMs), tonumber(closedWaitMs), tonumber(openHoldMs), tonumber(jitterMs)
        local maxMs = 2147483647000
        if leaseMs and leaseMs >= 1 and leaseMs <= maxMs
            and closedWaitMs and closedWaitMs >= 1 and closedWaitMs <= maxMs
            and openHoldMs and openHoldMs >= 1 and openHoldMs <= maxMs
            and jitterMs and jitterMs >= 0 and jitterMs <= maxMs then
            PrepareVisit(leaseMs, closedWaitMs, openHoldMs, jitterMs)
        end
    end
end
