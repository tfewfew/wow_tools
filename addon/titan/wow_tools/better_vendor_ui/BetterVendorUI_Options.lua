local ns = WoWTools.betterVendorUI

function ns.BuildOptions(parent)
    -- BetterVendorUI_Options.lua
    -- Settings page under ESC > Options > AddOns. Built as a canvas page (our own widgets)
    -- so it works with both the modern Settings API and the old InterfaceOptions API.

    local TITLE = "商人增强"
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
        SetTooltip(btn, label, (tooltip and tooltip .. "|n|n" or "") .. "左键切换下一项，右键切换上一项。")
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
    Header("商人窗口")
    local columnsSlider = Slider("列数", "gridColumns", 2, 6, 1, "%d",
        "每行显示的商品数量，游戏默认 2 列。|n|nEllesmereUI 使用商人列表视图时，此选项暂不可用。")
    Slider("行数", "gridRows", 5, 10, 1, "%d",
        "每页显示的商品行数，游戏默认 5 行。")
    Buttons(
        { text = "游戏默认（2×5）", onClick = function()
            ns.Set("gridColumns", 2)
            ns.Set("gridRows", 5)
            ns.RefreshOptions()
        end },
        { text = "插件默认（4×5）", onClick = function()
            ns.Set("gridColumns", 4)
            ns.Set("gridRows", 5)
            ns.RefreshOptions()
        end }
    )
    local buybackFullWidth = Checkbox("回购页使用完整窗口宽度", "buybackFullWidth",
        "将 12 个回购栏位按商人窗口的列数排列，例如 4 列 3 行。取消勾选后，回购页采用游戏默认的 2 列布局。")
    local showSearch = Checkbox("显示搜索框", "showSearch",
        "在商人窗口显示搜索框，按物品名称筛选商品。")
    local searchMode = Cycle("未匹配的商品", "searchMode", {
        { value = "dim", text = "淡化" },
        { value = "hide", text = "隐藏" },
    }, "选择搜索未匹配商品的显示方式。", 20)
    local dimAlpha = Slider("淡化后不透明度", "dimAlpha", 0, 0.6, 0.05, "%.2f",
        "设置淡化后商品的不透明度。0 为完全透明，0.6 为轻度淡化。", 20)
    local clearSearch = Checkbox("打开商人时清空搜索", "clearSearchOnShow", nil, 20)
    Checkbox("已学配方标记", "knownRecipes", "图标去色并显示绿色勾，标识本角色已经学会的配方。")
    local qualityBorders = Checkbox("按物品品质显示边框颜色", "qualityBorders",
        "根据商品的物品品质设置边框颜色。")
    local qualityChoices = {}
    for q = 1, 4 do
        local _, _, _, hex = ns.GetItemQualityColorSafe(q)
        local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
        table.insert(qualityChoices, { value = q, text = hex and ("|c" .. hex .. name .. "|r") or name })
    end
    local minQuality = Cycle("最低品质", "minBorderQuality", qualityChoices,
        "达到此品质及以上的商品显示品质边框。", 20)
    Checkbox("显示售卖名单按钮", "showListsButton",
        "在搜索框旁显示便笺按钮，点击打开必卖名单和禁卖名单。也可通过 /bvu lists 或本页打开。")
    Checkbox("显示设置按钮", "showOptionsButton",
        "在搜索框旁显示齿轮按钮，点击打开本设置页。也可使用 /bvu 打开。")

    -- Filters
    Header("筛选")
    Checkbox("显示筛选按钮", "showFilterButton",
        "在搜索框旁显示望远镜按钮，按类别、品质、当前角色是否可用及是否买得起筛选商品。")
    Checkbox("打开商人时重置筛选", "resetFiltersOnShow",
        "每次打开商人时清空筛选条件，避免沿用上一位商人的筛选结果。")
    Checkbox("默认启用“当前角色可用”", "usableOnlyDefault",
        "重置筛选时自动勾选“当前角色可用”，根据当前角色的可用状态显示商品。")
    Checkbox("显示装备部位筛选", "showSlotFilters",
        "在筛选面板中增加头部、胸部、脚部等装备部位选项。")
    Buttons(
        { text = "重置筛选", onClick = function() ns.ResetFilters() end,
          tooltip = "清空筛选条件，并应用“当前角色可用”的默认设置。" }
    )

    -- Selling junk
    Header("出售垃圾")
    Checkbox("出售垃圾按钮采用商人增强规则", "overrideSellButton",
        "勾选后，出售垃圾按钮使用必卖名单、禁卖名单及下方设置。取消勾选后，按钮采用游戏原有规则。")
    Checkbox("出售垃圾按钮始终可点击", "keepSellButtonEnabled",
        "游戏判定背包中没有垃圾时会禁用按钮。启用后，仍可点击按钮出售必卖名单中的物品。")
    Checkbox("出售必卖名单中的物品", "sellAlwaysList",
        "出售垃圾时一并出售必卖名单中的所有物品，包含各类品质。")
    local autoSell = Checkbox("打开商人时自动出售垃圾", "autoSell",
        "打开商人时自动出售垃圾，打开时按住 Shift 可跳过。|n|nLeatrix Plus 或 EllesmereUI 正在自动出售垃圾时，此功能自动停用。")
    Checkbox("保留未绑定的灰色武器和护甲", "keepGreyGear",
        "保留尚未灵魂绑定的灰色武器和护甲，方便在拍卖行出售。必卖名单中的物品仍会出售。")
    Checkbox("每次最多出售 12 件物品", "limit12",
        "回购页保存最近出售的 12 件物品。启用后，每次出售的物品均可回购，再次点击出售垃圾按钮可继续出售。")
    Checkbox("在聊天栏显示出售汇总", "printSummary")
    Checkbox("显示“没有可出售的垃圾物品”", "printNoJunk")

    -- Leatrix Plus
    Header("Leatrix Plus")
    Note(function()
        local state = ns.LeatrixState()
        if state == "on" then
            return "|cff00ff00已检测到 Leatrix Plus，自动出售垃圾已开启。|r"
        elseif state == "off" then
            return "|cffffd100已检测到 Leatrix Plus，自动出售垃圾已关闭，相关选项暂不可用。|r"
        end
        return "|cff808080Leatrix Plus 尚未加载，相关选项暂不可用。|r"
    end)
    local leaSync = Checkbox("将禁卖名单中的灰色物品同步到 Leatrix 排除名单", "leatrixSyncNeverSell",
        "将禁卖名单中的灰色物品加入 Leatrix 排除名单，防止自动出售。取消勾选会移除由商人增强添加的记录，你在 Leatrix 中手动输入的记录继续保留。")
    local leaSell = Checkbox("Leatrix 自动售卖时一并出售必卖物品", "leatrixSellAlwaysList",
        "Leatrix 自动售卖的范围为灰色物品。启用后，商人增强会在打开商人时额外出售必卖名单中的物品，按住 Shift 可跳过。")

    -- EllesmereUI
    Header("EllesmereUI")
    Note(function()
        local loaded, autoSell, marker = ns.EllesmereInfo()
        if not loaded then
            return "|cff808080EllesmereUI 尚未加载，相关选项暂不可用。|r"
        elseif marker then
            return "|cff00ff00EllesmereUI 垃圾标记已开启，垃圾售卖将遵循售卖名单。|r"
        elseif autoSell then
            return "|cffff8000EllesmereUI 会卖出所有灰色物品，开启背包硬币标记可保护禁卖物品。|r"
        end
        return "|cffffd100EllesmereUI 自动售卖和垃圾标记均已关闭，相关选项暂不可用。|r"
    end)
    local ellNever = Checkbox("EllesmereUI 遵循禁卖名单", "ellesmereNeverSell",
        "EllesmereUI 会将禁卖名单中的物品排除出垃圾范围，自动售卖和出售垃圾按钮均会跳过这些物品，同时移除其垃圾标记。|n|n需要开启 EllesmereUI 背包中的垃圾标记（硬币图标）。")
    local ellAlways = Checkbox("EllesmereUI 一并出售必卖物品", "ellesmereAlwaysSell",
        "必卖名单中的物品会随 EllesmereUI 的垃圾一并出售。开启垃圾标记后，这些物品会归入其垃圾分类。垃圾标记关闭时，由商人增强在打开商人时出售，按住 Shift 可跳过。")

    -- Lists and window
    Header("售卖名单与窗口")
    Note(function()
        local DB = ns.DB or {}
        return string.format("必卖名单 %d 件     禁卖名单 %d 件", CountKeys(DB.whitelist), CountKeys(DB.blacklist))
    end)
    Buttons(
        { text = "打开售卖名单", onClick = function() ns.ToggleConfig() end },
        { text = "重置窗口位置", onClick = function() ns.ResetConfigPosition() end,
          tooltip = "将售卖名单窗口移回商人窗口旁。" }
    )
    Buttons(
        { text = "清空必卖名单", onClick = function()
            Confirm("确定清空必卖名单中的所有物品吗？", function()
                wipe(ns.DB.whitelist)
                ns.UpdateConfigLists()
            end)
        end },
        { text = "清空禁卖名单", onClick = function()
            Confirm("确定清空禁卖名单中的所有物品吗？", function()
                wipe(ns.DB.blacklist)
                ns.UpdateConfigLists()
            end)
        end }
    )
    Buttons(
        { text = "重置全部设置", onClick = function()
            Confirm("确定将商人增强的全部设置恢复为默认值吗？|n|n必卖名单和禁卖名单继续保留。", function()
                ns.ResetSettings()
                ns.RefreshOptions()
            end)
        end }
    )
    Note(function() return "|cff808080命令 /bvu（设置）、/bvu lists（售卖名单）、/bvu wl <物品>（切换必卖）、/bvu bl <物品>（切换禁卖）|r" end)

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
