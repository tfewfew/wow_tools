-- Offline UI and merchant simulation. No real game APIs or input are used.
local root = TEST_ROOT or "."
local function Run(flavor, legacy)
    local frames, names, messages, calls, requests = {}, {}, {}, {}, {}
    local bags, catalog = {}, {[101] = "新鲜的美味小鱼", [102] = "新鲜的长嘴泥鳅"}
    local sendEvent, afterUse, acknowledge
    local money, simulationTime = 10000, 0
    local priced, prices = false, {[101] = 1, [102] = 2, [777] = 3}
    local soldSlots,postSaleReads,bagReads,slotReads={},0,{},0
    local bagSlots, hiddenBags, unreadableBags = {}, {}, {}
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
    if legacy then MerchantFrameTab1=nil else MerchantFrameTab1=Widget(nil,MerchantFrame) end
    MerchantFrame:Hide()
    MerchantFrame.selectedTab = 1
    DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages + 1] = message end}
    NUM_BAG_SLOTS = 4
    function InCombatLockdown() return combat end
    function CursorHasItem() return cursor end
    function GetMoney() return money end
    ERR_OBJECT_IS_BUSY="物品正忙";ERR_ITEM_LOCKED="物品锁定";ERR_CANT_DO_THAT_RIGHT_NOW="暂时无法执行"
    function ContainerIDToInventoryID(bag) return 20+bag end
    function GetInventoryItemID(_,slot) return bags[slot-20] and next(bags[slot-20]) and 1 or nil end
    local function NumSlots(bag)
        bagReads[bag]=(bagReads[bag] or 0)+1
        if hiddenBags[bag] then return 0 end
        if unreadableBags[bag] then error("Bag metadata unavailable") end
        return bagSlots[bag] or (bag <= 4 and 8 or 100)
    end
    local function Info(bag, slot)
        slotReads=slotReads+1
        if soldSlots[bag..":"..slot] then postSaleReads=postSaleReads+1 end
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
        calls[#calls + 1] = {id = data.id, count = data.count or 20, bag = bag, slot = slot,
            sentAt = simulationTime, price = priced and (prices[data.id] or 1) or 1}
        if mode == "error" then error("API rejected sale") end
        if mode == "false" then return false end
        if mode == "unconfirmed" then return end
        if mode=="busyAlways" or (mode=="busyOnce" and #calls==1) then
            sendEvent("BAG_UPDATE",bag) -- A lock update alone is not a successful sale.
            sendEvent("UI_ERROR_MESSAGE",1,ERR_OBJECT_IS_BUSY);return
        end
        if mode=="permanent" then sendEvent("UI_ERROR_MESSAGE",2,"无法出售该物品");return end
        acknowledge(calls[#calls])
        if mode == "falseAfterAck" then return false end
        if mode == "close" then
            MerchantFrame:Hide()
            for _, frame in ipairs(frames) do
                if frame.events.MERCHANT_CLOSED then frame.scripts.OnEvent(frame, "MERCHANT_CLOSED") end
            end
        end
    end
    local function ItemInfo(id)
        if type(id) == "string" then id = tonumber(id:match("^item:(%d+)")) end
        local price = priced and prices[id] or nil
        if secretField == "price" then price = secret end
        return catalog[id], nil, nil, nil, nil, nil, nil, nil, nil, nil, price
    end
    C_Item = {GetItemInfo = ItemInfo, RequestLoadItemDataByID = function(id)
        requests[id] = true
        if id == 888 then
            catalog[id] = "新鲜的斑点黄尾鱼"
            sendEvent("ITEM_DATA_LOAD_RESULT", id, true)
        end
    end}
    ItemLocation = {CreateFromBagAndSlot = function(_, bag, slot) return {bag = bag, slot = slot} end}
    C_Item.GetItemGUID = function(location)
        if secretField == "guid" then return secret end
        local data = bags[location.bag] and bags[location.bag][location.slot]
        return data and data.guid
    end
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
            simulationTime = simulationTime + (elapsed or 0.16)
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
    assert(button.parent == MerchantFrame and button.width==78 and button.height==24)
    if MerchantFrameTab1 then
        assert(button.point[1]=="BOTTOMLEFT" and button.point[2]==MerchantFrameTab1 and button.point[3]=="TOPLEFT"
            and button.point[4]==0 and button.point[5]==0)
    else
        assert(button.point[1]=="BOTTOMLEFT" and button.point[2]==MerchantFrame and button.point[3]=="BOTTOMLEFT"
            and button.point[4]==16 and button.point[5]==0)
    end
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
    -- The entire carried inventory must be counted before any request is sent.
    local function ResetTrace()
        soldSlots, postSaleReads, bagReads, slotReads = {}, 0, {}, 0
    end
    local function Ack(call, notify)
        if call.acked then return end
        call.acked = true
        bags[call.bag][call.slot] = nil
        soldSlots[call.bag .. ":" .. call.slot] = true
        money = money + call.count * call.price
        if afterUse then afterUse() end
        if notify ~= false then
            Event("BAG_UPDATE",call.bag)
            Event("PLAYER_MONEY")
        end
    end
    acknowledge = Ack
    local function Fill42()
        bags,bagSlots = {[0]={},[1]={},[2]={}}, {[0]=20,[1]=24,[2]=20,[3]=20,[4]=20}
        for slot=1,19 do bags[0][slot]={id=101} end
        for slot=1,21 do bags[1][slot]={id=102} end
        for slot=1,2 do bags[2][slot]={id=777} end
    end
    bags = {[0] = {[1] = {id = 101}, [2] = {id = 500}, [3] = {id = 102, locked = true},
        [4] = {id = 777, noValue = true}, [8] = {id = 101}},
        [4] = {[2] = {id = 102}}, [-1] = {[1] = {id = 101}}}
    ResetTrace()
    Click("WoWToolsSellFishButton")
    assert(#calls==0 and slotReads==40 and bagReads[0]==1 and bagReads[4]==1,
        "A sale request was sent before all five bags were scanned")
    assert(messages[#messages]:find("清单匹配 5 组，可出售 4 组",1,true))
    Tick(2,0.05)
    assert(#calls==1 and HasUpdate(),"Locked queued entry was skipped instead of waiting")
    bags[0][3].locked=false
    Tick(10,0.05)
    assert(#calls==4 and not HasUpdate() and button.enabled)
    assert(bags[0][2] and bags[0][4] and bags[-1][1] and not bags[0][3])
    assert(messages[#messages]:find("固定清单 4 组已全部出售",1,true))
    assert(postSaleReads==0 and bagReads[0]==1,"Seller inspected sold slots or rescanned inventory")

    -- Screenshot regression: 19 + 21 + 2 = 42 groups, not a 20-group partial plan.
    Fill42();ResetTrace();calls={}
    NUM_BAG_SLOTS=0
    Click("WoWToolsSellFishButton")
    assert(#calls==0 and slotReads==104 and messages[#messages]:find("可出售 42 组",1,true))
    assert(messages[#messages]:find("0:19/20，1:21/24，2:2/20，3:0/20，4:0/20",1,true))
    Tick(1,0.049);assert(#calls==0)
    Tick(1,0.0011);assert(#calls==1)
    Tick(50,0.05)
    assert(#calls==42 and not HasUpdate(),"Fixed 42-group plan did not finish past twenty")
    assert(postSaleReads==0 and slotReads==104+42,"Post-sale inventory verification was performed")
    for bag=0,4 do assert(bagReads[bag]==1,"Inventory was scanned more than once") end
    assert(messages[#messages]:find("固定清单 42 组已全部出售",1,true))
    NUM_BAG_SLOTS=4

    -- A server-side lock after the twentieth sale must pause, not discard, the remaining plan.
    Fill42();ResetTrace();calls={}
    afterUse=function()
        if #calls==20 then
            afterUse=nil
            for _,bag in pairs(bags) do for _,data in pairs(bag) do data.locked=true end end
        end
    end
    Click("WoWToolsSellFishButton");Tick(25,0.05)
    assert(#calls==20 and HasUpdate(),"Temporary lock after twenty dropped later queued groups")
    for _,bag in pairs(bags) do for _,data in pairs(bag) do data.locked=false end end
    Tick(30,0.05)
    assert(#calls==42 and not HasUpdate() and postSaleReads==0,"Original plan did not resume through all 42 groups")

    -- An equipped but unreadable/zero-slot bag aborts the whole scan before the first sale.
    for _,partial in ipairs({"hidden","unreadable"}) do
        Fill42();ResetTrace();calls={}
        if partial=="hidden" then hiddenBags[1]=true else unreadableBags[1]=true end
        Click("WoWToolsSellFishButton");Tick(10)
        assert(#calls==0 and not HasUpdate() and messages[#messages]:find("扫描未完成",1,true))
        hiddenBags[1],unreadableBags[1]=nil,nil
        Click("WoWToolsSellFishButton");Tick(50,0.05)
        assert(#calls==42 and not HasUpdate())
    end

    -- Delayed receipts block only the current original queue entry; no bag re-reads.
    Fill42();ResetTrace();mode,calls="unconfirmed",{}
    Click("WoWToolsSellFishButton");Tick(1,0.05)
    local first=calls[1]
    Ack(first,false)
    Event("BAG_UPDATE",4);Event("PLAYER_MONEY")
    local readCount=slotReads
    Tick(3,0.05)
    assert(#calls==1 and HasUpdate() and slotReads==readCount,
        "Wrong bag event advanced the queue or pending sales read inventory")
    Event("BAG_UPDATE",first.bag)
    Tick(1,0.05);assert(#calls==2)
    for _=1,45 do
        Ack(calls[#calls])
        Tick(1,0.8)
    end
    assert(#calls==42 and not HasUpdate(),"Sale was limited by total time or total group count")
    assert(postSaleReads==0)

    -- Cached vendor prices allow eight requests per batch. A partial money receipt
    -- must not advance the batch, even if a bag event has already arrived.
    priced, mode, calls = true, "unconfirmed", {}
    Fill42();ResetTrace()
    Click("WoWToolsSellFishButton");Tick(1,0.05)
    assert(#calls==8 and slotReads==112, "Priced sales did not send an eight-group batch")
    Ack(calls[1],false);Event("BAG_UPDATE",0);Event("PLAYER_MONEY")
    Tick(5,0.05)
    assert(#calls==8 and HasUpdate(), "A partial batch receipt was reported as complete")
    for i=2,8 do Ack(calls[i],false) end
    Event("PLAYER_MONEY");Tick(1,0.05)
    assert(#calls==16, "Aggregate money receipt did not release the next batch")
    Close();Open()

    -- Coalesced, out-of-order events must cover every bag in this batch.
    bags={[0]={[1]={id=101},[2]={id=102}},[1]={[1]={id=777}}}
    calls={};ResetTrace()
    Click("WoWToolsSellFishButton");Tick(1,0.05)
    assert(#calls==3)
    for _,call in ipairs(calls) do Ack(call,false) end
    Event("PLAYER_MONEY");Event("BAG_UPDATE",0);Tick(2,0.05)
    assert(HasUpdate(), "Batch completed without every affected bag's receipt")
    Event("BAG_UPDATE",1);Tick(1,0.05)
    assert(not HasUpdate() and postSaleReads==0)

    -- With 300 ms server latency, 42 groups should take about six round trips,
    -- not 42. Limit in-flight requests to eight, with no rescan or sold-slot reads.
    Fill42();ResetTrace();calls={}
    local started=simulationTime
    Click("WoWToolsSellFishButton")
    for _=1,100 do
        local before=#calls
        Tick(1,0.05)
        assert(#calls-before<=8, "A single update exceeded the eight-group batch")
        local changed,waiting=false,0
        for _,call in ipairs(calls) do
            if not call.acked then
                waiting=waiting+1
                if simulationTime-call.sentAt>=0.3 then Ack(call,false);changed=true end
            end
        end
        assert(waiting<=8, "More than eight requests were in flight")
        if changed then Event("BAG_UPDATE_DELAYED");Event("PLAYER_MONEY") end
        if not HasUpdate() then break end
    end
    assert(#calls==42 and not HasUpdate() and simulationTime-started<5,
        "Batched 42-group sale did not complete within five simulated seconds")
    assert(postSaleReads==0 and slotReads==146, "Acceleration added post-sale inventory verification")
    for bag=0,4 do assert(bagReads[bag]==1) end
    print("SellFish " .. flavor .. (legacy and " legacy" or " C_Container")
        .. ": 42 groups / 300ms receipts in " .. string.format("%.2f",simulationTime-started) .. " simulated seconds")

    -- The old twenty-group boundary cannot discard locked later entries.
    mode,calls="success",{}
    Fill42();ResetTrace()
    afterUse=function()
        if #calls==20 then
            afterUse=nil
            for _,bag in pairs(bags) do for _,data in pairs(bag) do data.locked=true end end
        end
    end
    Click("WoWToolsSellFishButton");Tick(8,0.05)
    assert(#calls==20 and HasUpdate())
    for _,bag in pairs(bags) do for _,data in pairs(bag) do data.locked=false end end
    Tick(8,0.05)
    assert(#calls==42 and not HasUpdate() and postSaleReads==0)

    -- A synchronous busy error in a batch drains the accepted prefix, then retries
    -- only the rejected slot, sequentially. Successful entries are never replayed.
    Fill42();ResetTrace();calls={}
    acknowledge=function(call)
        if #calls==3 then Event("UI_ERROR_MESSAGE",1,ERR_OBJECT_IS_BUSY) else Ack(call) end
    end
    Click("WoWToolsSellFishButton");Tick(100,0.05)
    assert(#calls==43 and calls[3].slot==calls[4].slot and not HasUpdate() and postSaleReads==0,
        "Busy response lost a fixed entry or replayed an accepted batch")
    acknowledge=Ack

    -- An ambiguous asynchronous batch error must not replay possibly sold slots,
    -- or count partial proceeds as all eight successes.
    Fill42();ResetTrace();mode,calls="unconfirmed",{}
    Click("WoWToolsSellFishButton");Tick(1,0.05)
    Ack(calls[1],false);Ack(calls[2],false)
    Event("BAG_UPDATE_DELAYED");Event("PLAYER_MONEY");Event("UI_ERROR_MESSAGE",1,ERR_OBJECT_IS_BUSY)
    Tick(110,0.05)
    assert(#calls==8 and not HasUpdate() and postSaleReads==0)
    assert(messages[#messages]:find("未完成",1,true))

    -- Unknown or restricted prices preserve the previous single-item path.
    for _,priceCase in ipairs({"missing","restricted"}) do
        mode,calls="success",{}
        bags={[0]={[1]={id=101},[2]={id=101},[3]={id=101}}};ResetTrace()
        if priceCase=="missing" then prices[101]=nil else secretField="price" end
        Click("WoWToolsSellFishButton");Tick(1,0.05)
        assert(#calls==1, "Unknown price was used for a batch receipt")
        Tick(5,0.05)
        assert(#calls==3 and not HasUpdate() and postSaleReads==0)
        prices[101],secretField=1,nil
    end

    -- Pre-send checks also protect later entries within the same frame/batch.
    mode,calls="falseAfterAck",{}
    bags={[0]={[1]={id=101},[2]={id=102}}};ResetTrace()
    Click("WoWToolsSellFishButton");Tick(5,0.05)
    assert(#calls==2 and not HasUpdate() and postSaleReads==0,
        "An API rejection after confirmed proceeds replayed an accepted sale")

    mode,calls="close",{}
    Fill42();ResetTrace()
    Click("WoWToolsSellFishButton");Tick(5,0.05)
    assert(#calls==1 and not HasUpdate(), "Closing the merchant did not stop inside a batch")
    Open()

    mode="success"
    Fill42();ResetTrace();calls={}
    afterUse=function() afterUse=nil;bags[0][18]={id=500} end
    Click("WoWToolsSellFishButton");Tick(3,0.05)
    assert(#calls==1 and not HasUpdate() and postSaleReads==0)
    assert(messages[#messages]:find("未完成：已出售 1/42",1,true))
    priced=false

    -- Temporary server-busy responses retry the same queue entry, not skip it.
    mode,calls="busyOnce",{}
    bags={[0]={[1]={id=101},[2]={id=102}}};ResetTrace()
    Click("WoWToolsSellFishButton");Tick(30,0.05)
    assert(#calls==3 and calls[1].slot==2 and calls[2].slot==2 and calls[3].slot==1 and not HasUpdate())
    assert(messages[#messages]:find("固定清单 2 组已全部出售",1,true))

    -- No new items are appended after the fixed plan was created.
    mode,calls="success",{}
    bags={[0]={[1]={id=101,guid="original"}}};ResetTrace()
    afterUse=function()
        afterUse=nil
        bags[0][1]={id=101,guid="new-item"}
    end
    Click("WoWToolsSellFishButton");Tick(5,0.05)
    assert(#calls==1 and bags[0][1].guid=="new-item" and not HasUpdate() and postSaleReads==0)

    -- Before-send checks stop on changes; no changed/unlisted item is blindly sold.
    bags={[0]={[1]={id=101},[2]={id=101}}};ResetTrace();calls={}
    Click("WoWToolsSellFishButton")
    bags[0][2]={id=500}
    Tick(3,0.05)
    assert(#calls==0 and not HasUpdate() and messages[#messages]:find("未完成",1,true))
    bags={[0]={[1]={id=101}}};ResetTrace()
    Click("WoWToolsSellFishButton")
    SlashCmdList.WOWTOOLSSELLFISH()
    Click("WoWToolsSellFishRow2")
    Click("WoWToolsSellFishDelete")
    Tick(3,0.05);assert(#calls==0 and not HasUpdate())
    Add("101");window:Hide()

    -- Errors, missing receipts and a persistent lock are reported as incomplete, never all sold.
    for _,failure in ipairs({"error","false","unconfirmed","busyAlways","permanent"}) do
        mode,calls=failure,{}
        bags={[0]={[1]={id=101}}};ResetTrace()
        Click("WoWToolsSellFishButton");Tick(50,0.16)
        local expected=(failure=="unconfirmed" or failure=="permanent") and 1 or 3
        assert(#calls==expected and bags[0][1] and not HasUpdate(),"Retries were unbounded or a failed item was lost")
        assert(messages[#messages]:find("未完成：已出售 0/1 组",1,true),"Unconfirmed request was reported as sold")
        assert(postSaleReads==0)
    end
    mode,calls="success",{}
    bags={[0]={[1]={id=101,locked=true}}};ResetTrace()
    Click("WoWToolsSellFishButton");Tick(40,0.16)
    assert(#calls==0 and not HasUpdate() and messages[#messages]:find("未跳过该组",1,true))

    local restrictedFields={"itemID","stackCount","isLocked","hasNoValue","hyperlink","table"}
    if not legacy then restrictedFields[#restrictedFields+1]="guid" end
    for _,field in ipairs(restrictedFields) do
        bags={[0]={[1]={id=101}}};ResetTrace();secretField=field
        Click("WoWToolsSellFishButton");Tick(5)
        assert(#calls==0 and not HasUpdate(),"Restricted item was sold")
    end
    secretField,failInfo=nil,true
    Click("WoWToolsSellFishButton");Tick(5)
    assert(#calls==0 and not HasUpdate())
    failInfo=false
    for _,tab in ipairs({2,secret}) do
        MerchantFrame.selectedTab=tab
        Click("WoWToolsSellFishButton");assert(#calls==0 and not HasUpdate())
    end
    MerchantFrame.selectedTab=1
    for _,value in ipairs({true,secret}) do combat=value;Click("WoWToolsSellFishButton");assert(not HasUpdate()) end
    combat=false
    for _,value in ipairs({true,secret}) do cursor=value;Click("WoWToolsSellFishButton");assert(not HasUpdate()) end
    cursor=false
    Click("WoWToolsSellFishButton");Close();Tick(5)
    assert(#calls==0 and not HasUpdate() and not button:IsShown())
    Open();Tick(5);assert(#calls==0,"Opening resumed a cancelled plan")
    Click("WoWToolsSellFishButton");MerchantFrame.selectedTab=2;Tick(5)
    assert(#calls==0 and not HasUpdate())
    MerchantFrame.selectedTab=1
    mode="close";bags={[0]={[1]={id=101},[2]={id=101}}};ResetTrace()
    Click("WoWToolsSellFishButton");Tick(5)
    assert(#calls==1 and not HasUpdate())
    for _,frame in ipairs(frames) do
        assert(not frame.events.BAG_UPDATE and not frame.events.PLAYER_MONEY and not frame.events.UI_ERROR_MESSAGE,
            "Receipt events remained active after stop")
    end
    if not legacy then
        SlashCmdList.WOWTOOLSSELLFISH();Add("888")
        assert(names.WoWToolsSellFishRow4.label.text:find(catalog[888],1,true))
        window:Hide()
    end
    -- Preset merges with the custom list; repeated imports and manual additions share deduplication.
    catalog[41813], catalog[41806], catalog[41809] = "预设鱼一", "预设鱼二", "预设鱼三"
    SlashCmdList.WOWTOOLSSELLFISH()
    local preset = assert(names.WoWToolsSellFishWintergrasp)
    assert(preset.text == "冬拥湖三杰")
    Add("41806")
    local beforePreset, beforeCalls = #wowDetectorDB.sellFishItems, #calls
    Click("WoWToolsSellFishWintergrasp")
    assert(#wowDetectorDB.sellFishItems == beforePreset + 2, "Preset did not merge existing IDs")
    assert(wowDetectorDB.sellFishItems[1] == 102 and wowDetectorDB.sellFishItems[2] == 777,
        "Preset replaced or reordered custom items")
    for _, id in ipairs({41813, 41806, 41809}) do
        local count = 0
        for index, value in ipairs(wowDetectorDB.sellFishItems) do
            if value == id then
                count = count + 1
                assert(names["WoWToolsSellFishRow" .. index].label.text:find(catalog[id], 1, true),
                    "Preset row did not resolve its item name")
            end
        end
        assert(count == 1, "Preset ID is missing or duplicated")
    end
    Click("WoWToolsSellFishWintergrasp")
    Click("WoWToolsSellFishWintergrasp")
    Add("041813")
    assert(#wowDetectorDB.sellFishItems == beforePreset + 2, "Repeated import or manual ID created duplicates")
    for index, id in ipairs(wowDetectorDB.sellFishItems) do
        if id == 41809 then Click("WoWToolsSellFishRow" .. index); break end
    end
    Click("WoWToolsSellFishDelete")
    Click("WoWToolsSellFishWintergrasp")
    assert(#wowDetectorDB.sellFishItems == beforePreset + 2, "Deleted preset item was not restored once")
    assert(#calls == beforeCalls and not HasUpdate(), "Preset import triggered sales or polling")
    window:Hide()
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
