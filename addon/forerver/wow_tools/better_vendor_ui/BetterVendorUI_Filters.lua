local ns = WoWTools.betterVendorUI

function ns.InitializeFilters()
    -- BetterVendorUI_Filters.lua
    -- Vendor item filters: category, equip slot, quality and a few conditions.
    -- Filters always remove items from the grid (see ApplyItemVisuals in BetterVendorUI.lua).

    local GetItemInfoInstantSafe = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant) or function() end
    local GetItemClassInfoSafe = GetItemClassInfo or (C_Item and C_Item.GetItemClassInfo) or function() end
    local GetItemSubClassInfoSafe = GetItemSubClassInfo or (C_Item and C_Item.GetItemSubClassInfo) or function() end
    local GetMerchantNumItemsSafe = ns.GetMerchantNumItemsSafe

    ---------------------------------------------------------------------------
    -- Saved filters
    ---------------------------------------------------------------------------

    -- Within a group, nothing checked means "no filter"; across groups all must pass.
    -- subclasses are keyed "classID:subclassID".
    local GROUPS = { "classes", "subclasses", "slots", "qualities" }
    local FLAGS = { "usableOnly", "affordableOnly", "hideSoldOut" }

    function ns.GetFilters()
        local DB = ns.DB
        DB.filters = DB.filters or {}
        for _, g in ipairs(GROUPS) do DB.filters[g] = DB.filters[g] or {} end
        return DB.filters
    end

    function ns.FiltersActive()
        if not ns.DB then return false end
        local f = ns.GetFilters()
        for _, g in ipairs(GROUPS) do
            if next(f[g]) and (g ~= "slots" or ns.Get("showSlotFilters")) then return true end
        end
        for _, flag in ipairs(FLAGS) do
            if f[flag] then return true end
        end
        return false
    end

    ---------------------------------------------------------------------------
    -- Vendor item data, cached per vendor visit
    ---------------------------------------------------------------------------

    local cache, cacheCount = {}, -1
    local waitingForQuality = {}  -- [itemID] = true while its details load

    -- Equip slots the game labels the same; shown and filtered as one
    local SLOT_ALIASES = { INVTYPE_ROBE = "INVTYPE_CHEST", INVTYPE_RANGEDRIGHT = "INVTYPE_RANGED" }

    function ns.ResetItemCache()
        wipe(cache)
        cacheCount = -1
    end

    function ns.CheckItemCache(numItems)
        if numItems ~= cacheCount then
            wipe(cache)
            cacheCount = numItems
        end
    end

    local function GetEntry(index)
        local e = cache[index]
        if e then return e end
        local name = ns.GetMerchantItemInfoSafe(index)
        if not name then return end
        e = { nameLower = string.lower(name), link = ns.GetMerchantItemLinkSafe(index) }
        if e.link then
            local itemID, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstantSafe(e.link)
            e.itemID, e.equipLoc, e.classID, e.subclassID = itemID, SLOT_ALIASES[equipLoc] or equipLoc, classID, subclassID
        end
        cache[index] = e
        return e
    end

    -- Quality can be unknown until the game loads the item; nil means "not yet"
    local function GetQuality(e)
        if e.quality == nil and e.link then
            local _, _, quality = ns.GetItemInfoSafe(e.link)
            if quality then
                e.quality = quality
            elseif e.itemID then
                waitingForQuality[e.itemID] = true
            end
        end
        return e.quality
    end

    function ns.MatchesSearch(index, searchString)
        local e = GetEntry(index)
        return e ~= nil and string.find(e.nameLower, searchString, 1, true) ~= nil
    end

    local function CanAfford(index, price, extendedCost)
        if CanAffordMerchantItem then
            local canAfford = CanAffordMerchantItem(index)
            if canAfford ~= nil then return canAfford ~= false end
        end
        if extendedCost then return true end  -- can't check other currencies without the API
        return (price or 0) <= GetMoney()
    end

    function ns.PassesFilters(index)
        local e = GetEntry(index)
        if not e then return true end
        local f = ns.GetFilters()

        if next(f.classes) or next(f.subclasses) then
            local sub = e.classID and (e.classID .. ":" .. (e.subclassID or 0))
            if not (e.classID and (f.classes[e.classID] or f.subclasses[sub])) then return false end
        end
        if next(f.slots) and ns.Get("showSlotFilters") and not f.slots[e.equipLoc or ""] then
            return false
        end
        if next(f.qualities) then
            local quality = GetQuality(e)
            -- Unknown quality passes, so nothing vanishes while it loads
            if quality and not f.qualities[quality] then return false end
        end
        if f.usableOnly or f.affordableOnly or f.hideSoldOut then
            -- Read fresh: these change as you buy
            local _, _, price, _, numAvailable, _, isUsable, extendedCost = ns.GetMerchantItemInfoSafe(index)
            if f.usableOnly and not isUsable then return false end
            if f.hideSoldOut and numAvailable == 0 then return false end
            if f.affordableOnly and not CanAfford(index, price, extendedCost) then return false end
        end
        return true
    end

    ---------------------------------------------------------------------------
    -- Filter panel (side panel to the right of the merchant window)
    ---------------------------------------------------------------------------

    local filterBtn, panel, scroll, content
    local rows, headers = {}, {}
    local expanded = {}  -- [classID] = true when its subcategories are shown (this session only)
    local ROW_HEIGHT, INDENT = 20, 16

    local function GetScrollBar()
        return scroll.ScrollBar or _G[scroll:GetName() .. "ScrollBar"]
    end

    local function QualityName(q)
        local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
        local _, _, _, hex = ns.GetItemQualityColorSafe(q)
        return hex and ("|c" .. hex .. name .. "|r") or name
    end

    local function SlotName(equipLoc)
        return _G[equipLoc] or equipLoc
    end

    local function ClassName(classID)
        return GetItemClassInfoSafe(classID) or ("类别 " .. classID)
    end

    local function SubclassName(classID, subclassID)
        return GetItemSubClassInfoSafe(classID, subclassID) or ("类型 " .. subclassID)
    end

    local function SortedKeys(t, nameOf)
        local keys = {}
        for k in pairs(t) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return nameOf(a) < nameOf(b) end)
        return keys
    end

    -- EllesmereUI look (see ns.OnSkin in BetterVendorUI.lua). The panel and its rows are
    -- built later than the facade arrives, so keep it and skin each piece as it's created.
    -- Every primitive is a no-op on an already skinned frame.
    local skin

    local function SkinHeader(fs)
        if skin then skin.Font(fs, skin.GetAccentColor()) end
    end

    local function SkinRow(row)
        if not skin then return end
        skin.Checkbox(row.check)
        skin.Font(row.label)
        skin.Font(row.count)
        -- No primitive for the +/- art: a small house button with a "+" / "-" label instead
        skin.Button(row.expand)
        skin.Font(row.expand.label)
        skin.White(row.expand.label)
    end

    local function SkinPanel()
        if not (skin and panel) then return end
        if panel.ClearBackdrop then panel:ClearBackdrop() end  -- the shell replaces it
        skin.Shell(panel)
        skin.Font(panel.title)
        skin.White(panel.title)
        skin.Button(panel.reset)
        skin.WhiteButtonLabel(panel.reset)
        local scrollBar = GetScrollBar()
        if scrollBar then skin.ScrollBar(scrollBar) end
        for _, fs in ipairs(headers) do SkinHeader(fs) end
        for _, row in ipairs(rows) do SkinRow(row) end
    end

    ns.OnSkin(function(S)
        skin = S
        SkinPanel()
        -- Headers use the accent color, which can change live
        S.OnLooksChanged(function()
            for _, fs in ipairs(headers) do SkinHeader(fs) end
        end)
    end)

    local function GetHeader(n)
        local fs = headers[n]
        if not fs then
            fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            SkinHeader(fs)
            headers[n] = fs
        end
        return fs
    end

    local function GetRow(n)
        local row = rows[n]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_HEIGHT)
        row.expand = CreateFrame("Button", nil, row)
        row.expand:SetSize(14, 14)
        row.expand:SetPoint("LEFT", 0, 0)
        row.expand.label = row.expand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.expand.label:SetPoint("CENTER", 0, 1)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 14, 0)
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
        row.label:SetJustifyH("LEFT")
        row.count = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.count:SetPoint("RIGHT", -4, 0)
        row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        SkinRow(row)
        rows[n] = row
        return row
    end

    -- Draws the panel from the current vendor's items and the saved filters
    local function RebuildPanel()
        if not panel or not panel:IsShown() then return end
        local f = ns.GetFilters()

        -- What this vendor sells, with counts
        local classes, subs, slotCounts, qualities = {}, {}, {}, {}
        local hasUnknownQuality = false
        for index = 1, GetMerchantNumItemsSafe() or 0 do
            local e = GetEntry(index)
            if e and e.classID then
                classes[e.classID] = (classes[e.classID] or 0) + 1
                subs[e.classID] = subs[e.classID] or {}
                local s = e.subclassID or 0
                subs[e.classID][s] = (subs[e.classID][s] or 0) + 1
                if e.equipLoc and e.equipLoc ~= "" and e.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
                    slotCounts[e.equipLoc] = (slotCounts[e.equipLoc] or 0) + 1
                end
            end
            if e then
                local q = GetQuality(e)
                if q then qualities[q] = (qualities[q] or 0) + 1 else hasUnknownQuality = true end
            end
        end

        -- A filter kept from another vendor gets a row with count 0, or it couldn't be unchecked
        for c in pairs(f.classes) do
            classes[c] = classes[c] or 0
            subs[c] = subs[c] or {}
        end
        for key in pairs(f.subclasses) do
            local c, s = key:match("^(%d+):(%d+)$")
            c, s = tonumber(c), tonumber(s)
            if c and s and not (subs[c] and subs[c][s]) then
                classes[c] = classes[c] or 0
                subs[c] = subs[c] or {}
                subs[c][s] = 0
                expanded[c] = true
            end
        end
        for loc in pairs(f.slots) do slotCounts[loc] = slotCounts[loc] or 0 end
        for q in pairs(f.qualities) do qualities[q] = qualities[q] or 0 end

        for _, row in ipairs(rows) do row:Hide() end
        for _, fs in ipairs(headers) do fs:Hide() end
        local y, nRow, nHeader = -4, 0, 0

        local function Header(text)
            nHeader = nHeader + 1
            local fs = GetHeader(nHeader)
            fs:SetPoint("TOPLEFT", 4, y - 4)
            fs:SetText(text)
            fs:Show()
            y = y - 22
        end

        local function Row(indent, text, count, checked, onToggle, expandState, onExpand)
            nRow = nRow + 1
            local row = GetRow(nRow)
            row:SetPoint("TOPLEFT", indent * INDENT, y)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            row.label:SetText(text)
            row.count:SetText(count and ("(" .. count .. ")") or "")
            row.check:SetChecked(checked and true or false)
            row.check:SetScript("OnClick", function() onToggle(); ns.FiltersChanged() end)
            row.check:Show()
            if expandState ~= nil then
                if skin then
                    row.expand.label:SetText(expandState and "-" or "+")
                else
                    local tex = expandState and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up"
                    row.expand:SetNormalTexture(tex)
                end
                row.expand:SetScript("OnClick", function() onExpand(); RebuildPanel() end)
                row.expand:Show()
            else
                row.expand:Hide()
            end
            row:Show()
            y = y - ROW_HEIGHT
            return row
        end

        local function Toggle(t, key) t[key] = (not t[key]) or nil end

        Header(CATEGORY or "类别")
        for _, c in ipairs(SortedKeys(classes, ClassName)) do
            local subList = SortedKeys(subs[c], function(s) return SubclassName(c, s) end)
            local canExpand = #subList > 1 or (subList[1] and f.subclasses[c .. ":" .. subList[1]])
            local expandState  -- nil = no +/- button, otherwise whether it's expanded
            if canExpand then expandState = expanded[c] == true end
            Row(0, ClassName(c), classes[c], f.classes[c],
                function()
                    Toggle(f.classes, c)
                    -- Whole category replaces any single subcategories picked in it
                    if f.classes[c] then
                        for _, s in ipairs(subList) do f.subclasses[c .. ":" .. s] = nil end
                    end
                end,
                expandState,
                function() expanded[c] = not expanded[c] or nil end)
            if canExpand and expanded[c] then
                for _, s in ipairs(subList) do
                    local key = c .. ":" .. s
                    Row(1, SubclassName(c, s), subs[c][s], f.subclasses[key], function()
                        Toggle(f.subclasses, key)
                        if f.subclasses[key] then f.classes[c] = nil end
                    end)
                end
            end
        end

        if ns.Get("showSlotFilters") and next(slotCounts) then
            Header("装备部位")
            for _, loc in ipairs(SortedKeys(slotCounts, SlotName)) do
                Row(0, SlotName(loc), slotCounts[loc], f.slots[loc], function() Toggle(f.slots, loc) end)
            end
        end

        Header(QUALITY or "品质")
        for q = 0, 7 do
            if qualities[q] then
                Row(0, QualityName(q), qualities[q], f.qualities[q], function() Toggle(f.qualities, q) end)
            end
        end
        if hasUnknownQuality then
            Row(0, "|cff808080正在加载…|r", nil, false, function() end).check:Hide()
        end

        Header("显示条件")
        Row(0, "当前角色可用", nil, f.usableOnly, function() f.usableOnly = not f.usableOnly end)
        Row(0, "买得起", nil, f.affordableOnly, function() f.affordableOnly = not f.affordableOnly end)
        Row(0, "有库存", nil, f.hideSoldOut, function() f.hideSoldOut = not f.hideSoldOut end)

        content:SetHeight(-y + 4)
        -- Panel fits its content, up to the merchant window's height (then it scrolls)
        local maxHeight = MerchantFrame:GetHeight() - 30
        local fits = -y + 52 <= maxHeight
        panel:SetHeight(fits and (-y + 52) or maxHeight)
        -- Scrollbar only when there's something to scroll
        local scrollBar = GetScrollBar()
        if scrollBar then scrollBar:SetShown(not fits) end
        if fits then scroll:SetVerticalScroll(0) end
        scroll:SetPoint("BOTTOMRIGHT", fits and -8 or -28, 8)
        content:SetWidth(fits and 210 or 190)
    end

    local function CreatePanel()
        panel = CreateFrame("Frame", "BetterVendorUIFilterPanel", MerchantFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        panel:SetSize(230, 300)
        panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 0, -24)
        panel:SetFrameStrata("DIALOG")
        panel:EnableMouse(true)
        panel:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        panel:Hide()
        table.insert(UISpecialFrames, "BetterVendorUIFilterPanel")  -- Escape closes it first

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 12, -12)
        title:SetText(FILTERS or "筛选")
        panel.title = title

        local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        reset:SetSize(70, 20)
        reset:SetPoint("TOPRIGHT", -10, -10)
        reset:SetText(RESET or "重置")
        reset:SetScript("OnClick", function() ns.ResetFilters() end)
        panel.reset = reset

        -- Named, so older templates can create their "$parentScrollBar" child
        scroll = CreateFrame("ScrollFrame", "BetterVendorUIFilterScroll", panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -38)
        scroll:SetPoint("BOTTOMRIGHT", -28, 8)
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(190, 1)
        scroll:SetScrollChild(content)

        panel:SetScript("OnShow", RebuildPanel)
        SkinPanel()  -- EllesmereUI look, when its skinning is on
    end

    local function UpdateFilterButton()
        if filterBtn then filterBtn.glow:SetShown(ns.FiltersActive()) end
    end

    -- Called after any filter change: redraw from page 1 and refresh the panel
    function ns.FiltersChanged()
        MerchantFrame.page = 1
        ns.ResetListScroll()
        if MerchantFrame:IsShown() then MerchantFrame_Update() end
        UpdateFilterButton()
        RebuildPanel()
    end

    -- Clears all filters, then applies the "Usable by me only" default.
    -- `silent` skips the redraw. Returns whether anything was or is active.
    function ns.ResetFilters(silent)
        if not ns.DB then return false end
        local wasActive = ns.FiltersActive()
        local f = ns.GetFilters()
        for _, g in ipairs(GROUPS) do wipe(f[g]) end
        for _, flag in ipairs(FLAGS) do f[flag] = false end
        f.usableOnly = ns.Get("usableOnlyDefault")
        if silent then
            UpdateFilterButton()
            RebuildPanel()
        else
            ns.FiltersChanged()
        end
        return wasActive or ns.FiltersActive()
    end

    -- Settings changed: equip slot filters may have been switched on or off
    function ns.UpdateFilterUI()
        UpdateFilterButton()
        RebuildPanel()
    end

    function ns.CreateFilterButton()
        filterBtn = ns.CreateHeaderButton("BetterVendorUIFilterBtn", "Interface\\Icons\\INV_Misc_Spyglass_02",
            FILTERS or "筛选", function()
                if not panel then CreatePanel() end
                panel:SetShown(not panel:IsShown())
            end)
        filterBtn.glow = filterBtn:CreateTexture(nil, "OVERLAY")
        filterBtn.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        filterBtn.glow:SetBlendMode("ADD")
        filterBtn.glow:SetAllPoints()
        filterBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(FILTERS or "筛选")
            if ns.FiltersActive() then
                GameTooltip:AddLine("筛选已启用，点击可修改筛选条件。", 0, 1, 0)
            else
                GameTooltip:AddLine("设置此商人的商品筛选条件。", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        UpdateFilterButton()
        return filterBtn
    end

    -- A vendor item's quality arrived: redraw once, batched
    local redrawPending = false
    function ns.OnItemInfoReceived(itemID)
        if not itemID or not waitingForQuality[itemID] then return end
        waitingForQuality[itemID] = nil
        if redrawPending then return end
        redrawPending = true
        C_Timer.After(0.2, function()
            redrawPending = false
            if not MerchantFrame:IsShown() then return end
            if ns.FiltersActive() then MerchantFrame_Update() end
            RebuildPanel()
        end)
    end

end
