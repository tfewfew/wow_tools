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
local SALE_INTERVAL, RESCAN_DELAY, MAX_ROUNDS = 0.05, 0.5, 3
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

local function AddCursorItem()
    if not items or not settings or not settings:IsShown() or type(GetCursorInfo) ~= "function" then return false end
    local ok, kind, id = pcall(GetCursorInfo)
    if not ok or not Readable(kind) or not ValidID(id) then return false end
    if kind ~= "item" then return false end
    local added = AddID(id)
    selectedID = id
    -- Return the dragged stack to its bag; only its ID belongs in the sale list.
    if type(ClearCursor) == "function" then pcall(ClearCursor) end
    status:SetText(added and "已添加拖入物品；名称未缓存时会自动加载。" or "该物品已在列表中。")
    RefreshList()
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
    hint:SetText("可输入物品 ID，或把背包物品拖入下方列表。")
    scroll = CreateFrame("ScrollFrame", "WoWToolsSellFishScroll", settings, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -98)
    scroll:SetSize(354, 240)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(350, 240)
    scroll:SetScrollChild(content)
    for _, target in ipairs({scroll, content}) do
        target:EnableMouse(true)
        target:SetScript("OnReceiveDrag", AddCursorItem)
        target:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then AddCursorItem() end
        end)
    end
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
            row:SetScript("OnReceiveDrag", AddCursorItem)
            row:SetScript("OnClick", function(self)
                if AddCursorItem() then return end
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
                        queue[#queue + 1] = {bag = bag, slot = slot, data = data}
                        units = units + data.count
                    end
                end
            end
            summary[#summary + 1] = bag .. ":" .. found .. "/" .. count
        end
    end
    return queue, matched, unavailable, unknown, slots, units, table.concat(summary, "，")
end
local function LoadRound(currentSale)
    local queue, matched, unavailable, unknown, slots, units, summary = ScanBags()
    if unknown > 0 then
        StopSale("扫描未完成：" .. unknown .. " 处背包数据不可读，已停止出售。背包匹配组数/格数：" .. summary)
        return false
    end
    Say("扫描完成：5 个随身背包、" .. slots .. " 格，清单匹配 " .. matched .. " 组，可出售 "
        .. #queue .. " 组（" .. units .. " 个物品），不可售 " .. unavailable .. " 组。背包匹配组数/格数：" .. summary)
    if #queue == 0 then
        StopSale("完成：扫描到可出售物品为 0；已尝试 " .. currentSale.round .. " 轮。")
        return false
    end
    if currentSale.round >= MAX_ROUNDS then
        StopSale("已尝试 3 轮，扫描仍有 " .. #queue .. " 组可出售物品，本次结束。")
        return false
    end
    currentSale.round = currentSale.round + 1
    currentSale.queue, currentSale.index, currentSale.elapsed = queue, 1, SALE_INTERVAL
    currentSale.rescan = false
    Say("开始第 " .. currentSale.round .. "/" .. MAX_ROUNDS .. " 轮，首组立即发送，随后每隔 50 毫秒尝试发送一组，不等待出售回执。")
    return true
end
local function SaleTick(_, elapsed)
    local currentSale = sale
    if not currentSale then return end
    if not MerchantReady() then StopSale("商店关闭、切页或当前无法出售，已停止。"); return end
    currentSale.elapsed = currentSale.elapsed + elapsed
    if currentSale.rescan then
        if currentSale.elapsed >= RESCAN_DELAY and LoadRound(currentSale) then SaleTick(nil, 0) end
        return
    end
    if currentSale.elapsed < SALE_INTERVAL then return end
    -- Never catch up with multiple sends in one frame after a delayed update.
    currentSale.elapsed = 0
    local entry = currentSale.queue[currentSale.index]
    local current, readable = Snapshot(entry.bag, entry.slot)
    if not readable then
        StopSale("待售物品数据不可读，已停止出售。")
        return
    end
    -- Changed/locked entries wait for the next round's fresh scan, never a local retry.
    if SameStack(current, entry.data) and FindID(entry.data.id)
        and current.noValue ~= true and current.noValue ~= 1
        and (current.locked == false or current.locked == 0) then
        pcall(SellBagItem, entry.bag, entry.slot)
        if sale ~= currentSale then return end
    end
    currentSale.index = currentSale.index + 1
    if currentSale.index > #currentSale.queue then
        currentSale.rescan, currentSale.elapsed = true, 0
    end
end
local function StartSale()
    if sale then return end
    if not MerchantReady() then Say("请在商店购买页、非战斗且鼠标未拿取物品时使用。"); return end
    if not items or #items == 0 then Say("清单为空，请右键按钮添加物品 ID。"); return end
    sale = {round = 0, elapsed = 0}
    if not LoadRound(sale) then return end
    merchantButton:SetText("出售中…")
    merchantButton:Disable()
    eventFrame:SetScript("OnUpdate", SaleTick)
    SaleTick(eventFrame, 0)
end
local function EnsureMerchantButton()
    if merchantButton or not MerchantFrame then return end
    merchantButton = CreateFrame("Button", "WoWToolsSellFishButton", MerchantFrame, "UIPanelButtonTemplate")
    merchantButton:SetSize(78, 24)
    if MerchantFrameTab1 then
        merchantButton:SetPoint("BOTTOMLEFT", MerchantFrameTab1, "TOPLEFT", 0, 0)
    else
        merchantButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 16, 0)
    end
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
