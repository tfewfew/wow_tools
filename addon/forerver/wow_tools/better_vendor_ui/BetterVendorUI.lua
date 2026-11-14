local ns = WoWTools.betterVendorUI
local ADDON_NAME = "BetterVendorUI"

function ns.Initialize()
    -- BetterVendorUI.lua

    local searchString = ""

    ns.DEFAULTS = {
        -- Merchant window
        showSearch = true,
        searchMode = "dim",         -- "dim" | "hide"
        dimAlpha = 0.2,
        clearSearchOnShow = true,
        knownRecipes = true,
        qualityBorders = true,
        minBorderQuality = 2,       -- Uncommon
        showListsButton = true,
        showOptionsButton = true,
        showFilterButton = true,
        resetFiltersOnShow = true,
        usableOnlyDefault = false,
        showSlotFilters = false,
        gridColumns = 4,
        gridRows = 5,
        buybackFullWidth = true,
        -- Selling junk
        overrideSellButton = true,
        keepSellButtonEnabled = true,
        sellAlwaysList = true,
        autoSell = false,
        keepGreyGear = false,
        limit12 = false,
        printSummary = true,
        printNoJunk = true,
        -- Leatrix Plus
        leatrixSyncNeverSell = true,
        leatrixSellAlwaysList = true,
        -- EllesmereUI
        ellesmereNeverSell = true,
        ellesmereAlwaysSell = true,
    }

    -- Settings that only matter when selling, so changing them needs no merchant redraw
    local NO_REDRAW = {
        clearSearchOnShow = true, overrideSellButton = true, sellAlwaysList = true, autoSell = true,
        keepGreyGear = true, limit12 = true, printSummary = true, printNoJunk = true,
        leatrixSyncNeverSell = true, leatrixSellAlwaysList = true,
        resetFiltersOnShow = true, usableOnlyDefault = true,
        ellesmereNeverSell = true, ellesmereAlwaysSell = true,
    }

    function ns.Get(key)
        local s = ns.DB and ns.DB.settings
        if s and s[key] ~= nil then return s[key] end
        return ns.DEFAULTS[key]
    end

    function ns.Set(key, value)
        if not ns.DB then return end
        ns.DB.settings[key] = value
        ns.ApplySettings(key)
    end

    function ns.ResetSettings()
        if not ns.DB then return end
        ns.DB.settings = {}
        ns.ApplySettings()
    end

    -- API fallbacks, resolved once: older clients have the globals, newer ones the C_ namespaces
    local GetItemInfoSafe = GetItemInfo or (C_Item and C_Item.GetItemInfo) or function() end
    ns.GetItemInfoSafe = GetItemInfoSafe

    local RawMerchantItemInfo = GetMerchantItemInfo or function(index)
        local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(index)
        if type(info) == "table" then
            return info.name, info.texture, info.price, info.stackCount or info.quantity or 1, info.numAvailable, info.isPurchasable, info.isUsable, info.hasExtendedCost, info.currencyID
        end
    end

    -- Currency containers go by the container's name, icon and amount, as in Blizzard's window
    local function GetMerchantItemInfoSafe(index)
        local name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, extendedCost, currencyID = RawMerchantItemInfo(index)
        if currencyID and CurrencyContainerUtil then
            name, texture, numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID, numAvailable, name, texture, nil)
        end
        return name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, extendedCost
    end

    local GetMerchantItemLinkSafe = GetMerchantItemLink or (C_MerchantFrame and C_MerchantFrame.GetItemLink) or function() end

    local GetMerchantNumItemsSafe = GetMerchantNumItems or (C_MerchantFrame and C_MerchantFrame.GetNumItems) or function() end
    ns.GetMerchantItemInfoSafe = GetMerchantItemInfoSafe
    ns.GetMerchantItemLinkSafe = GetMerchantItemLinkSafe
    ns.GetMerchantNumItemsSafe = GetMerchantNumItemsSafe

    local GetItemQualityColorSafe = GetItemQualityColor or (C_Item and C_Item.GetItemQualityColor)
        or function() return 1, 1, 1, "ffffffff" end
    ns.GetItemQualityColorSafe = GetItemQualityColorSafe

    local GetCoinTextureStringSafe = GetCoinTextureString
        or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
        or function(amount) return amount .. 'c' end

    local GetContainerNumSlotsSafe = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local UseContainerItemSafe = (C_Container and C_Container.UseContainerItem) or UseContainerItem

    -- Returns itemID, stackCount, isBound, isLocked for a bag slot, or nil if empty
    local ReadBagSlot
    if C_Container and C_Container.GetContainerItemInfo then
        ReadBagSlot = function(bag, slot)
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then return info.itemID, info.stackCount or 1, info.isBound, info.isLocked end
        end
    else
        ReadBagSlot = function(bag, slot)
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                local _, count, locked = GetContainerItemInfo(bag, slot)
                return itemID, count or 1, false, locked
            end
        end
    end

    -- Asks the game to load an item's details; GET_ITEM_INFO_RECEIVED fires when they arrive
    function ns.RequestItem(itemID)
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("PLAYER_LOGIN")  -- every addon is loaded by then (EllesmereUI hook)

    local searchBox
    local configBtn
    local optionsBtn
    local filterBtn
    local origSellClick

    local function IsAddOnLoadedSafe(name)
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        return isLoaded and isLoaded(name) or false
    end

    ---------------------------------------------------------------------------
    -- Leatrix Plus integration
    ---------------------------------------------------------------------------

    -- Leatrix Plus "Sell junk automatically" integration.
    -- The exclusions editbox only exists when that feature is enabled. Setting its text
    -- runs Leatrix's own update, which refreshes its exclusion list and saves it.
    -- Leatrix gives its panels random names, so find the panel by what it does: it's the
    -- MERCHANT_SHOW listener with a scrolling editbox child. Leatrix's other editbox panels
    -- don't listen to that event.
    local leatrixBox
    local function GetLeatrixExcludeBox()
        if leatrixBox then return leatrixBox end
        if not GetFramesRegisteredForEvent or not IsAddOnLoadedSafe("Leatrix_Plus") then return end
        for _, listener in ipairs({ GetFramesRegisteredForEvent("MERCHANT_SHOW") }) do
            if not (listener.IsForbidden and listener:IsForbidden()) then
                for _, child in ipairs({ listener:GetChildren() }) do
                    local scroll = child.scroll
                    if type(scroll) == "table" and scroll.CharCount and child.Text and child.Text.SetText then
                        leatrixBox = child.Text  -- the panel is built once, so this never changes
                        return leatrixBox
                    end
                end
            end
        end
    end

    -- "none" = Leatrix not loaded, "off" = loaded but auto-sell disabled, "on" = auto-sell active
    function ns.LeatrixState()
        if GetLeatrixExcludeBox() then return "on" end
        return IsAddOnLoadedSafe("Leatrix_Plus") and "off" or "none"
    end

    -- Mirror grey items from our blacklist into Leatrix's exclusions so it won't sell them.
    -- DB.leatrixAdded tracks IDs we added, so we never remove entries the user typed in.
    -- With the option off, everything we added is removed again.
    function ns.SyncLeatrix()
        local DB = ns.DB
        if not DB then return end
        local box = GetLeatrixExcludeBox()
        if not box then return end
        DB.leatrixAdded = DB.leatrixAdded or {}
        local enabled = ns.Get("leatrixSyncNeverSell")

        local ids, present = {}, {}
        for id in (box:GetText() or ""):gmatch("%d+") do
            id = tonumber(id)
            if not present[id] then
                present[id] = true
                table.insert(ids, id)
            end
        end

        local changed = false
        for id in pairs(DB.leatrixAdded) do
            if not enabled or not DB.blacklist[id] then
                DB.leatrixAdded[id] = nil
                present[id] = nil
                changed = true
            end
        end
        if enabled then
            for id in pairs(DB.blacklist) do
                if not present[id] then
                    local _, _, quality = GetItemInfoSafe(id)
                    -- Only greys: Leatrix treats white items in its exclusions as "sell"
                    if quality == 0 then
                        present[id] = true
                        DB.leatrixAdded[id] = true
                        table.insert(ids, id)
                        changed = true
                    elseif quality == nil then
                        ns.RequestItem(id)  -- synced again once its details arrive
                    end
                end
            end
        end

        if changed then
            local out = {}
            for _, id in ipairs(ids) do
                if present[id] then table.insert(out, id) end
            end
            box:SetText(table.concat(out, ","))
        end
    end

    ---------------------------------------------------------------------------
    -- EllesmereUI integration
    ---------------------------------------------------------------------------

    -- EllesmereUI sells junk one of two ways (EllesmereUIQoL's Auto Sell Junk, and the Sell
    -- Junk button in EllesmereUIBags):
    --   Junk Marker on (EllesmereUIBags' coin): it sells what EUI_CategoryManager:IsJunk says,
    --     and every junk check (selling, badge, Junk category) goes through that one method,
    --     so wrapping it lets our lists decide.
    --   Junk Marker off: C_MerchantFrame.SellAllJunkItems(), which sells every grey item
    --     server side; nothing can be excluded from that.

    -- loaded: any EllesmereUI selling present; autoSell: Auto Sell Junk runs at vendors;
    -- marker: the Junk Marker is on, so our lists apply to EllesmereUI's selling
    function ns.EllesmereInfo()
        local cats = _G.EUI_CategoryManager
        local marker = cats and cats.IsJunkMarkerEnabled and cats:IsJunkMarkerEnabled() or false
        local qol = IsAddOnLoadedSafe("EllesmereUIQoL")
        local autoSell = qol and EllesmereUIDB ~= nil and EllesmereUIDB.autoSellJunk ~= false
        return qol or cats ~= nil, autoSell, marker
    end

    local function HookEllesmere()
        local cats = _G.EUI_CategoryManager
        if not cats or cats.BetterVendorUIHooked or type(cats.IsJunk) ~= "function" then return end
        local origIsJunk = cats.IsJunk
        cats.IsJunk = function(self, itemID, quality)
            local DB = ns.DB
            if DB and itemID and self:IsJunkMarkerEnabled() then
                if DB.blacklist[itemID] and ns.Get("ellesmereNeverSell") then return false end
                if DB.whitelist[itemID] and ns.Get("sellAlwaysList") and ns.Get("ellesmereAlwaysSell") then
                    return true
                end
            end
            return origIsJunk(self, itemID, quality)
        end
        cats.BetterVendorUIHooked = true
    end

    -- EllesmereUIBlizzardSkin skins the merchant window (needs a reload to change)
    function ns.EllesmereMerchantSkinOn()
        if not IsAddOnLoadedSafe("EllesmereUIBlizzardSkin") then return false end
        local getStyle = EllesmereUI and EllesmereUI.GetBlizzWindowStyle
        return not (getStyle and getStyle("merchant") == "off")
    end

    -- The merchant skin's "Show As List": it hides Blizzard's grid and draws every vendor item
    -- in its own scrolling list (WSkinMerchantScrollFrame), one row per item.
    function ns.EllesmereListMode()
        if not (EllesmereUIDB and EllesmereUIDB.merchantShowAsList == true) then return false end
        return ns.EllesmereMerchantSkinOn()
    end

    -- EllesmereUI look for our own windows, through its public skinning API
    -- (EllesmereUI/SKINNING_API.md). EllesmereUI accepts one registration per addon, so it's
    -- made here and each window subscribes with ns.OnSkin(fn). fn(S) runs once the facade
    -- exists (at login), and only when EllesmereUI's third-party skinning is on for us.
    local skinFacade
    local skinSubscribers = {}

    function ns.OnSkin(fn)
        if skinFacade then fn(skinFacade) else table.insert(skinSubscribers, fn) end
    end

    if EllesmereUI and EllesmereUI.RegisterSkin then
        EllesmereUI.RegisterSkin(ADDON_NAME, function(S)
            skinFacade = S
            for _, fn in ipairs(skinSubscribers) do fn(S) end
        end)
    end

    -- 聊天消息前缀跟随 EllesmereUI 的强调色，默认采用绿色。
    function ns.ChatPrefix()
        local r, g, b = 0, 1, 0
        if skinFacade then r, g, b = skinFacade.GetAccentColor() end
        local function Byte(v) return math.floor(v * 255 + 0.5) end
        return string.format("|cff%02x%02x%02x[商人增强]|r ", Byte(r), Byte(g), Byte(b))
    end

    -- EllesmereUIBags paints junk badges when it draws; redraw after our lists change
    function ns.RefreshEllesmereBags()
        local bags = _G.EUI_Bags
        if bags and bags.RefreshInventory and bags.IsShown and bags:IsShown() then
            bags:RefreshInventory()
        end
    end

    ---------------------------------------------------------------------------
    -- Selling
    ---------------------------------------------------------------------------

    -- Selling everything in one go can make the server drop some sales, so sell in
    -- small batches a moment apart (as Leatrix does) until nothing sellable is left.
    local ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR = 2, 4
    local BUYBACK_SLOTS = 12
    local SELL_INTERVAL, SELL_BATCH, SELL_MAX_TICKS = 0.2, 10, 100
    local LAST_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 4

    local sellRun  -- the selling run in progress, if any

    -- Vendor price if this item should be sold in `run`, else nil
    local function SellPrice(run, itemID, isBound)
        local DB = ns.DB
        local _, _, quality, _, _, _, _, _, _, _, price, classID = GetItemInfoSafe(itemID)
        if not price or price <= 0 then return end
        if run.sellAlways and DB.whitelist[itemID] then return price end
        if run.whitelistOnly or quality ~= 0 or DB.blacklist[itemID] then return end
        if run.keepGreyGear and not isBound
            and (classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR) then
            return
        end
        return price
    end

    -- `stopReason`: the vendor refused the sale. The run's totals only count attempts, so
    -- it reports the reason instead of claiming a sale.
    local function FinishSelling(stopReason)
        local run = sellRun
        if not run then return end
        sellRun = nil
        frame:UnregisterEvent("UI_ERROR_MESSAGE")
        if run.ticker then run.ticker:Cancel() end
        if stopReason then
            print(ns.ChatPrefix() .. "出售已停止，原因是" .. stopReason)
        elseif run.total > 0 then
            if ns.Get("printSummary") then
                local what = run.whitelistOnly and "必卖" or "垃圾"
                print(ns.ChatPrefix() .. string.format("已出售 %d 件%s物品，获得 %s。", run.sold, what, GetCoinTextureStringSafe(run.total)))
            end
        elseif not run.whitelistOnly and ns.Get("printNoJunk") then
            print(ns.ChatPrefix() .. "没有可出售的垃圾物品。")
        end
    end

    -- Sells up to SELL_BATCH items. Returns how many it sold and whether sales are still
    -- pending (locked items, or the batch filled up before the bags were fully scanned).
    local function SellBatch(run)
        local soldNow = 0
        for bag = 0, LAST_BAG do
            for slot = 1, GetContainerNumSlotsSafe(bag) or 0 do
                if run.sold >= run.limit then return soldNow, false end
                if soldNow >= SELL_BATCH then return soldNow, true end
                local itemID, count, isBound, isLocked = ReadBagSlot(bag, slot)
                local price = itemID and SellPrice(run, itemID, isBound)
                if price then
                    local key = bag * 1000 + slot
                    if isLocked then
                        run.pending = true  -- sale in flight, or the item is being moved
                    elseif run.attempted[key] ~= itemID then
                        -- Never retry the same item in the same slot: if the vendor refused it,
                        -- it would otherwise be "sold" again every batch
                        run.attempted[key] = itemID
                        UseContainerItemSafe(bag, slot)
                        run.sold = run.sold + 1
                        run.total = run.total + price * count
                        soldNow = soldNow + 1
                    end
                end
            end
        end
        return soldNow, run.pending
    end

    local function SellTick()
        local run = sellRun
        if not run then return end
        if not MerchantFrame:IsShown() then return FinishSelling() end
        run.pending = false
        run.ticks = run.ticks + 1
        local soldNow, pending = SellBatch(run)
        if (soldNow == 0 and not pending) or run.sold >= run.limit or run.ticks >= SELL_MAX_TICKS then
            FinishSelling()
        end
    end

    local function PerformSellJunk(whitelistOnly)
        if sellRun or not ns.DB then return end  -- already selling
        sellRun = {
            whitelistOnly = whitelistOnly,
            sellAlways = ns.Get("sellAlwaysList"),
            keepGreyGear = ns.Get("keepGreyGear"),
            limit = ns.Get("limit12") and BUYBACK_SLOTS or math.huge,
            sold = 0, total = 0, ticks = 0, attempted = {},
        }
        frame:RegisterEvent("UI_ERROR_MESSAGE")  -- the vendor can refuse; see the event handler
        SellTick()  -- first batch right away
        if sellRun then sellRun.ticker = C_Timer.NewTicker(SELL_INTERVAL, SellTick) end
    end

    ---------------------------------------------------------------------------
    -- Merchant window widgets
    ---------------------------------------------------------------------------

    -- EllesmereUI look for our parts of the merchant window (see ns.OnSkin): the search box,
    -- the header buttons and the grid slots past Blizzard's 12. Only while EllesmereUI also
    -- skins the merchant window: on Blizzard's stock window they'd stand out.
    -- The facade arrives at login, the header is built on the first vendor visit; each side
    -- calls SkinMerchantHeader, and it runs once both are there.
    local merchantSkin
    local SkinExtraSlots  -- defined with the grid layout below

    local function SkinHeaderButton(btn)
        if not btn then return end
        btn.border:SetAlpha(0)  -- the action-slot ring; SquareIcon draws a thin border instead
        local pushed = btn:GetPushedTexture()
        if pushed then pushed:SetAlpha(0) end
        merchantSkin.SquareIcon(btn.icon, btn)
    end

    local function SkinMerchantHeader()
        if not (merchantSkin and searchBox) then return end
        merchantSkin.EditBox(searchBox, { padInput = true })
        SkinHeaderButton(configBtn)
        SkinHeaderButton(optionsBtn)
        SkinHeaderButton(filterBtn)
    end

    ns.OnSkin(function(S)
        if not ns.EllesmereMerchantSkinOn() then return end
        merchantSkin = S
        SkinMerchantHeader()
        SkinExtraSlots()
    end)

    local function CreateHeaderButton(name, texture, tooltip, onClick)
        local btn = CreateFrame("Button", name, MerchantFrame)
        btn:SetSize(22, 22)
        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        icon:SetTexture(texture)
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        border:SetSize(37, 37)
        border:SetPoint("CENTER")
        btn.icon, btn.border = icon, border
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return btn
    end
    ns.CreateHeaderButton = CreateHeaderButton

    local function InitUI()
        if searchBox then return end

        -- Create Search Box
        searchBox = CreateFrame("EditBox", "BetterVendorUISearchBox", MerchantFrame, "SearchBoxTemplate")
        searchBox:SetSize(120, 20)
        searchBox:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -30, -32)
        searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnTextChanged", function(self)
            SearchBoxTemplate_OnTextChanged(self)
            local text = string.lower(self:GetText() or "")
            if text == searchString then return end
            MerchantFrame.page = 1
            ns.ResetListScroll()
            searchString = text
            MerchantFrame_Update()
        end)

        if MerchantSellAllJunkButton then
            origSellClick = MerchantSellAllJunkButton:GetScript("OnClick")
            MerchantSellAllJunkButton:SetScript("OnClick", function(self, ...)
                if ns.Get("overrideSellButton") or not origSellClick then
                    PerformSellJunk()
                else
                    origSellClick(self, ...)
                end
            end)
            -- Next to the search box: the bottom area is shared with the buyback item name,
            -- repair buttons and the sell junk button, so nothing there is reliably free.
            configBtn = CreateHeaderButton("BetterVendorUIConfigBtn", "Interface\\Icons\\INV_Misc_Note_02",
                "售卖名单", function() ns.ToggleConfig() end)
        end

        optionsBtn = CreateHeaderButton("BetterVendorUIOptionsBtn", "Interface\\Icons\\INV_Misc_Gear_01",
            "商人增强设置", function() ns.OpenSettings() end)
        filterBtn = ns.CreateFilterButton and ns.CreateFilterButton()
        SkinMerchantHeader()
    end

    -- Header buttons sit right to left from the search box: filter, lists, options.
    -- Hidden ones are skipped so the rest close up.
    local function LayoutHeaderButtons()
        local shown = {
            { filterBtn, ns.Get("showFilterButton") },
            { configBtn, ns.Get("showListsButton") },
            { optionsBtn, ns.Get("showOptionsButton") },
        }
        local prev, gap = searchBox, -10
        for _, entry in ipairs(shown) do
            local btn, show = entry[1], entry[2]
            if btn then
                btn:SetShown(show)
                if show then
                    btn:ClearAllPoints()
                    btn:SetPoint("RIGHT", prev, "LEFT", gap, 0)
                    prev, gap = btn, -8
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Grid layout
    ---------------------------------------------------------------------------

    -- Blizzard draws MERCHANT_ITEMS_PER_PAGE slots from frames MerchantItem1..N in a 2x5 grid.
    -- We raise that count, create the missing slot frames from Blizzard's template, lay them
    -- out in a columns x rows grid and resize MerchantFrame to fit.
    local BUYBACK_ITEMS = BUYBACK_ITEMS_PER_PAGE or 12
    local slots, itemButtons = {}, {}  -- MerchantItemN and MerchantItemNItemButton, by N
    local slotParts = {}  -- [N] = { name, nameFrame, money, altCurrency } regions of MerchantItemN
    local baseWidth, baseHeight, gapX, gapY
    local buybackAnchor   -- stands in for MerchantItem10 at its 2x5 position
    local anchoredCols    -- column count the slots are currently anchored for; nil = re-anchor
    local listMode = false  -- EllesmereUI's "Show As List" draws the items; our grid stands down

    local function GetSlotFrame(i)
        if not slots[i] then
            local name = "MerchantItem" .. i
            slots[i] = _G[name] or CreateFrame("Frame", name, MerchantFrame, "MerchantItemTemplate")
            itemButtons[i] = _G[name .. "ItemButton"]
            slotParts[i] = {
                name = _G[name .. "Name"],
                nameFrame = _G[name .. "NameFrame"],
                money = _G[name .. "MoneyFrame"],
                altCurrency = _G[name .. "AltCurrencyFrame"],
            }
        end
        return slots[i]
    end

    -- Bottom bar artwork: MerchantFrameBottomLeftBorder is one fixed-width texture holding both
    -- bottom boxes and the divider above them. To widen it without distorting the borders we
    -- 3-slice it: the original keeps everything up to inside the right box, a thin slice of
    -- that box's interior is stretched over the extra width, and its right border goes last.
    local BOTTOM_ART_CUT, BOTTOM_ART_SLICE = 310, 2  -- texture-local x of the slice, its width
    local bottomArt  -- { tex, mid, tail, width, left, right, top, bottom }

    local function SyncBottomArtShown()
        if bottomArt then
            -- Skins (EllesmereUI's) fade the original with SetAlpha instead of hiding it
            local shown, alpha = bottomArt.tex:IsShown(), bottomArt.tex:GetAlpha()
            bottomArt.mid:SetShown(shown)
            bottomArt.tail:SetShown(shown)
            bottomArt.mid:SetAlpha(alpha)
            bottomArt.tail:SetAlpha(alpha)
        end
    end

    local function StretchBottomArt(extra)
        local tex = MerchantFrameBottomLeftBorder
        if not tex then return end
        if not bottomArt then
            local width = tex:GetWidth()
            if not width or width <= BOTTOM_ART_CUT + BOTTOM_ART_SLICE then return end
            local ulx, uly, llx, lly, urx = tex:GetTexCoord()
            local layer, sublevel = tex:GetDrawLayer()
            local parent = tex:GetParent()
            bottomArt = {
                tex = tex, width = width, left = ulx, right = urx, top = uly, bottom = lly,
                mid = parent:CreateTexture(nil, layer, nil, sublevel),
                tail = parent:CreateTexture(nil, layer, nil, sublevel),
            }
            for _, piece in ipairs({ bottomArt.mid, bottomArt.tail }) do
                piece:SetTexture(tex:GetTexture())
                piece:SetHeight(tex:GetHeight())
            end
            -- Blizzard hides the bottom bar on the buyback tab; the extra pieces follow it
            hooksecurefunc(tex, "Show", SyncBottomArtShown)
            hooksecurefunc(tex, "Hide", SyncBottomArtShown)
            hooksecurefunc(tex, "SetShown", SyncBottomArtShown)
            hooksecurefunc(tex, "SetAlpha", SyncBottomArtShown)
        end
        local a = bottomArt
        local function U(x) return a.left + (a.right - a.left) * x / a.width end
        local cut, sliceEnd = BOTTOM_ART_CUT, BOTTOM_ART_CUT + BOTTOM_ART_SLICE

        a.tex:SetWidth(cut)
        a.tex:SetTexCoord(a.left, U(cut), a.top, a.bottom)
        a.mid:ClearAllPoints()
        a.mid:SetPoint("TOPLEFT", a.tex, "TOPRIGHT")
        a.mid:SetWidth(BOTTOM_ART_SLICE + math.max(0, extra))
        a.mid:SetTexCoord(U(cut), U(sliceEnd), a.top, a.bottom)
        a.tail:ClearAllPoints()
        a.tail:SetPoint("TOPLEFT", a.mid, "TOPRIGHT")
        a.tail:SetWidth(a.width - sliceEnd)
        a.tail:SetTexCoord(U(sliceEnd), a.right, a.top, a.bottom)
        SyncBottomArtShown()
    end

    -- Must run before the merchant is first shown: Blizzard indexes MerchantItem1..N directly.
    function ns.ApplyLayout()
        if not MerchantItem1 then return end
        if not baseWidth then
            -- Blizzard's own size and spacing, read before we change anything
            baseWidth, baseHeight = MerchantFrame:GetSize()
            gapX = select(4, MerchantItem2:GetPoint(1)) or 12
            gapY = select(5, MerchantItem3:GetPoint(1)) or -8
            local i = 1
            while _G["MerchantItem" .. i] do GetSlotFrame(i); i = i + 1 end
        end
        -- In EllesmereUI's list mode Blizzard's grid is hidden, so keep its 10 slots and the
        -- default width; Rows still makes the window (and so the list) taller
        listMode = ns.EllesmereListMode()
        local cols, rows = ns.Get("gridColumns"), ns.Get("gridRows")
        if listMode then cols = 2 end
        local perPage = listMode and 10 or cols * rows
        for i = 1, perPage do GetSlotFrame(i) end
        if MERCHANT_ITEMS_PER_PAGE ~= perPage then
            MERCHANT_ITEMS_PER_PAGE = perPage
            MerchantFrame.page = 1
            anchoredCols = nil  -- slots the grid just grew by have no anchors yet
        end
        if anchoredCols ~= cols then anchoredCols = nil end
        local itemWidth, itemHeight = MerchantItem1:GetSize()
        local extraWidth = (cols - 2) * (itemWidth + gapX)
        MerchantFrame:SetSize(baseWidth + extraWidth, baseHeight + (rows - 5) * (itemHeight - gapY))
        StretchBottomArt(extraWidth)

        -- Where MerchantItem10 would be in a 2-column grid of this height (right slot, last row)
        buybackAnchor = buybackAnchor or CreateFrame("Frame", nil, MerchantFrame)
        buybackAnchor:SetSize(itemWidth, itemHeight)
        buybackAnchor:ClearAllPoints()
        buybackAnchor:SetPoint("TOPLEFT", MerchantItem1, "TOPLEFT", itemWidth + gapX, -(rows - 1) * (itemHeight - gapY))
    end

    -- Bottom bar and paging. Blizzard places them for the default-width frame: the buyback item
    -- hangs off MerchantItem10 (bottom-right slot of 2x5), and buttons hang off whichever edge
    -- happened to be convenient. Each frame below gets pinned where it belongs in the wider
    -- frame: 0 = with the left edge, 0.5 = centred, 1 = with the right edge.
    local PINNED_FRAMES = {
        MerchantRepairAllButton = 0, MerchantGuildBankRepairButton = 0, MerchantRepairItemButton = 0,
        MerchantRepairText = 0, MerchantSellAllJunkButton = 0,
        MerchantNextPageButton = 1, MerchantPageText = 0.5,  -- Prev stays left by itself
    }
    local pinTarget  -- [region] = where it belongs (from PINNED_FRAMES)
    local pins = {}  -- [region] = { orig = points Blizzard set, applied = points we set, extra = shift used }

    -- How far an anchor on `rel`'s `relPoint` moves when the frame gets wider, as a share of
    -- the extra width: 1 on the right edge, 0.5 on the center, 0 if it stays put. Follows
    -- anchor chains a few levels deep. An anchor on another pinned frame moves wherever that
    -- frame gets pinned.
    local RegionFactor
    local function PointFactor(rel, relPoint, depth)
        if rel == MerchantFrame then
            return relPoint:find("RIGHT") and 1 or (relPoint:find("LEFT") and 0 or 0.5)
        elseif rel and pinTarget[rel] then
            return pinTarget[rel]
        elseif rel and rel ~= UIParent and rel.GetNumPoints then
            return RegionFactor(rel, depth + 1)
        end
        return 0
    end

    -- How far `region` as a whole moves: the most any of its anchors moves
    RegionFactor = function(region, depth)
        if depth > 5 then return 0 end
        local factor = 0
        for n = 1, region:GetNumPoints() do
            local _, rel, relPoint = region:GetPoint(n)
            factor = math.max(factor, PointFactor(rel or region:GetParent(), relPoint, depth))
        end
        return factor
    end

    local function GetPoints(region)
        local points = {}
        for n = 1, region:GetNumPoints() do points[n] = { region:GetPoint(n) } end
        return points
    end

    -- Whether `region` still has exactly the anchors we gave it (no table allocations)
    local function HasPoints(region, points)
        if region:GetNumPoints() ~= #points then return false end
        for n = 1, #points do
            local p = points[n]
            local point, rel, relPoint, x, y = region:GetPoint(n)
            if point ~= p[1] or rel ~= p[2] or relPoint ~= p[3] or x ~= p[4] or y ~= p[5] then
                return false
            end
        end
        return true
    end

    -- Same anchor points on the same frames as `points`, offsets aside
    local function SameAnchors(current, points)
        if #current ~= #points then return false end
        for n = 1, #points do
            local c, p = current[n], points[n]
            if c[1] ~= p[1] or c[2] ~= p[2] or c[3] ~= p[3] then return false end
        end
        return true
    end

    -- Moves each of `region`'s anchors by however much it is off from where the region is
    -- pinned, keeping what it's anchored to. Judged per anchor: a button can be anchored both
    -- to the right edge and to a left-side button, and only the first needs moving.
    -- Remembers Blizzard's anchors, so repeated calls never shift twice.
    local function ShiftRegion(region, extra)
        local target = pinTarget[region]
        local pin = pins[region]
        local orig
        if pin and HasPoints(region, pin.applied) then
            if pin.extra == extra then return end
            orig = pin.orig  -- layout changed: redo the shift from Blizzard's anchors
        else
            orig = GetPoints(region)  -- new anchors from Blizzard...
            if pin and SameAnchors(orig, pin.applied) and not HasPoints(region, pin.orig) then
                -- ...unless another addon only nudged ours (EllesmereUI's skin moves the page
                -- buttons a few pixels from where they are). Keep the nudge, drop our shift,
                -- or the next pass would shift a second time.
                for n, p in ipairs(orig) do
                    p[4] = p[4] - (pin.applied[n][4] - pin.orig[n][4])
                    p[5] = p[5] - (pin.applied[n][5] - pin.orig[n][5])
                end
            end
        end
        region:ClearAllPoints()
        for _, p in ipairs(orig) do region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        if extra ~= 0 and RegionFactor(region, 0) ~= target then
            region:ClearAllPoints()
            for _, p in ipairs(orig) do
                local factor = PointFactor(p[2] or region:GetParent(), p[3], 0)
                region:SetPoint(p[1], p[2], p[3], p[4] + extra * (target - factor), p[5])
            end
        end
        pins[region] = { orig = orig, applied = GetPoints(region), extra = extra }
    end

    local function PinBottomBar()
        if not baseWidth then return end
        if not pinTarget then
            pinTarget = {}
            for name, target in pairs(PINNED_FRAMES) do
                if _G[name] then pinTarget[_G[name]] = target end
            end
        end
        if buybackAnchor and MerchantBuyBackItem then
            for n = 1, MerchantBuyBackItem:GetNumPoints() do
                local point, rel, relPoint, x, y = MerchantBuyBackItem:GetPoint(n)
                if rel == MerchantItem10 then
                    MerchantBuyBackItem:SetPoint(point, buybackAnchor, relPoint, x, y)
                end
            end
        end
        local extra = MerchantFrame:GetWidth() - baseWidth
        for region in pairs(pinTarget) do ShiftRegion(region, extra) end
    end

    -- The slot that slot `i` hangs off in a grid of `cols` columns
    local function GridAnchor(i, cols)
        if (i - 1) % cols == 0 then return slots[i - cols], "BOTTOMLEFT", 0, gapY end
        return slots[i - 1], "TOPRIGHT", gapX, 0
    end

    -- Blizzard re-anchors some slots for its own layouts; spot-check a few of them
    local function SlotsStillAnchored(cols)
        for i = 3, math.min(11, MERCHANT_ITEMS_PER_PAGE), 2 do
            local _, rel = slots[i]:GetPoint(1)
            if rel ~= (GridAnchor(i, cols)) then return false end
        end
        return true
    end

    -- EllesmereUI list mode: filters and search on its rows.
    -- Its update (one frame after MerchantFrame_Update) walks the rows in order and Show()s
    -- each one with an item. A hook on Show hides rows that fail our filters or search right
    -- away, and anchors the rest under the nearest visible row above, so no gaps are left.
    -- Row N always shows vendor item N.
    local LIST_ROW_SPACING = 4  -- EllesmereUI's rowSpacing

    -- Whether list row `index` is shown, and its alpha (search in dim mode fades it)
    local function ListRowState(index)
        if MerchantFrame.selectedTab ~= 1 then return true, 1 end  -- buyback: untouched
        if ns.FiltersActive() and not ns.PassesFilters(index) then return false end
        if searchString ~= "" and not ns.MatchesSearch(index, searchString) then
            if ns.Get("searchMode") == "hide" then return false end
            return true, ns.Get("dimAlpha")
        end
        return true, 1
    end

    local function OnListRowShown(row)
        if not listMode then return end
        local visible, alpha = ListRowState(row.betterVendorUIIndex)
        if not visible then
            row.betterVendorUIHidden = true
            row:Hide()
            return
        end
        row.betterVendorUIHidden = nil
        row:SetAlpha(alpha)
        local sf = _G.WSkinMerchantScrollFrame
        local prev
        for j = row.betterVendorUIIndex - 1, 1, -1 do
            local r = sf.rows[j]
            if r and r:IsShown() then prev = r; break end
        end
        row:ClearAllPoints()
        if prev then
            row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -LIST_ROW_SPACING)
        else
            row:SetPoint("TOPLEFT", sf:GetScrollChild(), "TOPLEFT", 0, 0)
        end
    end

    -- Full pass: hooks rows EllesmereUI created since the last pass (their first Show came
    -- before we could hook them), and re-applies the filters to every row
    local function RelayoutList()
        local sf = _G.WSkinMerchantScrollFrame
        if not listMode or not sf or not sf.rows then return end
        local numItems = MerchantFrame.selectedTab == 1 and (GetMerchantNumItemsSafe() or 0)
            or (GetNumBuybackItems and GetNumBuybackItems() or 0)
        if MerchantFrame.selectedTab == 1 then ns.CheckItemCache(numItems) end
        for i, row in ipairs(sf.rows) do
            if not row.betterVendorUIIndex then
                row.betterVendorUIIndex = i
                hooksecurefunc(row, "Show", OnListRowShown)
            end
            if row:IsShown() then
                OnListRowShown(row)
            elseif row.betterVendorUIHidden and i <= numItems and ListRowState(i) then
                row:Show()  -- passes again: the hook anchors it
            end
        end
    end

    -- After EllesmereUI's own update, which runs one frame after MerchantFrame_Update
    local listRelayoutPending = false
    local function ScheduleListRelayout()
        if listRelayoutPending then return end
        listRelayoutPending = true
        C_Timer.After(0, function()
            C_Timer.After(0, function()
                listRelayoutPending = false
                RelayoutList()
            end)
        end)
    end

    -- Filters or search changed: start the list from the top
    function ns.ResetListScroll()
        local sf = _G.WSkinMerchantScrollFrame
        if listMode and sf then sf:SetVerticalScroll(0) end
    end

    -- EllesmereUI's merchant skin restyles Blizzard's 12 tiles only; give every slot past
    -- them (as many as the grid has) the same treatment through the public API, mirroring
    -- its tile skin: Blizzard art faded, flat panel with border, squared icon centred on the
    -- row's height, price 6px higher.
    local FIRST_EXTRA_SLOT = 13
    local slotArt = {}  -- [slot] = Blizzard's texture regions, kept faded on every update

    -- Blizzard re-anchors price frames on every update; lift each one right after
    local function LiftCurrency(frame)
        if not frame or frame.betterVendorUILifted then return end
        frame.betterVendorUILifted = true
        local applying = false
        local function Apply()
            if applying or frame:GetNumPoints() == 0 then return end
            local points = {}
            for n = 1, frame:GetNumPoints() do
                local p, rel, relPoint, x, y = frame:GetPoint(n)
                points[n] = { p, rel, relPoint, x or 0, (y or 0) + 6 }
            end
            applying = true  -- our own SetPoint calls below fire this hook again
            frame:ClearAllPoints()
            for _, p in ipairs(points) do frame:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            applying = false
        end
        hooksecurefunc(frame, "SetPoint", Apply)
        Apply()
    end

    local function SkinExtraSlot(slot)
        if slotArt[slot] then return end
        local art = {}
        for _, region in ipairs({ slot:GetRegions() }) do
            if region:IsObjectType("Texture") then table.insert(art, region) end
        end
        slotArt[slot] = art  -- taken before Panel adds its own textures
        merchantSkin.Panel(slot)
        local name = slot:GetName()
        local nameText = slot.Name or _G[name .. "Name"]
        if nameText then
            nameText:SetWordWrap(true)
            if nameText.SetMaxLines then nameText:SetMaxLines(2) end
        end
        local btn = slot.ItemButton or _G[name .. "ItemButton"]
        if btn then
            local icon = btn.icon or btn.Icon or _G[name .. "ItemButtonIconTexture"]
            if icon then merchantSkin.SquareIcon(icon, btn) end
            local normal = btn:GetNormalTexture()
            if normal then normal:SetAlpha(0) end
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", slot, "LEFT", 0, 0)
        end
        LiftCurrency(_G[name .. "MoneyFrame"])
        LiftCurrency(_G[name .. "AltCurrencyFrame"])
    end

    SkinExtraSlots = function()
        if not merchantSkin or listMode then return end
        for i = FIRST_EXTRA_SLOT, #slots do
            SkinExtraSlot(slots[i])
            -- Blizzard repaints slot art on page flips; keep it faded
            for _, region in ipairs(slotArt[slots[i]]) do region:SetAlpha(0) end
        end
    end

    local function LayoutMerchantSlots()
        if listMode then
            -- Blizzard's slots 1-12 are hidden by EllesmereUI; hide our extra ones too
            for i = 13, #slots do slots[i]:Hide() end
            PinBottomBar()
            SyncBottomArtShown()
            return
        end
        SkinExtraSlots()  -- also catches slots the grid just grew by
        local cols = ns.Get("gridColumns")
        if anchoredCols ~= cols or not SlotsStillAnchored(cols) then
            for i = 2, MERCHANT_ITEMS_PER_PAGE do
                local rel, relPoint, x, y = GridAnchor(i, cols)
                slots[i]:ClearAllPoints()
                slots[i]:SetPoint("TOPLEFT", rel, relPoint, x, y)
            end
            anchoredCols = cols
        end
        for i = 1, #slots do
            slots[i]:SetShown(i <= MERCHANT_ITEMS_PER_PAGE)
        end
        PinBottomBar()
        SyncBottomArtShown()
    end

    -- Buyback's 12 slots. Blizzard only re-anchors some of them for its own layout and the rest
    -- keep our merchant grid anchors, so lay out all 12 here: across the full width in the
    -- merchant grid's columns, or in Blizzard's 2 columns.
    local function LayoutBuybackSlots()
        if listMode then
            for i = 13, #slots do slots[i]:Hide() end
            SyncBottomArtShown()
            return
        end
        if ns.Get("buybackFullWidth") then
            local cols = ns.Get("gridColumns")
            for i = 2, BUYBACK_ITEMS do
                local rel, relPoint, x, y = GridAnchor(i, cols)
                slots[i]:ClearAllPoints()
                slots[i]:SetPoint("TOPLEFT", rel, relPoint, x, y)
            end
            -- Same anchors as the merchant grid for these slots; the spot-check in
            -- LayoutMerchantSlots catches any Blizzard moved back
        else
            -- Blizzard's buyback row spacing is on slot 3 (under slot 1) after its update
            local _, rel, _, _, y = MerchantItem3:GetPoint(1)
            local rowGap = (rel == MerchantItem1 and y) or -15
            for i = 2, BUYBACK_ITEMS do
                local slot = slots[i]
                slot:ClearAllPoints()
                if i % 2 == 0 then
                    slot:SetPoint("TOPLEFT", slots[i - 1], "TOPRIGHT", gapX or 12, 0)
                else
                    slot:SetPoint("TOPLEFT", slots[i - 2], "BOTTOMLEFT", 0, rowGap)
                end
            end
            anchoredCols = nil  -- merchant grid must be rebuilt when switching back
        end
        for i = 1, #slots do
            slots[i]:SetShown(i <= BUYBACK_ITEMS)
        end
        SyncBottomArtShown()
    end

    ---------------------------------------------------------------------------
    -- Settings
    ---------------------------------------------------------------------------

    -- Re-apply settings that have a visible effect. `key` is the setting that changed
    -- (nil = all of them); `skipRedraw` when the caller knows a redraw is coming anyway.
    function ns.ApplySettings(key, skipRedraw)
        ns.ApplyLayout()
        if searchBox then
            local show = ns.Get("showSearch")
            searchBox:SetShown(show)
            if not show and searchBox:GetText() ~= "" then searchBox:SetText("") end
        end
        if searchBox then LayoutHeaderButtons() end
        if ns.UpdateFilterUI then ns.UpdateFilterUI() end
        if key == nil or key:find("^leatrix") then ns.SyncLeatrix() end
        if key == nil or key:find("^ellesmere") or key == "sellAlwaysList" then ns.RefreshEllesmereBags() end
        if not skipRedraw and not NO_REDRAW[key] and MerchantFrame and MerchantFrame:IsShown() then
            MerchantFrame_Update()
        end
    end

    ---------------------------------------------------------------------------
    -- Search and item visuals
    ---------------------------------------------------------------------------

    local function ResetItemButton(merchantButton, itemButton)
        merchantButton:SetAlpha(1.0)
        itemButton:EnableMouse(true)
    end

    -- At alpha 0 the item is invisible, so it mustn't be clickable either (no blind purchases).
    -- ResetItemButton undoes this on the next update.
    local function DimSlot(i, alpha)
        slots[i]:SetAlpha(alpha)
        if alpha <= 0 then itemButtons[i]:EnableMouse(false) end
    end

    local function Call(fnName, ...)
        local fn = _G[fnName]
        if fn then return fn(...) end
    end

    local function ItemMatches(index)
        return searchString == "" or ns.MatchesSearch(index, searchString)
    end

    local MAX_MONEY_DISPLAY_WIDTH = 120  -- a local in Blizzard's MerchantFrame.lua

    -- Draws vendor item `index` into slot `i`, mirroring Blizzard's MerchantFrame_UpdateMerchantInfo.
    -- Clicks, tooltips and buying all read itemButton:GetID(), so they follow the new index.
    local function FillSlot(i, index)
        local itemButton = itemButtons[i]
        local merchantButton = slots[i]
        local parts = slotParts[i]
        local money, altCurrency = parts.money, parts.altCurrency
        local name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, extendedCost = GetMerchantItemInfoSafe(index)
        local canAfford = CanAffordMerchantItem and CanAffordMerchantItem(index)

        parts.name:SetText(name)
        Call("SetItemButtonCount", itemButton, stackCount)
        Call("SetItemButtonStock", itemButton, numAvailable)
        Call("SetItemButtonTexture", itemButton, texture)

        itemButton.name = name
        itemButton.link = GetMerchantItemLinkSafe(index)
        itemButton.texture = texture
        itemButton.extendedCost = extendedCost or nil
        itemButton.price = (price and price > 0) and price or nil
        -- This slot may have held another item a moment ago: buying reads this flag
        if C_MerchantFrame and C_MerchantFrame.IsMerchantItemRefundable then
            itemButton.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(index)
        end
        Call("MerchantFrameItem_UpdateQuality", merchantButton, itemButton.link)  -- name color

        -- Only the table API has this flag. The item button is what Blizzard's update left
        -- for the slot's unfiltered item, so always set it.
        local questTexture = itemButton.IconQuestTexture
        if questTexture then
            local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(index)
            if info and info.isQuestStartItem then
                questTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
                questTexture:Show()
            else
                questTexture:Hide()
            end
        end

        local showMoney = not extendedCost or (price and price > 0)
        local altCurrencyWidth = 0
        if extendedCost and MerchantFrame_UpdateAltCurrency and altCurrency then
            altCurrencyWidth = MerchantFrame_UpdateAltCurrency(index, i, canAfford) or 0
            -- Blizzard's two layouts: after the money, or alone on the money's line
            altCurrency:ClearAllPoints()
            if showMoney and money then
                altCurrency:SetPoint("LEFT", money, "RIGHT", -14, 0)
            elseif parts.nameFrame then
                altCurrency:SetPoint("BOTTOMLEFT", parts.nameFrame, "BOTTOMLEFT", 0, 31)
            end
            altCurrency:Show()
        elseif altCurrency then
            altCurrency:Hide()
        end
        if money then
            if showMoney then
                -- Replaces the limit left by the slot's unfiltered item, which would cut off
                -- this price's silver and copper
                Call("MoneyFrame_SetMaxDisplayWidth", money, MAX_MONEY_DISPLAY_WIDTH - altCurrencyWidth)
                MoneyFrame_Update(money:GetName(), price or 0)
                Call("SetMoneyFrameColor", money:GetName(), canAfford == false and "gray" or nil)
                money:Show()
            else
                money:Hide()
            end
        end

        itemButton.hasItem = true
        itemButton:SetID(index)
        itemButton:Show()

        local itemID = GetMerchantItemID and GetMerchantItemID(index)
        local isHeirloom = itemID and C_Heirloom and C_Heirloom.IsItemHeirloom(itemID)
        local isKnownHeirloom = isHeirloom and C_Heirloom.PlayerHasHeirloom(itemID)
        local tintRed = not isPurchasable or (not isUsable and not isHeirloom)
        Call("SetItemButtonDesaturated", itemButton, isKnownHeirloom)

        local r, g, b
        if numAvailable == 0 or isKnownHeirloom then
            if tintRed then r, g, b = 0.5, 0, 0 else r, g, b = 0.5, 0.5, 0.5 end
            Call("SetItemButtonNameFrameVertexColor", merchantButton, r, g, b)
            Call("SetItemButtonSlotVertexColor", merchantButton, r, g, b)
        elseif tintRed then
            r, g, b = 1, 0, 0
            Call("SetItemButtonNameFrameVertexColor", merchantButton, r, g, b)
            Call("SetItemButtonSlotVertexColor", merchantButton, r, g, b)
            r = 0.9  -- Blizzard tints the icon slightly darker than the slot
        else
            r, g, b = 1, 1, 1
            Call("SetItemButtonNameFrameVertexColor", merchantButton, 0.5, 0.5, 0.5)
            Call("SetItemButtonSlotVertexColor", merchantButton, 1, 1, 1)
        end
        Call("SetItemButtonTextureVertexColor", itemButton, r, g, b)
        Call("SetItemButtonNormalTextureVertexColor", itemButton, r, g, b)
    end

    -- Empty slot, as Blizzard draws slots past the last item.
    local function ClearSlot(i)
        local itemButton = itemButtons[i]
        local merchantButton = slots[i]
        itemButton.price, itemButton.hasItem, itemButton.name, itemButton.link = nil, nil, nil, nil
        itemButton:Hide()
        Call("SetItemButtonNameFrameVertexColor", merchantButton, 0.5, 0.5, 0.5)
        Call("SetItemButtonSlotVertexColor", merchantButton, 0.4, 0.4, 0.4)
        local parts = slotParts[i]
        parts.name:SetText("")
        if parts.money then parts.money:Hide() end
        if parts.altCurrency then parts.altCurrency:Hide() end
    end

    local function UpdatePaging(page, numPages)
        local show = numPages > 1
        MerchantPageText:SetShown(show)
        MerchantPrevPageButton:SetShown(show)
        MerchantNextPageButton:SetShown(show)
        if show then
            MerchantPageText:SetFormattedText(MERCHANT_PAGE_NUMBER, page, numPages)
            MerchantPrevPageButton:SetEnabled(page > 1)
            MerchantNextPageButton:SetEnabled(page < numPages)
        end
    end

    local matches = {}  -- reused by every redraw

    local function ApplyItemVisuals()
        if MerchantFrame.selectedTab ~= 1 or listMode then return end  -- list mode: RelayoutList

        local numMerchantItems = GetMerchantNumItemsSafe()
        if not numMerchantItems then return end
        ns.CheckItemCache(numMerchantItems)

        local perPage = MERCHANT_ITEMS_PER_PAGE
        local borders = ns.Get("qualityBorders")
        local minQuality = ns.Get("minBorderQuality")
        local searching = searchString ~= ""
        local hideSearch = searching and ns.Get("searchMode") == "hide"
        local filtering = ns.FiltersActive()

        if filtering or hideSearch then
            -- Pack the remaining items into the slots and page through them only.
            -- Filters always remove items; search does too in hide mode.
            wipe(matches)
            for index = 1, numMerchantItems do
                if (not filtering or ns.PassesFilters(index)) and (not hideSearch or ItemMatches(index)) then
                    table.insert(matches, index)
                end
            end
            local numPages = math.max(1, math.ceil(#matches / perPage))
            if MerchantFrame.page > numPages then MerchantFrame.page = numPages end
            local dimAlpha = ns.Get("dimAlpha")
            for i = 1, perPage do
                ResetItemButton(slots[i], itemButtons[i])
                local index = matches[(MerchantFrame.page - 1) * perPage + i]
                if index then
                    FillSlot(i, index)
                    -- Search in dim mode still dims within the filtered items
                    if searching and not hideSearch and not ItemMatches(index) then
                        DimSlot(i, dimAlpha)
                    end
                else
                    ClearSlot(i)
                end
            end
            UpdatePaging(MerchantFrame.page, numPages)
        else
            -- Dim mode: items stay in place, non-matches are faded
            local dimAlpha = ns.Get("dimAlpha")
            for i = 1, perPage do
                local index = (MerchantFrame.page - 1) * perPage + i
                ResetItemButton(slots[i], itemButtons[i])
                if index <= numMerchantItems and not ItemMatches(index) then
                    DimSlot(i, dimAlpha)
                end
            end
        end

        -- Quality Borders
        for i = 1, perPage do
            local itemButton = itemButtons[i]
            if itemButton.IconBorder then
                local quality = itemButton:IsShown() and itemButton.link and select(3, GetItemInfoSafe(itemButton.link))
                if borders and quality and quality >= minQuality then
                    local r, g, b = GetItemQualityColorSafe(quality)
                    itemButton.IconBorder:SetVertexColor(r, g, b)
                    itemButton.IconBorder:Show()
                else
                    itemButton.IconBorder:Hide()
                end
            end
        end
    end

    -- The buyback tab reuses the same item buttons, so undo search dimming/hiding there.
    local function ResetBuybackVisuals()
        LayoutBuybackSlots()
        for i = 1, BUYBACK_ITEMS do
            ResetItemButton(slots[i], itemButtons[i])
        end
    end

    -- baseWidth is only set once ApplyLayout found Blizzard's slot frames
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
        if not baseWidth then return end
        LayoutMerchantSlots()
        ApplyItemVisuals()
    end)
    if MerchantFrame_UpdateBuybackInfo then
        hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function()
            if baseWidth then ResetBuybackVisuals() end
        end)
    end
    if MerchantFrame_UpdateRepairButtons then
        hooksecurefunc("MerchantFrame_UpdateRepairButtons", PinBottomBar)
    end
    -- When a vendor item finishes loading, Blizzard recolors every slot by its unfiltered item
    -- and restores its own borders. Redo ours: filtered slots show other items, and the
    -- quality border settings apply. ApplyItemVisuals ignores the buyback tab.
    if MerchantFrame_UpdateItemQualityBorders then
        hooksecurefunc("MerchantFrame_UpdateItemQualityBorders", function()
            if baseWidth then ApplyItemVisuals() end
        end)
    end
    hooksecurefunc("MerchantFrame_Update", function()
        if listMode then ScheduleListRelayout() end
        if MerchantSellAllJunkButton and ns.Get("keepSellButtonEnabled") then
            MerchantSellAllJunkButton:Enable()
            if MerchantSellAllJunkButton.Icon then MerchantSellAllJunkButton.Icon:SetDesaturated(false) end
        end
    end)

    ---------------------------------------------------------------------------
    -- Events
    ---------------------------------------------------------------------------

    local listRefreshPending = false

    frame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if event == "MERCHANT_SHOW" then
            InitUI()
            ns.ResetItemCache()
            -- Blizzard redraws the merchant window itself when it opens
            ns.ApplySettings(nil, true)
            if ns.Get("resetFiltersOnShow") and ns.ResetFilters(true) and MerchantFrame:IsShown() then
                MerchantFrame_Update()  -- Blizzard may have drawn with the old filters already
            end
            if ns.Get("clearSearchOnShow") and searchBox:GetText() ~= "" then
                searchBox:SetText("")  -- redraws via OnTextChanged
            end
            HookEllesmere()  -- in case EllesmereUIBags loaded after login
            if IsShiftKeyDown() then return end
            local alwaysOn = ns.Get("sellAlwaysList")
            local _, ellesmereAutoSell, ellesmereMarker = ns.EllesmereInfo()
            if GetLeatrixExcludeBox() then
                -- Leatrix sells greys on a short timer after MERCHANT_SHOW; ApplySettings above
                -- already synced its exclusions. We sell the always-sell items ourselves.
                if ns.Get("leatrixSellAlwaysList") and alwaysOn then
                    PerformSellJunk(true)
                end
            elseif ellesmereAutoSell then
                -- With the Junk Marker, EllesmereUI sells our always-sell items itself (IsJunk
                -- hook). Without it, it only sells greys, so we sell the always-sell items.
                if not ellesmereMarker and ns.Get("ellesmereAlwaysSell") and alwaysOn then
                    PerformSellJunk(true)
                end
            elseif ns.Get("autoSell") then
                PerformSellJunk()
            end
        elseif event == "PLAYER_LOGIN" then
            HookEllesmere()
            -- EllesmereUI's settings are only loaded now. Runs before its merchant skin is
            -- built (we registered PLAYER_LOGIN first), so its list gets the right size.
            ns.ApplyLayout()
        elseif event == "MERCHANT_CLOSED" then
            FinishSelling()
            -- Blizzard draws the next vendor before our MERCHANT_SHOW runs: don't let that
            -- draw read this vendor's items
            ns.ResetItemCache()
        elseif event == "UI_ERROR_MESSAGE" then  -- registered only while selling
            if arg2 and (arg2 == ERR_VENDOR_DOESNT_BUY or arg2 == ERR_TOO_MUCH_GOLD) then
                FinishSelling(arg2)
            end
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            ns.OnItemInfoReceived(arg1)  -- vendor items waiting for their quality
            -- An item on one of our lists finished loading: refresh the lists window and
            -- Leatrix sync. Batched, since many of these can arrive at once.
            local DB = ns.DB
            if DB and arg1 and (DB.whitelist[arg1] or DB.blacklist[arg1]) and not listRefreshPending then
                listRefreshPending = true
                C_Timer.After(0.2, function()
                    listRefreshPending = false
                    ns.UpdateConfigLists()
                end)
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Slash commands
    ---------------------------------------------------------------------------

    local function ParseItemID(arg)
        return tonumber(arg:match('item:(%d+)') or arg)
    end

    SLASH_BETTERVENDOR1 = '/bvu'
    SlashCmdList['BETTERVENDOR'] = function(msg)
        local cmd, arg = strsplit(' ', strtrim(msg or ''), 2)
        local DB = ns.DB
        if cmd == '' then
            ns.OpenSettings()
            return
        elseif cmd == 'lists' then
            ns.ToggleConfig()
            return
        elseif cmd == 'debug' and arg == 'bottom' then
            -- Everything below the item grid: the boxes, borders and backgrounds of the bottom
            -- bar, with positions relative to the merchant window's bottom-left corner
            if not MerchantFrame:IsShown() then return print("|cff00ff00[商人增强]|r 请先打开商人窗口。") end
            local fl, fb = MerchantFrame:GetLeft(), MerchantFrame:GetBottom()
            local gridBottom = slots[MERCHANT_ITEMS_PER_PAGE]:GetBottom()
            local ours = {}
            for _, s in ipairs(slots) do ours[s] = true end
            local seen = 0
            local function Report(r)
                if ours[r] or not r:IsShown() or r:GetObjectType() == "FontString" then return end
                local left, right, bottom, top = r:GetLeft(), r:GetRight(), r:GetBottom(), r:GetTop()
                if not left or bottom > gridBottom then return end
                seen = seen + 1
                local name = (r.GetDebugName and r:GetDebugName()) or r:GetName() or "?"
                local p, rel, rp, x, y = r:GetPoint(1)
                local relName = rel and ((rel.GetDebugName and rel:GetDebugName()) or rel:GetName()) or "-"
                print(string.format("%s %s x%.0f-%.0f y%.0f-%.0f | %d 个锚点 %s %s %s %.0f,%.0f",
                    name, r:GetObjectType(), left - fl, right - fl, bottom - fb, top - fb,
                    r:GetNumPoints(), tostring(p), relName, tostring(rp), x or 0, y or 0))
            end
            for _, r in ipairs({ MerchantFrame:GetRegions() }) do Report(r) end
            for _, child in ipairs({ MerchantFrame:GetChildren() }) do
                Report(child)
                for _, r in ipairs({ child:GetRegions() }) do Report(r) end
            end
            print(string.format("|cff00ff00[商人增强]|r %d 个元素位于 y%.0f 以下（宽度 %.0f，基础宽度 %.0f）",
                seen, gridBottom - fb, MerchantFrame:GetWidth(), baseWidth))
            return
        elseif cmd == 'debug' then
            -- Where the bottom bar buttons are, for tracking down layout problems
            local function Num(v) return v and string.format("%.0f", v) or "nil" end
            print(string.format("|cff00ff00[商人增强]|r 商人窗口左侧 %s，底部 %s，宽度 %s（基础宽度 %s）",
                Num(MerchantFrame:GetLeft()), Num(MerchantFrame:GetBottom()), Num(MerchantFrame:GetWidth()), Num(baseWidth)))
            for _, name in ipairs({ "MerchantSellAllJunkButton", "MerchantBuyBackItem", "MerchantRepairAllButton" }) do
                local b = _G[name]
                if b then
                    print(string.format("%s 显示状态 %s | 位置 %s,%s | 不透明度 %.1f 层级 %d | %d 个锚点",
                        name, tostring(b:IsShown()), Num(b:GetLeft()), Num(b:GetBottom()),
                        b:GetAlpha(), b:GetFrameLevel(), b:GetNumPoints()))
                    for n = 1, b:GetNumPoints() do
                        local p, r, rp, x, y = b:GetPoint(n)
                        print(string.format("   %s 对齐 %s %s %s,%s", tostring(p),
                            r and (r:GetName() or "未命名") or "nil", tostring(rp), Num(x), Num(y)))
                    end
                end
            end
            return
        elseif cmd == 'wl' and arg then
            local id = ParseItemID(arg)
            if not id then return end
            DB.whitelist[id] = not DB.whitelist[id] or nil
            if DB.whitelist[id] then DB.blacklist[id] = nil end
            print(ns.ChatPrefix() .. "已切换物品的必卖状态，物品 ID 为 " .. id .. ' -> ' .. (DB.whitelist[id] and "已开启" or "已关闭"))
        elseif cmd == 'bl' and arg then
            local id = ParseItemID(arg)
            if not id then return end
            DB.blacklist[id] = not DB.blacklist[id] or nil
            if DB.blacklist[id] then DB.whitelist[id] = nil end
            print(ns.ChatPrefix() .. "已切换物品的禁卖状态，物品 ID 为 " .. id .. ' -> ' .. (DB.blacklist[id] and "已开启" or "已关闭"))
        else
            print(ns.ChatPrefix() .. "用法 /bvu（设置）| /bvu lists（售卖名单）| /bvu wl [物品链接或ID]（切换必卖）| /bvu bl [物品链接或ID]（切换禁卖）")
            return
        end
        ns.UpdateConfigLists()
    end

    ---------------------------------------------------------------------------
    -- Learned recipe markers
    ---------------------------------------------------------------------------

    local knownRecipeCache, recipeDataRequests = {}, {}
    local recipeTooltip

    local function RequestRecipeData(link)
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID and recipeDataRequests[itemID] == nil then
            recipeDataRequests[itemID] = true
            ns.RequestItem(itemID)
        end
    end

    local function IsKnownRecipe(link)
        if knownRecipeCache[link] ~= nil then return knownRecipeCache[link] end
        local name, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfoSafe(link)
        if not name or not classID then
            RequestRecipeData(link)
            return
        end
        if classID ~= 9 then
            knownRecipeCache[link] = false
            return false
        end

        recipeTooltip = recipeTooltip or CreateFrame("GameTooltip", "BetterVendorUIRecipeTooltip", UIParent, "GameTooltipTemplate")
        recipeTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        recipeTooltip:ClearLines()
        recipeTooltip:SetHyperlink(link)
        local numLines = recipeTooltip:NumLines()
        local complete, known = numLines > 1, false
        for i = 1, numLines do
            local line = _G["BetterVendorUIRecipeTooltipTextLeft" .. i]
            local text = line and line:GetText()
            if text == RETRIEVING_ITEM_INFO then complete = false end
            if text and text:find(ITEM_SPELL_KNOWN, 1, true) then known = true end
        end
        recipeTooltip:Hide()
        if complete then
            knownRecipeCache[link] = known
        else
            RequestRecipeData(link)
        end
        return known
    end

    local function UpdateKnownRecipeMarkers()
        local buying = ns.Get("knownRecipes") and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1 and not listMode
        for i, itemButton in pairs(itemButtons) do
            local icon = itemButton.icon or itemButton.Icon or _G[itemButton:GetName() .. "IconTexture"]
            local known = buying and i <= MERCHANT_ITEMS_PER_PAGE and itemButton:IsShown()
                and itemButton.link and icon and IsKnownRecipe(itemButton.link)
            local marker = itemButton.betterVendorUIKnownRecipe
            if known then
                if not marker then
                    marker = {
                        gray = itemButton:CreateTexture(nil, "OVERLAY", nil, 1),
                        check = itemButton:CreateTexture(nil, "OVERLAY", nil, 2),
                    }
                    marker.gray:SetAllPoints(icon)
                    marker.gray:SetDesaturated(true)
                    marker.check:SetTexture(136814)
                    marker.check:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 4, -4)
                    marker.check:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT", -4, 4)
                    itemButton.betterVendorUIKnownRecipe = marker
                end
                -- Copy the icon after the vendor has finished drawing this slot.
                marker.gray:SetTexture(icon:GetTexture())
                marker.gray:SetTexCoord(icon:GetTexCoord())
                marker.gray:SetVertexColor(icon:GetVertexColor())
                marker.gray:SetAlpha(icon:GetAlpha())
            end
            if marker then
                marker.gray:SetShown(known == true)
                marker.check:SetShown(known == true)
            end
        end
    end

    local recipeRefreshPending = false
    local function ScheduleRecipeRefresh()
        if recipeRefreshPending then return end
        recipeRefreshPending = true
        C_Timer.After(0, function()
            recipeRefreshPending = false
            if MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1 then
                MerchantFrame_Update()
            end
        end)
    end

    -- These hooks run after the vendor's own filtering and item remapping.
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateKnownRecipeMarkers)
    if MerchantFrame_UpdateItemQualityBorders then
        hooksecurefunc("MerchantFrame_UpdateItemQualityBorders", UpdateKnownRecipeMarkers)
    end
    if MerchantFrame_UpdateBuybackInfo then
        hooksecurefunc("MerchantFrame_UpdateBuybackInfo", UpdateKnownRecipeMarkers)
    end
    frame:HookScript("OnEvent", function(self, event, itemID)
        if event == "MERCHANT_SHOW" then
            wipe(knownRecipeCache)
            wipe(recipeDataRequests)
            self:RegisterEvent("NEW_RECIPE_LEARNED")
            self:RegisterEvent("SKILL_LINES_CHANGED")
            self:RegisterEvent("SPELLS_CHANGED")
            ScheduleRecipeRefresh()
        elseif event == "MERCHANT_CLOSED" then
            self:UnregisterEvent("NEW_RECIPE_LEARNED")
            self:UnregisterEvent("SKILL_LINES_CHANGED")
            self:UnregisterEvent("SPELLS_CHANGED")
            wipe(knownRecipeCache)
            wipe(recipeDataRequests)
            for _, itemButton in pairs(itemButtons) do
                local marker = itemButton.betterVendorUIKnownRecipe
                if marker then
                    marker.gray:Hide()
                    marker.check:Hide()
                end
            end
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            if recipeDataRequests[itemID] then
                recipeDataRequests[itemID] = false
                ScheduleRecipeRefresh()
            end
        elseif event == "NEW_RECIPE_LEARNED" or event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" then
            wipe(knownRecipeCache)
            ScheduleRecipeRefresh()
        end
    end)

    ns.ApplyLayout()
end
