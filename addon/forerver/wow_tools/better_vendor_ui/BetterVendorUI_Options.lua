local ns = WoWTools.betterVendorUI

function ns.BuildOptions(parent)
    -- BetterVendorUI_Options.lua
    -- Settings page under ESC > Options > AddOns. Built as a canvas page (our own widgets)
    -- so it works with both the modern Settings API and the old InterfaceOptions API.

    local TITLE = "Better Vendor UI"
    local widgets = {}

    StaticPopupDialogs["BETTERVENDORUI_CONFIRM"] = {
        text = "%s",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, data) data() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    local function Confirm(text, onAccept)
        StaticPopup_Show("BETTERVENDORUI_CONFIRM", text, nil, onAccept)
    end

    local function SetTooltip(frame, title, text)
        if not text then return end
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(text, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function CountKeys(t)
        local n = 0
        for _ in pairs(t or {}) do n = n + 1 end
        return n
    end

    ---------------------------------------------------------------------------
    -- Panel and layout
    ---------------------------------------------------------------------------

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    ns.optionsPanel = panel
    panel.name = TITLE

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width) content:SetWidth(width) end)

    local y = -8
    local LEFT = 16

    local function Advance(height) y = y - height end

    local function Header(text)
        Advance(14)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", LEFT, y)
        fs:SetText(text)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.15)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
        line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        Advance(30)
    end

    local function Note(getText)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", LEFT + 4, y)
        fs:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        fs:SetJustifyH("LEFT")
        Advance(20)
        local w = { Refresh = function() fs:SetText(getText()) end, SetEnabledState = function() end }
        table.insert(widgets, w)
        return w
    end

    local function Checkbox(label, key, tooltip, indent)
        local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", LEFT + (indent or 0), y)
        local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        text:SetText(label)
        cb:SetScript("OnClick", function(self)
            ns.Set(key, self:GetChecked() and true or false)
            ns.RefreshOptions()
        end)
        SetTooltip(cb, label, tooltip)
        Advance(28)

        local w = {}
        function w.Refresh() cb:SetChecked(ns.Get(key)) end
        function w.SetEnabledState(on)
            cb:SetEnabled(on)
            text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        end
        table.insert(widgets, w)
        return w
    end

    -- Click to go to the next choice, right-click for the previous one.
    -- (Used instead of a dropdown: the dropdown templates differ between client versions.)
    local function Cycle(label, key, choices, tooltip, indent)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", LEFT + (indent or 0) + 6, y - 5)
        fs:SetText(label)
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetSize(130, 22)
        btn:SetPoint("LEFT", fs, "RIGHT", 10, 0)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(_, mouseButton)
            local current = ns.Get(key)
            local index = 1
            for i, c in ipairs(choices) do
                if c.value == current then index = i end
            end
            local step = mouseButton == "RightButton" and -1 or 1
            index = (index - 1 + step) % #choices + 1
            ns.Set(key, choices[index].value)
            ns.RefreshOptions()
        end)
        SetTooltip(btn, label, (tooltip and tooltip .. "|n|n" or "") .. "Left-click: next, right-click: previous.")
        Advance(30)

        local w = {}
        function w.Refresh()
            local current = ns.Get(key)
            for _, c in ipairs(choices) do
                if c.value == current then btn:SetText(c.text) end
            end
        end
        function w.SetEnabledState(on)
            btn:SetEnabled(on)
            fs:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        end
        table.insert(widgets, w)
        return w
    end

    local function Slider(label, key, minValue, maxValue, step, format, tooltip, indent)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", LEFT + (indent or 0) + 6, y - 4)
        fs:SetText(label)

        local slider = CreateFrame("Slider", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(180, 17)
        -- Fixed column so stacked sliders line up regardless of label width
        slider:SetPoint("LEFT", content, "TOPLEFT", LEFT + (indent or 0) + 150, y - 11)
        slider:SetHitRectInsets(0, 0, -10, -10)
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

        local valueText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)

        local refreshing = false
        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            valueText:SetText(string.format(format, value))
            if not refreshing then ns.Set(key, value) end
        end)
        SetTooltip(slider, label, tooltip)
        Advance(32)

        local w = {}
        function w.Refresh()
            refreshing = true
            slider:SetValue(ns.Get(key))
            valueText:SetText(string.format(format, ns.Get(key)))
            refreshing = false
        end
        function w.SetEnabledState(on)
            if on then slider:Enable() else slider:Disable() end
            slider:SetAlpha(on and 1 or 0.5)
            fs:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        end
        table.insert(widgets, w)
        return w
    end

    -- Puts up to three buttons in one row.
    local function Buttons(...)
        local x = LEFT + 4
        for i = 1, select("#", ...) do
            local def = select(i, ...)
            local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            btn:SetText(def.text)
            btn:SetSize(math.max(140, btn:GetFontString():GetStringWidth() + 24), 24)
            btn:SetPoint("TOPLEFT", x, y)
            btn:SetScript("OnClick", def.onClick)
            SetTooltip(btn, def.text, def.tooltip)
            x = x + btn:GetWidth() + 8
        end
        Advance(32)
    end

    ---------------------------------------------------------------------------
    -- Contents
    ---------------------------------------------------------------------------

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", LEFT, y)
    title:SetText(TITLE)
    local version = ns.sourceVersion
    if version then
        local versionText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        versionText:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
        versionText:SetText("v" .. version)
    end
    Advance(30)

    -- Merchant window
    Header("Merchant window")
    local columnsSlider = Slider("Columns", "gridColumns", 2, 6, 1, "%d",
        "How many items are shown side by side. The game's default is 2.|n|nNot used while EllesmereUI shows the merchant as a list.")
    Slider("Rows", "gridRows", 5, 10, 1, "%d",
        "How many rows of items are shown. The game's default is 5.")
    Buttons(
        { text = "Game default (2 x 5)", onClick = function()
            ns.Set("gridColumns", 2)
            ns.Set("gridRows", 5)
            ns.RefreshOptions()
        end },
        { text = "Better Vendor UI default (4 x 5)", onClick = function()
            ns.Set("gridColumns", 4)
            ns.Set("gridRows", 5)
            ns.RefreshOptions()
        end }
    )
    local buybackFullWidth = Checkbox("Buyback tab uses the full width", "buybackFullWidth",
        "Lays out the 12 buyback slots in the same columns as the merchant grid (for example 4 x 3). When unchecked, buyback uses the game's 2 columns.")
    local showSearch = Checkbox("Show search box", "showSearch",
        "Adds a search box to the merchant window that filters items by name.")
    local searchMode = Cycle("Non-matching items:", "searchMode", {
        { value = "dim", text = "Dim" },
        { value = "hide", text = "Hide" },
    }, "What happens to items that don't match the search.", 20)
    local dimAlpha = Slider("Dim strength", "dimAlpha", 0, 0.6, 0.05, "%.2f",
        "How visible dimmed items stay. 0 is invisible, 0.6 is barely dimmed.", 20)
    local clearSearch = Checkbox("Clear search when opening a vendor", "clearSearchOnShow", nil, 20)
    Checkbox("已学配方标记", "knownRecipes", "图标去色并显示绿色勾，标识本角色已经学会的配方。")
    local qualityBorders = Checkbox("Quality borders on vendor items", "qualityBorders",
        "Colors the border of vendor items by their quality.")
    local qualityChoices = {}
    for q = 1, 4 do
        local _, _, _, hex = ns.GetItemQualityColorSafe(q)
        local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
        table.insert(qualityChoices, { value = q, text = hex and ("|c" .. hex .. name .. "|r") or name })
    end
    local minQuality = Cycle("Minimum quality:", "minBorderQuality", qualityChoices,
        "Only items of this quality or better get a colored border.", 20)
    Checkbox("Show lists button on the merchant window", "showListsButton",
        "The small note button next to the search box that opens the Always sell / Never sell lists. The lists can also be opened with /bvu lists or from this page.")
    Checkbox("Show options button on the merchant window", "showOptionsButton",
        "The small gear button next to the search box that opens this page. It can also be opened with /bvu.")

    -- Filters
    Header("Filters")
    Checkbox("Show filter button on the merchant window", "showFilterButton",
        "The spyglass button next to the search box. It opens a panel to show only some of the vendor's items, by category, quality or whether you can use or afford them.")
    Checkbox("Reset filters when opening a vendor", "resetFiltersOnShow",
        "Starts every vendor with no filters, so a filter set at one vendor doesn't hide items at the next.")
    Checkbox("\"Usable by me\" on by default", "usableOnlyDefault",
        "Whenever filters are reset, \"Usable by me\" is switched on. Usability is checked for the character you're playing, so each character only sees items it can use.")
    Checkbox("Show equip slot filters", "showSlotFilters",
        "Adds an Equip slot section (Head, Chest, Feet...) to the filter panel.")
    Buttons(
        { text = "Reset filters", onClick = function() ns.ResetFilters() end,
          tooltip = "Clears all filters (then applies the \"Usable by me\" default)." }
    )

    -- Selling junk
    Header("Selling junk")
    Checkbox("Use Better Vendor UI rules for the Sell Junk button", "overrideSellButton",
        "When checked, the Sell Junk button uses your Always sell and Never sell lists and the options below. When unchecked, it does what the game normally does.")
    Checkbox("Keep the Sell Junk button always clickable", "keepSellButtonEnabled",
        "The game disables the button when it thinks you have no junk. Keep it enabled so items on your Always sell list can still be sold.")
    Checkbox("Sell items on the Always sell list", "sellAlwaysList",
        "Items on the Always sell list are sold along with junk, whatever their quality.")
    local autoSell = Checkbox("Sell junk automatically when opening a vendor", "autoSell",
        "Sells junk as soon as you open a vendor. Hold Shift while opening the vendor to skip it.|n|nThis is turned off while Leatrix Plus or EllesmereUI is selling junk automatically.")
    Checkbox("Keep unbound grey weapons and armor", "keepGreyGear",
        "Grey weapons and armor that aren't soulbound are not sold, for example so you can put them on the auction house. Items on the Always sell list are still sold.")
    Checkbox("Sell at most 12 items at a time", "limit12",
        "The buyback tab only holds the last 12 items you sold. With this on, every sold item can still be bought back. Click Sell Junk again to sell the rest.")
    Checkbox("Print a summary in chat", "printSummary")
    Checkbox("Print \"No junk items found\"", "printNoJunk")

    -- Leatrix Plus
    Header("Leatrix Plus")
    Note(function()
        local state = ns.LeatrixState()
        if state == "on" then
            return "|cff00ff00Leatrix Plus detected, \"Sell junk automatically\" is on.|r"
        elseif state == "off" then
            return "|cffffd100Leatrix Plus detected, \"Sell junk automatically\" is off. These options have no effect.|r"
        end
        return "|cff808080Leatrix Plus is not loaded. These options have no effect.|r"
    end)
    local leaSync = Checkbox("Copy grey Never sell items into Leatrix's exclusions", "leatrixSyncNeverSell",
        "Leatrix won't sell grey items on your Never sell list. Unchecking this removes every entry Better Vendor UI added to Leatrix's list. Entries you typed in Leatrix yourself are never touched.")
    local leaSell = Checkbox("Sell Always sell items when Leatrix auto-sells", "leatrixSellAlwaysList",
        "Leatrix only sells grey items. With this on, Better Vendor UI sells the items on your Always sell list when you open a vendor. Hold Shift to skip.")

    -- EllesmereUI
    Header("EllesmereUI")
    Note(function()
        local loaded, autoSell, marker = ns.EllesmereInfo()
        if not loaded then
            return "|cff808080EllesmereUI is not loaded. These options have no effect.|r"
        elseif marker then
            return "|cff00ff00EllesmereUI detected with the Junk Marker on: its junk selling follows your lists.|r"
        elseif autoSell then
            return "|cffff8000EllesmereUI's Auto Sell Junk sells every grey item and can't skip Never sell items. Turn on the Junk Marker (coin icon) in EllesmereUI Bags to protect them.|r"
        end
        return "|cffffd100EllesmereUI detected, \"Auto Sell Junk\" is off and the Junk Marker is off. These options have no effect.|r"
    end)
    local ellNever = Checkbox("EllesmereUI never sells Never sell items", "ellesmereNeverSell",
        "Items on your Never sell list don't count as junk in EllesmereUI: its Auto Sell Junk and its Sell Junk button skip them, and they don't get the junk badge.|n|nNeeds the Junk Marker (coin icon) in EllesmereUI Bags.")
    local ellAlways = Checkbox("EllesmereUI sells Always sell items too", "ellesmereAlwaysSell",
        "Items on your Always sell list are sold with EllesmereUI's junk. With the Junk Marker on, EllesmereUI treats them as junk (they also show in its Junk category). Without it, Better Vendor UI sells them when you open a vendor. Hold Shift to skip.")

    -- Lists and window
    Header("Lists and window")
    Note(function()
        local DB = ns.DB or {}
        return string.format("Always sell: %d items     Never sell: %d items", CountKeys(DB.whitelist), CountKeys(DB.blacklist))
    end)
    Buttons(
        { text = "Open lists window", onClick = function() ns.ToggleConfig() end },
        { text = "Reset window position", onClick = function() ns.ResetConfigPosition() end,
          tooltip = "Moves the lists window back next to the merchant window." }
    )
    Buttons(
        { text = "Clear Always sell", onClick = function()
            Confirm("Remove all items from the Always sell list?", function()
                wipe(ns.DB.whitelist)
                ns.UpdateConfigLists()
            end)
        end },
        { text = "Clear Never sell", onClick = function()
            Confirm("Remove all items from the Never sell list?", function()
                wipe(ns.DB.blacklist)
                ns.UpdateConfigLists()
            end)
        end }
    )
    Buttons(
        { text = "Reset all settings", onClick = function()
            Confirm("Reset all Better Vendor UI settings to their defaults?|n|nYour Always sell and Never sell lists are kept.", function()
                ns.ResetSettings()
                ns.RefreshOptions()
            end)
        end }
    )
    Note(function() return "|cff808080Slash commands: /bvu (this page), /bvu lists, /bvu wl <item>, /bvu bl <item>|r" end)

    content:SetHeight(-y + 16)

    ---------------------------------------------------------------------------
    -- Refresh and dependencies
    ---------------------------------------------------------------------------

    function ns.RefreshOptions()
        if not ns.DB or not panel:IsVisible() then return end
        for _, w in ipairs(widgets) do w.Refresh() end

        local searchOn = ns.Get("showSearch")
        searchMode.SetEnabledState(searchOn)
        dimAlpha.SetEnabledState(searchOn and ns.Get("searchMode") == "dim")
        clearSearch.SetEnabledState(searchOn)
        minQuality.SetEnabledState(ns.Get("qualityBorders"))

        local leatrixOn = ns.LeatrixState() == "on"
        local _, ellesmereAutoSell, ellesmereMarker = ns.EllesmereInfo()
        -- Our own auto-sell stays off while another addon sells junk at vendors
        autoSell.SetEnabledState(not leatrixOn and not ellesmereAutoSell)
        leaSync.SetEnabledState(leatrixOn)
        leaSell.SetEnabledState(leatrixOn and ns.Get("sellAlwaysList"))
        ellNever.SetEnabledState(ellesmereMarker)
        ellAlways.SetEnabledState((ellesmereMarker or ellesmereAutoSell) and ns.Get("sellAlwaysList"))
        -- EllesmereUI's list draws the items itself: no grid columns there
        local listMode = ns.EllesmereListMode()
        columnsSlider.SetEnabledState(not listMode)
        buybackFullWidth.SetEnabledState(not listMode)
    end

    panel:SetScript("OnShow", ns.RefreshOptions)

    return panel
end
