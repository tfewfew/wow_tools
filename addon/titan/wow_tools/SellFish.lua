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
local SALE_INTERVAL, SALE_BATCH_SIZE, MAX_PENDING_SALES, CONFIRM_TIMEOUT = 0.05, 5, 20, 1.5
local RESCAN_INTERVAL, SCAN_READ_TIMEOUT = 0.1, 5
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
local function StopSale(message)
    sale = nil
    eventFrame:SetScript("OnUpdate", nil)
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
local function StackKey(bag, slot, data)
    local identity = data.guid or (bag .. ":" .. slot)
    return identity .. ":" .. data.id .. ":" .. data.count .. ":" .. (data.link or "")
end
local function SkipStack(currentSale, bag, slot, data)
    local key = StackKey(bag, slot, data)
    if currentSale.skippedStacks[key] then return end
    currentSale.skippedStacks[key] = true
    currentSale.skipped = currentSale.skipped + 1
end
local function ScanBags(currentSale)
    local allowed, queue, summary = {}, {}, {}
    local remaining, unknown = 0, 0
    for _, id in ipairs(items or {}) do allowed[id] = true end
    -- Always inspect backpack + four carried bags; a missing/stale global must not
    -- silently restrict sales to the backpack. Index 5 is carried only when exposed.
    local lastBag = NUM_BAG_SLOTS
    if not Readable(lastBag) or type(lastBag) ~= "number" or lastBag ~= math.floor(lastBag)
        or lastBag < 4 or lastBag > 5 then lastBag = 4 end
    for bag = 0, lastBag do
        local count, matched = BagSlotCount(bag), 0
        if not Readable(count) or type(count) ~= "number" or count < 0 or count > 1000
            or count ~= math.floor(count) then
            unknown = unknown + 1
            summary[#summary + 1] = bag .. ":?"
        else
            for slot = count, 1, -1 do
                local data, readable = Snapshot(bag, slot)
                if not readable then
                    unknown = unknown + 1
                elseif data and allowed[data.id] then
                    remaining, matched = remaining + 1, matched + 1
                    local key = StackKey(bag, slot, data)
                    if not currentSale.skippedStacks[key] then
                        if (data.locked == false or data.locked == 0) and data.noValue ~= true and data.noValue ~= 1 then
                            queue[#queue + 1] = {bag = bag, slot = slot, data = data}
                        else
                            SkipStack(currentSale, bag, slot, data)
                        end
                    end
                end
            end
            summary[#summary + 1] = bag .. ":" .. matched .. "/" .. count
        end
    end
    currentSale.remaining, currentSale.unknown = remaining, unknown
    currentSale.scanSummary = table.concat(summary, "，")
    return queue
end
local function FinishOrRescan(currentSale, delta)
    currentSale.rescanWait = currentSale.rescanWait + delta
    if currentSale.rescanWait < RESCAN_INTERVAL then return end
    local waited = currentSale.rescanWait
    currentSale.rescanWait = 0
    local queue = ScanBags(currentSale)
    if #queue > 0 then
        currentSale.queue, currentSale.index = queue, 1
        currentSale.emptyScans, currentSale.unreadWait = 0, 0
        return
    end
    if currentSale.unknown > 0 then
        currentSale.emptyScans = 0
        currentSale.unreadWait = currentSale.unreadWait + waited
        if currentSale.unreadWait < SCAN_READ_TIMEOUT then return end
        StopSale("扫描未完成：已出售 " .. currentSale.sold .. " 组；仍有 " .. currentSale.unknown
            .. " 处数据不可读，请稍后重试。背包匹配组数/格数：" .. currentSale.scanSummary)
        return
    end
    currentSale.emptyScans = currentSale.emptyScans + 1
    if currentSale.emptyScans < 2 then return end
    local result = currentSale.remaining == 0 and "完成：" or "结束："
    StopSale(result .. "已出售 " .. currentSale.sold .. " 组，跳过 / 未确认 " .. currentSale.skipped
        .. " 组；复查清单剩余 " .. currentSale.remaining .. " 组。背包匹配组数/格数：" .. currentSale.scanSummary)
end
local function SaleTick(_, elapsed)
    local currentSale = sale
    if not currentSale then return end
    if not MerchantReady() then StopSale("出售已停止：商店关闭、切页或当前无法出售。"); return end
    currentSale.elapsed = currentSale.elapsed + elapsed
    if currentSale.elapsed < SALE_INTERVAL then return end
    local delta = currentSale.elapsed
    currentSale.elapsed = 0
    for index = #currentSale.pending, 1, -1 do
        local pending = currentSale.pending[index]
        local current, readable = Snapshot(pending.bag, pending.slot)
        if readable and (not current or current.id ~= pending.data.id or current.count < pending.data.count
            or (current.guid and pending.data.guid and current.guid ~= pending.data.guid)) then
            currentSale.sold = currentSale.sold + 1
            table.remove(currentSale.pending, index)
        else
            pending.wait = pending.wait + delta
            if pending.wait >= CONFIRM_TIMEOUT then
                SkipStack(currentSale, pending.bag, pending.slot, pending.data)
                table.remove(currentSale.pending, index)
            end
        end
    end
    -- 20 is only the in-flight bound. Draining one scan must never end the whole sale.
    for _ = 1, SALE_BATCH_SIZE do
        if #currentSale.pending >= MAX_PENDING_SALES then break end
        local entry = currentSale.queue[currentSale.index]
        if not entry then break end
        if not MerchantReady() then StopSale("出售已停止：商店关闭、切页或当前无法出售。"); return end
        currentSale.index = currentSale.index + 1
        local current = Snapshot(entry.bag, entry.slot)
        if not SameStack(current, entry.data) or (current.locked ~= false and current.locked ~= 0)
            or current.noValue == true or current.noValue == 1 or not FindID(current.id) then
            SkipStack(currentSale, entry.bag, entry.slot, entry.data)
        else
            local pending = {bag = entry.bag, slot = entry.slot, data = current, wait = 0}
            local ok, result = pcall(SellBagItem, entry.bag, entry.slot)
            if sale ~= currentSale then return end
            if not ok or not Readable(result) or result == false then
                SkipStack(currentSale, entry.bag, entry.slot, current)
            else
                currentSale.pending[#currentSale.pending + 1] = pending
            end
        end
    end
    if not currentSale.queue[currentSale.index] and #currentSale.pending == 0 then
        FinishOrRescan(currentSale, delta)
    end
end
local function StartSale()
    if sale then return end
    if not MerchantReady() then Say("请在商店购买页、非战斗且鼠标未拿取物品时使用。"); return end
    if not items or #items == 0 then Say("清单为空，请右键按钮添加物品 ID。"); return end
    local nextSale = {index = 1, sold = 0, skipped = 0, elapsed = 0, pending = {},
        skippedStacks = {}, rescanWait = 0, emptyScans = 0, unreadWait = 0}
    nextSale.queue = ScanBags(nextSale)
    if #nextSale.queue == 0 and nextSale.unknown == 0 then
        Say("没有可出售的清单物品；清单匹配 " .. nextSale.remaining
            .. " 组（锁定或不可出售会跳过）。背包匹配组数/格数：" .. nextSale.scanSummary)
        return
    end
    sale = nextSale
    Say("开始：本次扫描可出售 " .. #sale.queue .. " 组，无总时长 / 总组数限制。背包匹配组数/格数：" .. sale.scanSummary)
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
    elseif ValidID(id) and FindID(id) and settings and settings:IsShown() then
        if Readable(success) then
            if success == false then failed[id] = true elseif success == true then failed[id] = nil end
        end
        RefreshList()
    end
end)
SLASH_WOWTOOLSSELLFISH1 = "/sellfish"
SlashCmdList.WOWTOOLSSELLFISH = ToggleSettings
