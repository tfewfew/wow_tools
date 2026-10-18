-- Offline UI and merchant simulation. No real game APIs or input are used.
local root = TEST_ROOT or "."
local function Run(flavor, legacy)
    local frames, names, messages, calls, requests = {}, {}, {}, {}, {}
    local bags, catalog = {}, {[101] = "新鲜的美味小鱼", [102] = "新鲜的长嘴泥鳅"}
    local sendEvent, afterUse
    local combat, cursor, mode, failInfo, secretField = false, false, "success", false, nil
    local secret = setmetatable({}, {
        __eq = function() error("Compared a secret") end,
        __tostring = function() error("Printed a secret") end,
        __index = function() error("Indexed a secret") end,
    })
    function issecretvalue(value) return rawequal(value, secret) end
    local function Widget(name, parent)
        local o = {scripts = {}, events = {}, shown = true, enabled = true, text = "", parent = parent}
        function o:SetScript(event, fn) self.scripts[event] = fn end
        function o:RegisterEvent(event) self.events[event] = true end
        function o:UnregisterEvent(event) self.events[event] = nil end
        function o:SetSize(w, h) self.width, self.height = w, h end
        function o:SetHeight(h) self.height = h end
        function o:SetWidth(w) self.width = w end
        function o:SetPoint(...) self.point = {...} end
        function o:SetText(text) self.text = text end
        function o:GetText() return self.text end
        function o:SetNumeric(value) self.numeric = value end
        function o:SetScrollChild(child) self.child = child end
        function o:Show()
            local changed = not self.shown; self.shown = true
            if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function o:Hide()
            local changed = self.shown; self.shown = false
            if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function o:IsShown() return self.shown end
        function o:Enable() self.enabled = true end
        function o:Disable() self.enabled = false end
        function o:CreateFontString() return Widget(nil, self) end
        function o:CreateTexture() return Widget(nil, self) end
        function o:SetColorTexture(...) self.color = {...} end
        for _, method in ipairs({"SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse",
            "RegisterForDrag", "RegisterForClicks", "StartMoving", "StopMovingOrSizing", "SetAutoFocus",
            "SetMaxLetters", "ClearFocus", "SetAllPoints", "SetJustifyH", "SetOwner", "AddLine"}) do
            o[method] = function() end
        end
        if name then names[name] = o end
        return o
    end
    function CreateFrame(_, name, parent, template)
        local o = Widget(name, parent)
        if template == "BasicFrameTemplateWithInset" then o.TitleText = Widget() end
        frames[#frames + 1] = o
        return o
    end
    WoWTools, SlashCmdList, UISpecialFrames = {modules = {}}, {}, {}
    wowDetectorDB = {unrelated = "preserve", sellFishItems = {101, 101, -1, "102", 0, 1.2}}
    UIParent, MerchantFrame, GameTooltip = Widget(), Widget(), Widget()
    MerchantFrame:Hide()
    MerchantFrame.selectedTab = 1
    DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages + 1] = message end}
    NUM_BAG_SLOTS = 4
    function InCombatLockdown() return combat end
    function CursorHasItem() return cursor end
    local function NumSlots(bag) return bag <= 4 and 8 or 100 end
    local function Info(bag, slot)
        if failInfo then error("Unreadable container") end
        local data = bags[bag] and bags[bag][slot]
        if not data then return nil end
        if secretField == "table" then return secret end
        local info = {itemID = data.id, stackCount = data.count or 20, isLocked = data.locked or false,
            hasNoValue = data.noValue or false, hyperlink = "item:" .. data.id}
        if secretField then info[secretField] = secret end
        return info
    end
    local function Use(bag, slot)
        assert(MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1 and not combat and not cursor)
        assert(bag >= 0 and bag <= 4, "Bank slot touched")
        local data = bags[bag][slot]
        calls[#calls + 1] = {id = data.id, bag = bag, slot = slot}
        if mode == "error" then error("API rejected sale") end
        if mode == "false" then return false end
        if mode == "unconfirmed" then return end
        bags[bag][slot] = nil
        if afterUse then afterUse() end
        if mode == "close" then
            MerchantFrame:Hide()
            for _, frame in ipairs(frames) do
                if frame.events.MERCHANT_CLOSED then frame.scripts.OnEvent(frame, "MERCHANT_CLOSED") end
            end
        end
    end
    local function ItemInfo(id) return catalog[id] end
    C_Item = {GetItemInfo = ItemInfo, RequestLoadItemDataByID = function(id)
        requests[id] = true
        if id == 888 then
            catalog[id] = "新鲜的斑点黄尾鱼"
            sendEvent("ITEM_DATA_LOAD_RESULT", id, true)
        end
    end}
    GetItemInfo = nil
    GetContainerNumSlots, GetContainerItemInfo, GetContainerItemID, UseContainerItem = nil, nil, nil, nil
    if legacy then
        C_Container = nil
        GetItemInfo, C_Item = ItemInfo, nil
        GetContainerNumSlots, UseContainerItem = NumSlots, Use
        GetContainerItemInfo = function(bag, slot)
            local info = Info(bag, slot)
            if info == nil then return nil end
            if rawequal(info, secret) then return secret end
            return 1, info.stackCount, info.isLocked, 1, false, false, info.hyperlink,
                false, info.hasNoValue -- Exercise pre-itemID tuple + GetContainerItemID fallback.
        end
        GetContainerItemID = function(bag, slot)
            if secretField == "itemID" then return secret end
            return bags[bag][slot].id
        end
    else
        C_Container = {GetContainerNumSlots = NumSlots, GetContainerItemInfo = Info, UseContainerItem = Use}
    end
    dofile(root .. "/addon/" .. flavor .. "/wow_tools/SellFish.lua")
    local function Event(event, ...)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    sendEvent = Event
    local function Tick(n, elapsed)
        for _ = 1, n or 1 do
            for _, frame in ipairs(frames) do
                if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed or 0.16) end
            end
        end
    end
    local function HasUpdate()
        for _, frame in ipairs(frames) do if frame.scripts.OnUpdate then return true end end
        return false
    end
    local function Click(name, button)
        local control = assert(names[name], name)
        if control.enabled then control.scripts.OnClick(control, button or "LeftButton") end
    end
    local function Open()
        MerchantFrame:Show()
        Event("MERCHANT_SHOW")
    end
    local function Close()
        MerchantFrame:Hide()
        Event("MERCHANT_CLOSED")
    end
    local function Add(text)
        names.WoWToolsSellFishIdInput:SetText(text)
        Click("WoWToolsSellFishAdd")
    end
    Event("ADDON_LOADED", "other")
    assert(wowDetectorDB.sellFishItems[2] == 101)
    Event("ADDON_LOADED", "wow_tools")
    assert(#wowDetectorDB.sellFishItems == 1 and wowDetectorDB.unrelated == "preserve")
    assert(not HasUpdate(), "Idle vendor module polls")
    assert(not names.WoWToolsSellFishSettings, "Settings should be lazy")
    Open()
    local button = assert(names.WoWToolsSellFishButton)
    assert(button.parent == MerchantFrame and button.point[2] == MerchantFrame)
    assert(#calls == 0 and not HasUpdate(), "Opening merchant sold items")
    Click("WoWToolsSellFishButton", "RightButton")
    local window, edit = names.WoWToolsSellFishSettings, names.WoWToolsSellFishIdInput
    assert(window:IsShown() and edit.numeric and #calls == 0)
    assert(names.WoWToolsSellFishRow1.label.text:find("新鲜的美味小鱼", 1, true))
    for _, invalid in ipairs({"0", "-2", "1.5", "abc", "2147483648", ""}) do Add(invalid) end
    assert(#wowDetectorDB.sellFishItems == 1)
    Add("101"); assert(#wowDetectorDB.sellFishItems == 1, "Duplicate accepted")
    Add("102"); assert(#wowDetectorDB.sellFishItems == 2)
    assert(names.WoWToolsSellFishRow2.label.text:find("新鲜的长嘴泥鳅", 1, true))
    Click("WoWToolsSellFishRow1")
    Click("WoWToolsSellFishDelete")
    assert(#wowDetectorDB.sellFishItems == 1 and wowDetectorDB.sellFishItems[1] == 102)
    assert(not names.WoWToolsSellFishRow2:IsShown(), "Deleted row still visible")
    assert(not names.WoWToolsSellFishDelete.enabled)
    Add("101")
    Add("777")
    assert(names.WoWToolsSellFishRow3.label.text:find("名称加载中", 1, true))
    if not legacy then assert(requests[777]) end
    catalog[777] = "新鲜的石鳞鳕鱼"
    Event("GET_ITEM_INFO_RECEIVED", 777, true)
    assert(names.WoWToolsSellFishRow3.label.text:find(catalog[777], 1, true))
    Add("999")
    Event("ITEM_DATA_LOAD_RESULT", 999, false)
    assert(names.WoWToolsSellFishRow4.label.text:find("未知物品", 1, true))
    Click("WoWToolsSellFishDelete") -- Remove currently selected 999 only.
    assert(#wowDetectorDB.sellFishItems == 3 and wowDetectorDB.sellFishItems[3] == 777)
    window:Hide()
    for _, frame in ipairs(frames) do
        assert(not frame.events.GET_ITEM_INFO_RECEIVED and not frame.events.ITEM_DATA_LOAD_RESULT)
    end
    assert(not HasUpdate())
    -- Exact allowlist, all carried bags/stacks, no unlisted/locked/unsellable/bank items.
    bags = {[0] = {[1] = {id = 101}, [2] = {id = 500}, [3] = {id = 102, locked = true},
        [4] = {id = 777, noValue = true}, [8] = {id = 101}},
        [4] = {[2] = {id = 102}}, [-1] = {[1] = {id = 101}}}
    Click("WoWToolsSellFishButton")
    assert(HasUpdate() and not button.enabled)
    Tick(30)
    assert(#calls == 3 and not HasUpdate() and button.enabled)
    assert(bags[0][2] and bags[0][3] and bags[0][4] and bags[-1][1])
    assert(messages[#messages]:find("已出售 3 组", 1, true))
    -- A large backpack is dispatched in bounded batches, without serial confirmation waits.
    local function FillBags()
        bags = {}
        for bag = 0, 4 do
            bags[bag] = {}
            for slot = 1, 8 do bags[bag][slot] = {id = 101} end
        end
    end
    FillBags()
    calls = {}
    Click("WoWToolsSellFishButton")
    Tick(1, 0.049)
    assert(#calls == 0, "Batch interval was ignored")
    Tick(1, 0.0011)
    assert(#calls == 5, "First batch was not bounded to five stacks")
    Tick(9, 0.05)
    assert(#calls == 40 and not HasUpdate(), "Forty stacks should finish within half a simulated second")
    assert(messages[#messages]:find("已出售 40 组", 1, true))
    -- Slow or out-of-order confirmations do not block later slots or create unlimited requests.
    FillBags()
    mode, calls = "unconfirmed", {}
    Click("WoWToolsSellFishButton")
    Tick(8, 0.05)
    assert(#calls == 20 and HasUpdate(), "Outstanding sale limit was not enforced")
    for index = 16, 20 do
        local call = calls[index]
        bags[call.bag][call.slot] = nil
    end
    Tick(1, 0.05)
    assert(#calls == 25, "Later confirmations were blocked by the oldest pending stack")
    Close(); Tick(5, 0.05)
    assert(#calls == 25 and not HasUpdate(), "Queued batches continued after merchant close")
    Open()
    mode, calls = "success", {}
    -- Revalidation also applies between two uses within the same batch.
    bags = {[0] = {}}
    for slot = 1, 6 do bags[0][slot] = {id = 101} end
    afterUse = function()
        afterUse = nil
        bags[0][5] = {id = 500}
        bags[0][4].count = 1
        bags[0][3].locked = true
        bags[0][2].noValue = true
    end
    Click("WoWToolsSellFishButton")
    Tick(4, 0.05)
    assert(#calls == 2 and calls[1].slot == 6 and calls[2].slot == 1 and not HasUpdate())
    assert(bags[0][5].id == 500 and bags[0][4].count == 1 and bags[0][3].locked and bags[0][2].noValue)
    -- Replacement items, changed stacks, and mid-run deletion never get sold.
    bags = {[0] = {[1] = {id = 101}, [2] = {id = 101}}}
    calls = {}
    Click("WoWToolsSellFishButton")
    bags[0][2] = {id = 500}
    bags[0][1].count = 5
    Tick(5)
    assert(#calls == 0 and not HasUpdate())
    bags = {[0] = {[1] = {id = 101}}}
    Click("WoWToolsSellFishButton")
    SlashCmdList.WOWTOOLSSELLFISH()
    Click("WoWToolsSellFishRow2") -- List order: 102, 101, 777.
    Click("WoWToolsSellFishDelete")
    Tick(5)
    assert(#calls == 0)
    Add("101")
    window:Hide()
    -- Each failed/unconfirmed use is attempted once; no permanent timer or retry.
    for _, failure in ipairs({"error", "false", "unconfirmed"}) do
        mode, calls = failure, {}
        bags = {[0] = {[1] = {id = 101}}}
        Click("WoWToolsSellFishButton")
        Tick(30)
        assert(#calls == 1 and bags[0][1] and not HasUpdate(), "Unbounded or repeated sale")
        assert(messages[#messages]:find("已出售 0 组", 1, true), "API return counted as successful sale")
    end
    mode, calls = "success", {}
    for _, field in ipairs({"itemID", "stackCount", "isLocked", "hasNoValue", "hyperlink", "table"}) do
        secretField = field
        Click("WoWToolsSellFishButton")
        Tick(5)
        assert(#calls == 0 and not HasUpdate(), "Restricted item was sold")
    end
    secretField, failInfo = nil, true
    Click("WoWToolsSellFishButton"); Tick(5)
    assert(#calls == 0 and not HasUpdate())
    failInfo = false
    for _, tab in ipairs({2, secret}) do
        MerchantFrame.selectedTab = tab
        Click("WoWToolsSellFishButton")
        assert(#calls == 0 and not HasUpdate())
    end
    MerchantFrame.selectedTab = 1
    for _, value in ipairs({true, secret}) do
        combat = value; Click("WoWToolsSellFishButton"); assert(not HasUpdate())
    end
    combat = false
    for _, value in ipairs({true, secret}) do
        cursor = value; Click("WoWToolsSellFishButton"); assert(not HasUpdate())
    end
    cursor = false
    Click("WoWToolsSellFishButton")
    Close(); Tick(5)
    assert(#calls == 0 and not HasUpdate() and not button:IsShown())
    Open(); Tick(5)
    assert(#calls == 0, "Opening resumed a cancelled sale")
    Click("WoWToolsSellFishButton")
    MerchantFrame.selectedTab = 2
    Tick(5)
    assert(#calls == 0 and not HasUpdate())
    MerchantFrame.selectedTab = 1
    mode = "close" -- Reentrant merchant-close event from inside the bag API.
    bags = {[0] = {[1] = {id = 101}, [2] = {id = 101}, [3] = {id = 101}}}
    Click("WoWToolsSellFishButton")
    Tick(5)
    assert(#calls == 1 and not HasUpdate())
    if not legacy then
        SlashCmdList.WOWTOOLSSELLFISH()
        Add("888")
        assert(names.WoWToolsSellFishRow4.label.text:find(catalog[888], 1, true),
            "Synchronous item event was overwritten by stale loading text")
        window:Hide()
    end
    -- Settings persist independently of detector activation, and survive reload.
    local saved = wowDetectorDB.sellFishItems
    dofile(root .. "/addon/" .. flavor .. "/wow_tools/SellFish.lua")
    Event("ADDON_LOADED", "wow_tools")
    assert(#wowDetectorDB.sellFishItems == #saved)
    for i, id in ipairs(saved) do assert(wowDetectorDB.sellFishItems[i] == id) end
    print("SellFish " .. flavor .. (legacy and " legacy" or " C_Container") .. ": passed")
end
Run("titan", true)
Run("titan", false)
Run("forerver", false)
