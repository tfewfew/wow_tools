-- Forever 1.60.1 / 16001: C_Container and C_Item signatures checked against
-- Blizzard export 943764493e6b16d63ded3ab304150d1f05e58b57. Never inspect secret data.
local function BagSlotCount(bag)
    if not C_Container or type(C_Container.GetContainerNumSlots) ~= "function" then return nil end
    local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
    if ok then return count end
end
local function ReadBagItem(bag, slot)
    if not C_Container or type(C_Container.GetContainerItemInfo) ~= "function" then return false end
    local ok, data = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or (issecretvalue and issecretvalue(data)) then return false end
    if data == nil then return nil end
    if type(data) ~= "table" then return false end
    return {id = data.itemID, count = data.stackCount, locked = data.isLocked,
        noValue = data.hasNoValue, link = data.hyperlink}
end
local function SellBagItem(bag, slot)
    if not C_Container or type(C_Container.UseContainerItem) ~= "function" then return false end
    return C_Container.UseContainerItem(bag, slot)
end

local eventFrame = CreateFrame("Frame")
local items, selectedID, settings, input, status, scroll, content, deleteButton
local rows, requested, failed = {}, {}, {}
local merchantOpen, merchantButton, sale = false, nil, nil
local SALE_INTERVAL, SALE_BATCH_SIZE, MAX_PENDING_SALES, CONFIRM_TIMEOUT = 0.05, 5, 20, 1.5
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
        if FindID(id) then status:SetText("该物品已在列表中。"); return end
        items[#items + 1] = id
        selectedID, requested[id], failed[id] = id, nil, nil
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
        or not Readable(data.link) then return nil, false end
    return data, true
end
local function SameStack(a, b)
    return a and b and a.id == b.id and a.count == b.count and a.link == b.link
end
local function SaleTick(_, elapsed)
    local currentSale = sale
    if not currentSale then return end
    if not MerchantReady() then StopSale("出售已停止：商店关闭、切页或当前无法出售。"); return end
    currentSale.elapsed = currentSale.elapsed + elapsed
    if currentSale.elapsed < SALE_INTERVAL then return end
    local delta = currentSale.elapsed
    currentSale.elapsed = 0
    -- Confirm all in-flight stacks independently; one slow response must not block the queue.
    for index = #currentSale.pending, 1, -1 do
        local pending = currentSale.pending[index]
        local current, readable = Snapshot(pending.bag, pending.slot)
        if readable and (not current or current.id ~= pending.data.id or current.count < pending.data.count) then
            currentSale.sold = currentSale.sold + 1
            table.remove(currentSale.pending, index)
        else
            pending.wait = pending.wait + delta
            if pending.wait >= CONFIRM_TIMEOUT then
                currentSale.skipped = currentSale.skipped + 1
                table.remove(currentSale.pending, index) -- Failed/unconfirmed stacks are never retried.
            end
        end
    end
    -- Bound both per-tick work and outstanding requests instead of waiting after every stack.
    for _ = 1, SALE_BATCH_SIZE do
        if #currentSale.pending >= MAX_PENDING_SALES then break end
        local entry = currentSale.queue[currentSale.index]
        if not entry then break end
        if not MerchantReady() then StopSale("出售已停止：商店关闭、切页或当前无法出售。"); return end
        currentSale.index = currentSale.index + 1
        local current = Snapshot(entry.bag, entry.slot)
        -- Re-read the exact slot immediately before use; never sell a replacement item.
        if not SameStack(current, entry.data) or (current.locked ~= false and current.locked ~= 0)
            or current.noValue == true or current.noValue == 1 or not FindID(current.id) then
            currentSale.skipped = currentSale.skipped + 1
        else
            local pending = {bag = entry.bag, slot = entry.slot, data = current, wait = 0}
            local ok, result = pcall(SellBagItem, entry.bag, entry.slot)
            if sale ~= currentSale then return end -- Merchant close may run inside the API call.
            if not ok or not Readable(result) or result == false then
                currentSale.skipped = currentSale.skipped + 1
            else
                currentSale.pending[#currentSale.pending + 1] = pending
            end
        end
    end
    if not currentSale.queue[currentSale.index] and #currentSale.pending == 0 then
        StopSale("完成：已出售 " .. currentSale.sold .. " 组，跳过 / 未确认 " .. currentSale.skipped .. " 组。")
    end
end
local function StartSale()
    if sale then return end
    if not MerchantReady() then Say("请在商店购买页、非战斗且鼠标未拿取物品时使用。"); return end
    if not items or #items == 0 then Say("清单为空，请右键按钮添加物品 ID。"); return end
    local allowed, queue, skipped = {}, {}, 0
    for _, id in ipairs(items) do allowed[id] = true end
    -- Backpack and carried bags only. Never enumerate bank/equipment slots.
    local lastBag = NUM_BAG_SLOTS
    if not Readable(lastBag) or type(lastBag) ~= "number" or lastBag < 0 or lastBag > 5 then lastBag = 4 end
    for bag = 0, lastBag do
        local count = BagSlotCount(bag)
        if Readable(count) and type(count) == "number" and count >= 0 and count <= 1000 then
            for slot = count, 1, -1 do
                local data = Snapshot(bag, slot)
                if data and allowed[data.id] then
                    if (data.locked == false or data.locked == 0) and data.noValue ~= true and data.noValue ~= 1 then
                        queue[#queue + 1] = {bag = bag, slot = slot, data = data}
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end
    if #queue == 0 then Say("没有可出售的清单物品（锁定或不可出售的物品会跳过）。"); return end
    sale = {queue = queue, index = 1, sold = 0, skipped = skipped, elapsed = 0, pending = {}}
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
