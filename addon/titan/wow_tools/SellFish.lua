-- Titan 38002: checked against Blizzard export 0f73fd6b0e12bf8de89a8084ebd81aade0afe8d7.
-- Independent merchant module; prefer C_Container, retain legacy bag APIs.
local function BagSlotCount(bag)
    local fn = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    if type(fn) ~= "function" then return nil end
    local ok, count = pcall(fn, bag)
    if ok then return count end
end
local function ReadBagItem(bag, slot)
    local fn = C_Container and C_Container.GetContainerItemInfo or GetContainerItemInfo
    if type(fn) ~= "function" then return false end
    local values = {pcall(fn, bag, slot)}
    if not values[1] then return false end
    local data = values[2]
    if issecretvalue and issecretvalue(data) then return false end
    if data == nil then return nil end
    if type(data) == "table" then
        return {id = data.itemID, count = data.stackCount, locked = data.isLocked,
            noValue = data.hasNoValue, link = data.hyperlink}
    end
    local id = values[11]
    if issecretvalue and issecretvalue(id) then return false end
    if id == nil and type(GetContainerItemID) == "function" then
        local ok, value = pcall(GetContainerItemID, bag, slot)
        if ok then id = value end
    end
    return {id = id, count = values[3], locked = values[4], noValue = values[10], link = values[8]}
end
local function SellBagItem(bag, slot)
    local fn = C_Container and C_Container.UseContainerItem or UseContainerItem
    if type(fn) ~= "function" then return false end
    return fn(bag, slot)
end

local eventFrame = CreateFrame("Frame")
local items, selectedID, settings, input, status, scroll, content, deleteButton
local rows, requested, failed = {}, {}, {}
local merchantOpen, merchantButton, sale = false, nil, nil
local SALE_INTERVAL, RETRY_INTERVAL, RECEIPT_TIMEOUT, LOCK_TIMEOUT, MAX_ATTEMPTS = 0.05, 0.25, 5, 5, 3
local BATCH_SIZE = 5
local saleEvents = {"BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "UI_ERROR_MESSAGE"}
local RefreshList

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function ValidID(value)
    return Readable(value) and type(value) == "number" and value >= 1
        and value <= 2147483647 and value == math.floor(value)
end
local function Say(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("wow_tools 卖鱼：" .. message) end
end
local function ItemName(id)
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    if type(getter) == "function" then
        local ok, name = pcall(getter, id)
        if ok and Readable(name) and type(name) == "string" and name ~= "" then return name end
    end
end
-- Optional cached vendor price enables exact aggregate receipts for small batches.
-- Missing/secret prices fall back to one item at a time without blocking the scan.
local function SaleProceeds(data)
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    if type(getter) ~= "function" then return nil end
    local values = {pcall(getter, data.link or data.id)}
    local price = values[12] -- GetItemInfo's eleventh return is the per-item sell price.
    if not values[1] or not Readable(price) or type(price) ~= "number" or price <= 0
        or price ~= math.floor(price) then return nil end
    local total = price * data.count
    if total > 0 and total <= 9007199254740991 and total == math.floor(total) then return total end
end
local function RequestName(id)
    if requested[id] then return end
    requested[id] = true
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end
local function FindID(id)
    for index, value in ipairs(items or {}) do
        if value == id then return index end
    end
end
local function AddID(id)
    if not items or not ValidID(id) or FindID(id) then return false end
    items[#items + 1] = id
    requested[id], failed[id] = nil, nil
    return true
end

local function CreateSettings()
    if settings then return end
    settings = CreateFrame("Frame", "WoWToolsSellFishSettings", UIParent, "BasicFrameTemplateWithInset")
    settings:SetSize(420, 410)
    settings:SetPoint("CENTER")
    settings:SetFrameStrata("DIALOG")
    settings:SetClampedToScreen(true)
    settings:SetMovable(true)
    settings:EnableMouse(true)
    settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart", function(self) self:StartMoving() end)
    settings:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    settings.TitleText:SetText("wow_tools - 一键卖鱼设置")
    settings:Hide()
    UISpecialFrames[#UISpecialFrames + 1] = "WoWToolsSellFishSettings"

    local label = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 18, -40)
    label:SetText("物品 ID")
    input = CreateFrame("EditBox", "WoWToolsSellFishIdInput", settings, "InputBoxTemplate")
    input:SetSize(145, 24)
    input:SetPoint("TOPLEFT", 82, -34)
    input:SetAutoFocus(false)
    input:SetNumeric(true)
    input:SetMaxLetters(10)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local add = CreateFrame("Button", "WoWToolsSellFishAdd", settings, "UIPanelButtonTemplate")
    add:SetSize(74, 24)
    add:SetPoint("LEFT", input, "RIGHT", 12, 0)
    add:SetText("添加")
    local function AddItem()
        if not items then return end
        local text = input:GetText() or ""
        local id = text:match("^%d+$") and tonumber(text)
        if not ValidID(id) then status:SetText("请输入有效的正整数物品 ID。"); return end
        if not AddID(id) then status:SetText("该物品已在列表中。"); return end
        selectedID = id
        input:SetText("")
        input:ClearFocus()
        status:SetText("已添加；名称未缓存时会自动加载。")
        RefreshList()
    end
    add:SetScript("OnClick", AddItem)
    input:SetScript("OnEnterPressed", AddItem)

    local hint = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 18, -72)
    hint:SetText("左键商店按钮出售清单物品；右键打开此设置。")
    scroll = CreateFrame("ScrollFrame", "WoWToolsSellFishScroll", settings, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -98)
    scroll:SetSize(354, 240)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(350, 240)
    scroll:SetScrollChild(content)
    deleteButton = CreateFrame("Button", "WoWToolsSellFishDelete", settings, "UIPanelButtonTemplate")
    deleteButton:SetSize(100, 24)
    deleteButton:SetPoint("BOTTOMLEFT", 18, 38)
    deleteButton:SetText("删除选中项")
    deleteButton:SetScript("OnClick", function()
        local index = selectedID and FindID(selectedID)
        if not index then return end
        table.remove(items, index)
        selectedID = nil
        status:SetText("已删除。")
        RefreshList()
    end)
    local wintergrasp = CreateFrame("Button", "WoWToolsSellFishWintergrasp", settings, "UIPanelButtonTemplate")
    wintergrasp:SetSize(116, 24)
    wintergrasp:SetPoint("BOTTOMRIGHT", -18, 38)
    wintergrasp:SetText("冬拥湖三杰")
    wintergrasp:SetScript("OnClick", function()
        if not items then return end
        local added = 0
        for _, id in ipairs({41813, 41806, 41809}) do
            if AddID(id) then
                added = added + 1
                selectedID = id
            end
        end
        status:SetText("冬拥湖三杰：新增 " .. added .. " 项，跳过 " .. (3 - added) .. " 项重复物品。")
        RefreshList()
    end)
    status = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 18, 14)
    status:SetWidth(384)
    status:SetJustifyH("LEFT")
    settings:SetScript("OnShow", function()
        eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        status:SetText("仅出售清单中的物品，设置自动保存。")
        RefreshList()
    end)
    settings:SetScript("OnHide", function()
        input:ClearFocus()
        eventFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        eventFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    end)
end

RefreshList = function()
    if not settings or not items then return end
    for index, id in ipairs(items) do
        local row = rows[index]
        if not row then
            row = CreateFrame("Button", "WoWToolsSellFishRow" .. index, content)
            row:SetSize(350, 26)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 26)
            row.background = row:CreateTexture(nil, "BACKGROUND")
            row.background:SetAllPoints()
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetWidth(338)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnClick", function(self)
                selectedID = self.itemID
                RefreshList()
            end)
            rows[index] = row
        end
        row.itemID = id
        local name = not failed[id] and ItemName(id)
        if not name then
            RequestName(id)
            -- Item data can arrive synchronously inside RequestLoadItemDataByID.
            name = not failed[id] and ItemName(id)
        end
        row.label:SetText((name or (failed[id] and "未知物品" or "名称加载中…")) .. "  (ID: " .. id .. ")")
        row.background:SetColorTexture(0.2, 0.45, 0.7, selectedID == id and 0.65 or 0)
        row:Show()
    end
    for index = #items + 1, #rows do rows[index]:Hide() end
    content:SetHeight(math.max(240, #items * 26))
    if selectedID and FindID(selectedID) then deleteButton:Enable() else deleteButton:Disable() end
end

local function ToggleSettings()
    if not items then return end
    CreateSettings()
    if settings:IsShown() then settings:Hide() else settings:Show() end
end
local function MerchantReady()
    if not merchantOpen or not MerchantFrame or not MerchantFrame:IsShown() then return false end
    local tab = MerchantFrame.selectedTab
    if not Readable(tab) or (tab ~= nil and tab ~= 1) then return false end
    if type(InCombatLockdown) == "function" then
        local ok, combat = pcall(InCombatLockdown)
        if not ok or not Readable(combat) or combat ~= false then return false end
    end
    if type(CursorHasItem) == "function" then
        local ok, holding = pcall(CursorHasItem)
        if not ok or not Readable(holding) or holding ~= false then return false end
    end
    return true
end
local function ReadMoney()
    if type(GetMoney) ~= "function" then return nil end
    local ok, value = pcall(GetMoney)
    if ok and Readable(value) and type(value) == "number" and value >= 0 and value <= 9007199254740991 then return value end
end
local function StopSale(message)
    sale = nil
    eventFrame:SetScript("OnUpdate", nil)
    for _, event in ipairs(saleEvents) do eventFrame:UnregisterEvent(event) end
    if merchantButton then merchantButton:SetText("一键卖鱼"); merchantButton:Enable() end
    if message then Say(message) end
end
local function Snapshot(bag, slot)
    local data = ReadBagItem(bag, slot)
    if data == nil then return nil, true end
    if data == false then return nil, false end
    if not ValidID(data.id) or not Readable(data.count) or type(data.count) ~= "number"
        or data.count < 1 or not Readable(data.locked) or not Readable(data.noValue)
        or not Readable(data.link) or (data.link ~= nil and type(data.link) ~= "string") then return nil, false end
    if C_Item and type(C_Item.GetItemGUID) == "function" and ItemLocation
        and type(ItemLocation.CreateFromBagAndSlot) == "function" then
        local ok, guid = pcall(function() return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot)) end)
        if not ok or not Readable(guid) then return nil, false end
        if type(guid) == "string" and guid ~= "" then data.guid = guid end
    end
    return data, true
end
local function SameStack(a, b)
    return a and b and a.id == b.id and a.count == b.count and a.link == b.link
        and (not a.guid or not b.guid or a.guid == b.guid)
end
-- The scan is completed once, before the first sale request.
local function ScanBags()
    local allowed, queue, summary = {}, {}, {}
    local matched, unavailable, unknown, slots, units = 0, 0, 0, 0, 0
    for _, id in ipairs(items or {}) do allowed[id] = true end
    for bag = 0, 4 do
        local count, found = BagSlotCount(bag), 0
        if not Readable(count) or type(count) ~= "number" or count < 0 or count > 1000
            or count ~= math.floor(count) then
            unknown = unknown + 1
            summary[#summary + 1] = bag .. ":?"
        else
            if count == 0 then
                local inventorySlot = C_Container and C_Container.ContainerIDToInventoryID or ContainerIDToInventoryID
                if bag == 0 then
                    unknown = unknown + 1
                elseif type(inventorySlot) == "function" and type(GetInventoryItemID) == "function" then
                    local ok, equipped = pcall(function() return GetInventoryItemID("player", inventorySlot(bag)) end)
                    if not ok or not Readable(equipped) or equipped ~= nil then unknown = unknown + 1 end
                end
            end
            slots = slots + count
            for slot = count, 1, -1 do
                local data, readable = Snapshot(bag, slot)
                if not readable then
                    unknown = unknown + 1
                elseif data and allowed[data.id] then
                    matched, found = matched + 1, found + 1
                    if data.noValue == true or data.noValue == 1 then
                        unavailable = unavailable + 1
                    else
                        queue[#queue + 1] = {bag = bag, slot = slot, data = data, attempts = 0,
                            lockWait = 0, proceeds = SaleProceeds(data)}
                        units = units + data.count
                    end
                end
            end
            summary[#summary + 1] = bag .. ":" .. found .. "/" .. count
        end
    end
    return queue, matched, unavailable, unknown, slots, units, table.concat(summary, "，")
end
local function FailSale(currentSale, reason)
    StopSale("未完成：已出售 " .. currentSale.sold .. "/" .. #currentSale.queue .. " 组，尚有 "
        .. (#currentSale.queue - currentSale.sold) .. " 组未完成；" .. reason)
end
local function ReceiptComplete(pending)
    if pending.expected then
        if pending.money - pending.beforeMoney < pending.expected then return false end
    elseif pending.money <= pending.beforeMoney then
        return false
    end
    for _, updated in pairs(pending.bags) do
        if not updated then return false end
    end
    return true
end
local function SaleTick(_, elapsed)
    local currentSale = sale
    if not currentSale then return end
    if not MerchantReady() then FailSale(currentSale, "商店关闭、切页或当前无法出售。"); return end
    currentSale.elapsed = currentSale.elapsed + elapsed
    if currentSale.elapsed < SALE_INTERVAL then return end
    local delta = currentSale.elapsed
    currentSale.elapsed = 0
    local pending = currentSale.pending
    if pending then
        -- One receipt can cover several requests. Require the full batch's proceeds,
        -- not merely any positive money event. Never inspect a sent slot again.
        if ReceiptComplete(pending) then
            currentSale.sold = currentSale.sold + #pending.entries
            currentSale.index = currentSale.index + #pending.entries
            currentSale.pending = nil
        elseif pending.error and #pending.entries == 1 and pending.money == pending.beforeMoney then
            local entry = pending.entries[1]
            if pending.retryable and entry.attempts < MAX_ATTEMPTS then
                currentSale.pending = nil
                currentSale.retryWait, currentSale.batchLimit = RETRY_INTERVAL, 1
            else
                FailSale(currentSale, pending.error)
                return
            end
        else
            -- An asynchronous batch error cannot identify a failed original slot.
            -- Drain late receipts, but never blindly replay a partially sold batch.
            pending.wait = pending.wait + delta
            if pending.wait >= RECEIPT_TIMEOUT then
                FailSale(currentSale, pending.error or "未收到完整商店售卖回执，已停止，未将本批计为完成。")
            end
            return
        end
    end
    if currentSale.failureReason then FailSale(currentSale, currentSale.failureReason); return end
    if not currentSale.queue[currentSale.index] then
        StopSale("完成：固定清单 " .. #currentSale.queue .. " 组已全部出售（" .. currentSale.units .. " 个物品）。")
        return
    end
    if currentSale.retryWait > 0 then
        currentSale.retryWait = math.max(0, currentSale.retryWait - delta)
        return
    end

    pending = nil
    for offset = 0, currentSale.batchLimit - 1 do
        local entry = currentSale.queue[currentSale.index + offset]
        if not entry or (pending and (not pending.expected or not entry.proceeds)) then break end
        if not MerchantReady() then
            currentSale.failureReason = "商店关闭、切页或当前无法出售。"
            break
        end
        -- Only a pre-send check of an unsent original slot, including within a batch.
        local current, readable = Snapshot(entry.bag, entry.slot)
        if not readable then
            currentSale.failureReason = "待售物品数据不可读，未继续发送。"
            break
        end
        if not SameStack(current, entry.data) or not FindID(entry.data.id) then
            currentSale.failureReason = "待售背包格或清单已变化，请重新点击建立清单。"
            break
        end
        if current.noValue == true or current.noValue == 1 then
            currentSale.failureReason = "清单中的物品当前不可出售。"
            break
        end
        if current.locked ~= false and current.locked ~= 0 then
            entry.lockWait = entry.lockWait + delta
            if entry.lockWait >= LOCK_TIMEOUT then currentSale.failureReason = "待售物品持续锁定，未跳过该组。" end
            break
        end
        if not pending then
            local money = ReadMoney()
            if money == nil then currentSale.failureReason = "无法读取商店金币回执所需数据。"; break end
            pending = {entries = {}, bags = {}, beforeMoney = money, money = money,
                expected = entry.proceeds and 0, wait = 0}
            currentSale.pending = pending
        end
        entry.attempts = entry.attempts + 1
        entry.error, entry.retryable = nil, nil
        local previousBag = pending.bags[entry.bag]
        pending.bags[entry.bag] = false
        pending.entries[#pending.entries + 1] = entry
        if pending.expected then pending.expected = pending.expected + entry.proceeds end
        currentSale.sending = entry -- Errors/events may be synchronous inside the API.
        local ok, result = pcall(SellBagItem, entry.bag, entry.slot)
        currentSale.sending = nil
        if sale ~= currentSale then return end
        if not ok or not Readable(result) or result == false then
            entry.error, entry.retryable = "售卖请求未被接受。", true
        end
        if entry.error then
            -- A positive full-price receipt can arrive before an API error. Keep
            -- this batch pending for its bag event rather than replaying a sale.
            if pending.money > pending.beforeMoney and (not pending.expected
                or pending.money - pending.beforeMoney >= pending.expected) then break end
            table.remove(pending.entries)
            if pending.expected then pending.expected = pending.expected - entry.proceeds end
            if previousBag == nil then pending.bags[entry.bag] = nil
            else pending.bags[entry.bag] = previousBag or pending.bags[entry.bag] end
            if #pending.entries == 0 then currentSale.pending = nil; pending = nil end
            if entry.retryable and entry.attempts < MAX_ATTEMPTS then
                -- Once the merchant is busy, finish the accepted prefix, then
                -- retry this exact entry sequentially for the rest of this run.
                currentSale.retryWait, currentSale.batchLimit = RETRY_INTERVAL, 1
            else
                currentSale.failureReason = entry.error
            end
            break
        end
        if not entry.proceeds then break end -- Unknown price retains the single-item receipt path.
    end
    if not currentSale.pending and currentSale.failureReason then FailSale(currentSale, currentSale.failureReason) end
end
local function StartSale()
    if sale then return end
    if not MerchantReady() then Say("请在商店购买页、非战斗且鼠标未拿取物品时使用。"); return end
    if not items or #items == 0 then Say("清单为空，请右键按钮添加物品 ID。"); return end
    local queue, matched, unavailable, unknown, slots, units, summary = ScanBags()
    if unknown > 0 then
        Say("扫描未完成：" .. unknown .. " 处背包数据不可读，尚未出售任何物品。背包匹配组数/格数：" .. summary)
        return
    end
    Say("扫描完成：5 个随身背包、" .. slots .. " 格，清单匹配 " .. matched .. " 组，可出售 "
        .. #queue .. " 组（" .. units .. " 个物品），不可售 " .. unavailable .. " 组。背包匹配组数/格数：" .. summary)
    if #queue == 0 then Say("没有可出售的清单物品。"); return end
    if ReadMoney() == nil then Say("金币回执数据不可读，尚未开始出售。"); return end
    sale = {queue = queue, index = 1, sold = 0, units = units, elapsed = 0, retryWait = 0, batchLimit = BATCH_SIZE}
    for _, event in ipairs(saleEvents) do eventFrame:RegisterEvent(event) end
    merchantButton:SetText("出售中…")
    merchantButton:Disable()
    eventFrame:SetScript("OnUpdate", SaleTick)
end
local function EnsureMerchantButton()
    if merchantButton or not MerchantFrame then return end
    merchantButton = CreateFrame("Button", "WoWToolsSellFishButton", MerchantFrame, "UIPanelButtonTemplate")
    merchantButton:SetSize(104, 24)
    merchantButton:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, -32)
    merchantButton:SetText("一键卖鱼")
    merchantButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    merchantButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ToggleSettings() elseif button == "LeftButton" then StartSale() end
    end)
    merchantButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("一键卖鱼")
        GameTooltip:AddLine("左键：出售清单中的所有整组物品", 1, 1, 1)
        GameTooltip:AddLine("右键：设置物品清单", 1, 1, 1)
        GameTooltip:Show()
    end)
    merchantButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    merchantButton:SetScript("OnHide", function()
        if sale then StopSale("商店关闭，出售已停止。") end
    end)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:SetScript("OnEvent", function(_, event, id, success)
    if event == "ADDON_LOADED" then
        if id ~= "wow_tools" then return end
        if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
        local previous, seen = wowDetectorDB.sellFishItems, {}
        items = {}
        if type(previous) == "table" then
            for _, value in ipairs(previous) do
                if ValidID(value) and not seen[value] then
                    items[#items + 1], seen[value] = value, true
                end
            end
        end
        wowDetectorDB.sellFishItems = items
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        EnsureMerchantButton()
        if merchantButton then merchantButton:Show() end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        if sale then StopSale("商店关闭，出售已停止。") end
        if merchantButton then merchantButton:Hide() end
    elseif sale and sale.pending and (event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED") then
        if event == "BAG_UPDATE_DELAYED" then
            for bag in pairs(sale.pending.bags) do sale.pending.bags[bag] = true end
        elseif Readable(id) and sale.pending.bags[id] ~= nil then
            sale.pending.bags[id] = true
        end
    elseif sale and sale.pending and event == "PLAYER_MONEY" then
        local money = ReadMoney()
        if money then sale.pending.money = money end
    elseif sale and sale.pending and event == "UI_ERROR_MESSAGE" and Readable(success) and type(success) == "string" then
        local target = sale.sending or sale.pending
        target.error = success
        target.retryable = success == ERR_OBJECT_IS_BUSY or success == ERR_ITEM_LOCKED
            or success == ERR_CANT_DO_THAT_RIGHT_NOW
    elseif ValidID(id) and FindID(id) and settings and settings:IsShown() then
        if Readable(success) then
            if success == false then failed[id] = true elseif success == true then failed[id] = nil end
        end
        RefreshList()
    end
end)
SLASH_WOWTOOLSSELLFISH1 = "/sellfish"
SlashCmdList.WOWTOOLSSELLFISH = ToggleSettings
