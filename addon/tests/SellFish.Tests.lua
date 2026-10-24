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
    -- Simulated time only: one request every 50 seconds, no receipt subscription.
    local function ResetTrace()
        soldSlots, postSaleReads, bagReads, slotReads = {}, 0, {}, 0
        calls = {}
    end
    local function Ack(call)
        bags[call.bag][call.slot] = nil
    end
    acknowledge = Ack
    local function Begin(data, behavior)
        Close();Open();bags=data;mode=behavior or "success";ResetTrace()
        Click("WoWToolsSellFishButton")
    end
    local function FinishRound(count)
        for _=1,count do Tick(1,50) end
        Tick(1,0.5)
    end
    Begin({[0]={[1]={id=101},[2]={id=102}},[-1]={[1]={id=101}}})
    assert(slotReads==40 and #calls==0 and HasUpdate(), "Initial scan must finish before sends")
    for _,frame in ipairs(frames) do
        assert(not frame.events.BAG_UPDATE and not frame.events.BAG_UPDATE_DELAYED
            and not frame.events.PLAYER_MONEY and not frame.events.UI_ERROR_MESSAGE, "Seller still waits for receipts")
    end
    Tick(1,49.999);assert(#calls==0)
    Tick(1,0.0011);assert(#calls==1)
    Tick(1,49.999);assert(#calls==1)
    Tick(1,0.0011);assert(#calls==2)
    assert(calls[2].sentAt-calls[1].sentAt>=50)
    assert(bagReads[0]==1 and HasUpdate(), "Rescan started before settling delay")
    Tick(1,0.499);assert(bagReads[0]==1)
    Tick(1,0.0011)
    assert(bagReads[0]==2 and not HasUpdate() and bags[-1][1] and button.enabled)
    assert(messages[#messages]:find("可出售物品为 0",1,true))

    -- Rejected/unknown sales never block the rest of a round; at most three rounds.
    for _,behavior in ipairs({"unconfirmed","false","error","busyAlways","permanent"}) do
        Begin({[0]={[1]={id=101},[2]={id=102}}},behavior)
        for round=1,3 do
            local scans=bagReads[0]
            Tick(1,50);Tick(1,50)
            assert(#calls==round*2 and bagReads[0]==scans, "A result delayed the next queued request")
            Tick(1,0.5)
            assert(HasUpdate()==(round<3), "Wrong round limit")
        end
        assert(bagReads[0]==4 and messages[#messages]:find("仍有 2 组",1,true))
    end
    -- A transient failure succeeds on the fresh second scan; no third round starts.
    Begin({[0]={[1]={id=101}}},"unconfirmed")
    FinishRound(1);assert(#calls==1 and HasUpdate())
    mode="success";FinishRound(1)
    assert(#calls==2 and bagReads[0]==3 and not HasUpdate())

    -- Fresh scans include newly arrived matching stacks; each round is a new queue.
    Begin({[0]={[1]={id=101}}})
    Tick(1,50);bags[1]={[2]={id=102}};Tick(1,0.5)
    assert(HasUpdate() and #calls==1)
    FinishRound(1);assert(#calls==2 and calls[2].bag==1 and not HasUpdate())

    -- Locks and moved/replaced stacks are skipped this round, reconsidered next scan.
    Begin({[0]={[1]={id=101,locked=true},[2]={id=102}}})
    Tick(1,50);Tick(1,50);assert(#calls==1)
    bags[0][1].locked=false;Tick(1,0.5);FinishRound(1)
    assert(#calls==2 and not HasUpdate())
    Begin({[0]={[1]={id=101},[2]={id=101}}})
    bags[0][2]={id=500}
    FinishRound(2);assert(#calls==1 and bags[0][2].id==500 and not HasUpdate())
    Begin({[0]={[1]={id=101,noValue=true}}})
    assert(#calls==0 and not HasUpdate())

    -- Long frames cannot emit a burst or consume the post-round 500ms in that frame.
    Begin({[0]={[1]={id=101},[2]={id=101}}})
    Tick(1,500);assert(#calls==1)
    Tick(1,500);assert(#calls==2 and bagReads[0]==1)
    Tick(1,0.5);assert(not HasUpdate())

    -- Forty-two stacks finish without a twenty-stack cap, independently of prices/money.
    local data={[0]={},[1]={},[2]={}}
    bagSlots={[0]=20,[1]=24,[2]=20,[3]=20,[4]=20}
    for slot=1,19 do data[0][slot]={id=101} end
    for slot=1,21 do data[1][slot]={id=102} end
    for slot=1,2 do data[2][slot]={id=777} end
    Begin(data);assert(slotReads==104)
    GetMoney=nil;FinishRound(42)
    assert(#calls==42 and bagReads[0]==2 and not HasUpdate())
    bagSlots={}
    for _,partial in ipairs({"hidden","unreadable"}) do
        if partial=="hidden" then hiddenBags[1]=true else unreadableBags[1]=true end
        Begin({[0]={[1]={id=101}},[1]={[1]={id=102}}})
        assert(#calls==0 and not HasUpdate())
        hiddenBags[1],unreadableBags[1]=nil,nil
    end
    for _,field in ipairs({"itemID","stackCount","isLocked","hasNoValue","hyperlink","table"}) do
        secretField=field;Begin({[0]={[1]={id=101}}})
        assert(#calls==0 and not HasUpdate(), "Restricted item was sold")
    end
    secretField=nil
    -- Safety gates cancel during both sending and the 500ms settling phase.
    for _,gate in ipairs({"close","tab","combat","cursor"}) do
        Begin({[0]={[1]={id=101}}})
        if gate=="close" then Close() elseif gate=="tab" then MerchantFrame.selectedTab=2
        elseif gate=="combat" then combat=true else cursor=true end
        Tick(1,50);assert(#calls==0 and not HasUpdate())
        combat,cursor=false,false;MerchantFrame.selectedTab=1
        Begin({[0]={[1]={id=101}}});Tick(1,50);Close();Tick(1,0.5)
        assert(not HasUpdate());Open();Tick(1,50);assert(#calls==1 and not HasUpdate())
    end
    Begin({[0]={[1]={id=101},[2]={id=102}}},"close")
    Tick(1,50);assert(#calls==1 and not HasUpdate());Open()
    mode="success"
    -- Preset merges with the custom list; repeated imports and manual additions share deduplication.
    catalog[41813], catalog[41806], catalog[41809] = "预设鱼一", "预设鱼二", "预设鱼三"
    SlashCmdList.WOWTOOLSSELLFISH()
    local preset = assert(names.WoWToolsSellFishWintergrasp)
    assert(preset.text == "冬拥湖三杰")
    Add("41806")
    local beforePreset, beforeCalls = #wowDetectorDB.sellFishItems, #calls
    Click("WoWToolsSellFishWintergrasp")
    assert(#wowDetectorDB.sellFishItems == beforePreset + 2, "Preset did not merge existing IDs")
    assert(wowDetectorDB.sellFishItems[1] == 102 and wowDetectorDB.sellFishItems[2] == 101 and wowDetectorDB.sellFishItems[3] == 777,
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
