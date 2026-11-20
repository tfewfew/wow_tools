-- Forever native container interfaces at Gethe/wow-ui-source 3d8abb1da73acd38e412e24fb3f99454a6392346.
-- Group the item buttons the native combined container already owns.
local module = { views = {}, settingsHeight = 240, active = false }
WoWTools.bagIntegration = module
local reagentBag = Enum.BagIndex.ReagentBag
local installed, applying = false, false
local layoutTimer
local retryLayout = false
local opening = false
local status = "背包整合已关闭。"
local decorations = {}
local events = CreateFrame("Frame")
local Reconcile, ScheduleLayout

local function Config()
    if type(wowDetectorDB) ~= "table" then return end
    if type(wowDetectorDB.bagIntegration) ~= "table" then wowDetectorDB.bagIntegration = {} end
    return wowDetectorDB.bagIntegration
end

function module.IsEnabled()
    local config = Config()
    return config and config.enabled == true or false
end

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Integer(value)
    return Readable(value) and type(value) == "number" and value >= 0
        and value <= 2147483647 and value == math.floor(value)
end

local function Finite(value)
    return Readable(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local anchorPoints = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function SavedPosition()
    local config = Config()
    local position = config and config.position
    if type(position) == "table" and Finite(position.x) and Finite(position.y)
        and anchorPoints[position.point or "TOPLEFT"] and anchorPoints[position.relativePoint or "TOPLEFT"] then
        return position
    end
end

local function SavePosition(frame)
    if not module.active then return end
    local config = Config()
    if not config then return end
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (Finite(scale) and scale > 0 and Finite(parentScale) and parentScale > 0) then return end
    local ratio = scale / parentScale
    -- Anchors remain readable during OnHide even when the visible rect is unavailable.
    local point, relative, relativePoint, offsetX, offsetY = frame:GetPoint(1)
    if (relative == UIParent or relative == nil) and anchorPoints[point] and anchorPoints[relativePoint]
        and Finite(offsetX) and Finite(offsetY) then
        local x, y = offsetX * ratio, offsetY * ratio
        if Finite(x) and Finite(y) then
            config.position = {point = point, relativePoint = relativePoint, x = x, y = y}
        end
        return
    end
    local left, top = frame:GetLeft(), frame:GetTop()
    local parentLeft, parentTop = UIParent:GetLeft(), UIParent:GetTop()
    if not (Finite(left) and Finite(top) and Finite(parentLeft) and Finite(parentTop)) then return end
    local x, y = left * ratio - parentLeft, top * ratio - parentTop
    if Finite(x) and Finite(y) then config.position = {x = x, y = y} end
end

local function ApplyScale(frame)
    if Readable(frame.suofang) and type(frame.suofang) == "number" and frame.suofang > 0 then
        frame:SetScale(frame.suofang)
    end
end

local function RestorePosition()
    local frame = ContainerFrameCombinedBags
    local position = SavedPosition()
    if not module.active or not position then return end
    ApplyScale(frame)
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (Finite(scale) and scale > 0 and Finite(parentScale) and parentScale > 0) then return end
    local ratio = parentScale / scale
    frame:ClearAllPoints()
    frame:SetPoint(position.point or "TOPLEFT", UIParent, position.relativePoint or "TOPLEFT",
        position.x * ratio, position.y * ratio)
end

local function Conflict()
    for _, name in ipairs({"Bagnon", "Bagnonium", "Combuctor", "Baganator", "AdiBags", "BetterBags", "ArkInventory", "Sorted"}) do
        if C_AddOns.IsAddOnLoaded(name) then return name end
    end
    local elvBags = ElvUI and ElvUI[1] and ElvUI[1].private and ElvUI[1].private.bags
    if C_AddOns.IsAddOnLoaded("ElvUI") and (not elvBags or elvBags.enable ~= false) then return "ElvUI" end
    local nduiBags = NDui and NDui[2] and NDui[2].db and NDui[2].db.Bags
    if C_AddOns.IsAddOnLoaded("NDui") and (not nduiBags or nduiBags.Enable ~= false) then return "NDui" end
end

local function UpdateViews()
    for _, view in ipairs(module.views) do
        view.enabled:SetChecked(module.IsEnabled())
        view.status:SetText(status)
    end
end

local function HideDecorations()
    for _, decoration in pairs(decorations) do
        decoration.label:Hide()
        decoration.line:Hide()
    end
end

local function BagGroup(bagID)
    if bagID == 0 then return 1 end
    if bagID == reagentBag then return 2 end
    if C_Container.GetContainerNumSlots(bagID) == 0 then return 1 end
    local ok, _, family = pcall(C_Container.GetContainerNumFreeSlots, bagID)
    if not ok or not Integer(family) then return end
    -- Arrow and bullet bag families are bits 1 and 2 on this client.
    if bit.band(family, 3) ~= 0 then return 3 end
    local inventoryID = C_Container.ContainerIDToInventoryID(bagID)
    local link = GetInventoryItemLink("player", inventoryID)
    if Readable(link) and link then
        local info = { pcall(C_Item.GetItemInfoInstant, link) }
        if info[1] and Readable(info[7]) and info[7] == Enum.ItemClass.Quiver then return 3 end
    end
    return family == 0 and 1 or 2
end

local function Layout()
    local frame = ContainerFrameCombinedBags
    -- Native bag reflows also run in combat, and their grouped geometry must follow.
    if not module.active or not frame:IsShown() then return end
    local conflict = Conflict()
    if conflict or InputUtil.IsGamepadUIEnabled() then Reconcile() return end
    local groups = {{}, {}, {}}
    local groupByBag = {}
    for _, button in frame:EnumerateValidItems() do
        local bagID = button:GetBagID()
        if bagID >= 0 and bagID <= reagentBag then
            local group = groupByBag[bagID] or BagGroup(bagID)
            if not group then
                retryLayout = true
                events:RegisterEvent("BAG_UPDATE_DELAYED")
                status = "背包类型暂不可读，等待背包数据更新。"
                UpdateViews()
                return
            end
            groupByBag[bagID] = group
            groups[group][#groups[group] + 1] = button
        end
    end
    local template = C_XMLUtil.GetTemplateInfo(frame.itemButtonPool:GetTemplate())
    local columns = frame.meihang or frame:GetColumns()
    if not Integer(columns) or columns < 1 or not template then return end
    local itemWidth, itemHeight = template.width, template.height
    local width = columns * itemWidth + (columns - 1) * 5 + frame:GetPaddingWidth()
    local offset, visibleGroups = 64, 0
    local labels = {"普通背包", "材料袋", "弹药袋"}
    HideDecorations()
    for groupIndex, buttons in ipairs(groups) do
        if #buttons > 0 then
            table.sort(buttons, function(left, right)
                if left:GetBagID() == right:GetBagID() then return left:GetID() < right:GetID() end
                return left:GetBagID() < right:GetBagID()
            end)
            local decoration = decorations[groupIndex]
            if not decoration then
                decoration = {label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
                    line = frame:CreateTexture(nil, "ARTWORK")}
                decoration.line:SetHeight(1)
                decoration.line:SetColorTexture(0.45, 0.45, 0.45, 1)
                decorations[groupIndex] = decoration
            end
            if visibleGroups > 0 then
                decoration.line:ClearAllPoints()
                decoration.line:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -offset - 10)
                decoration.line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -offset - 10)
                decoration.line:Show()
                offset = offset + 22
            end
            decoration.label:ClearAllPoints()
            decoration.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -offset)
            decoration.label:SetText(labels[groupIndex])
            decoration.label:Show()
            offset = offset + 18
            for index, button in ipairs(buttons) do
                local column = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", frame, "TOPLEFT", 8 + column * (itemWidth + 5), -offset - row * (itemHeight + 5))
            end
            offset = offset + math.ceil(#buttons / columns) * (itemHeight + 5) - 5
            visibleGroups = visibleGroups + 1
        end
    end
    frame:SetSize(width, offset + frame:CalculateExtraHeight() + 12)
    NineSliceUtil.UpdateCornerCropping(frame, frame:GetHeight())
    frame:LayoutAddSlots()
    -- Native opening and movement addons own the window anchors during item reflows.
    ApplyScale(frame)
    retryLayout = false
    events:UnregisterEvent("BAG_UPDATE_DELAYED")
    status = "背包整合已开启，按普通背包、材料袋、弹药袋分区显示。"
    UpdateViews()
end

ScheduleLayout = function()
    if not module.active or layoutTimer or not ContainerFrameCombinedBags:IsShown() then return end
    -- Run after native and !Pig layout hooks, including hooks installed later.
    layoutTimer = C_Timer.NewTimer(0, function()
        layoutTimer = nil
        opening = false
        Layout()
    end)
end

local function NativeReady()
    local frame = ContainerFrameCombinedBags
    return frame and type(frame.EnumerateValidItems) == "function" and type(frame.UpdateItemSlots) == "function"
        and type(frame.UpdateItemLayout) == "function" and type(frame.UpdateFrameSize) == "function"
        and EventRegistry and type(EventRegistry.RegisterCallback) == "function"
        and type(ContainerFrame_GenerateFrame) == "function" and type(C_Timer.NewTimer) == "function"
end

local function InstallHooks()
    if installed then return end
    installed = true
    local frame = ContainerFrameCombinedBags
    -- BankFrameBaseMixin opens bags before selecting its tab. Leave native bag routing intact
    -- so that the subsequent protected first-tab purchase stays in the Blizzard execution path.
    hooksecurefunc(frame, "UpdateItemSlots", function(self)
        if not module.active or InputUtil.IsGamepadUIEnabled() then return end
        -- Native generation creates the slots before Show, so prepare the opening anchor here.
        if not self:IsShown() then RestorePosition() end
    end)
    hooksecurefunc(frame, "UpdateItemLayout", ScheduleLayout)
    hooksecurefunc(frame, "UpdateFrameSize", ScheduleLayout)
    frame:HookScript("OnShow", function()
        opening = module.active
        RestorePosition()
        ScheduleLayout()
    end)
    hooksecurefunc("ContainerFrame_GenerateFrame", function(container)
        if container ~= frame or not opening then return end
        opening = false
        if layoutTimer then
            layoutTimer:Cancel()
            layoutTimer = nil
        end
        -- Generation reanchors after Show. Finish in this call, before the first rendered frame.
        Layout()
        RestorePosition()
    end)
    -- Native OnHide emits this event before rearranging windows and !Pig's saved-point hook.
    EventRegistry:RegisterCallback("ContainerFrame.CloseBag", function(_, container)
        if container ~= frame then return end
        SavePosition(container)
        opening = false
    end, module)
end

local function ApplyActive(enabled)
    local combined = GetCVar("combinedBags")
    if enabled == module.active and (not enabled or combined == "1") then
        ScheduleLayout()
        return
    end
    local config = Config()
    module.active = enabled
    if enabled then
        InstallHooks()
        if config.previousCombinedBags == nil then config.previousCombinedBags = combined end
        -- The client applies combinedBags through USE_COMBINED_BAGS_CHANGED.
        if combined ~= "1" then SetCVar("combinedBags", "1") end
        ScheduleLayout()
    else
        HideDecorations()
        retryLayout = false
        events:UnregisterEvent("BAG_UPDATE_DELAYED")
        local previous = config.previousCombinedBags
        config.previousCombinedBags = nil
        local frame = ContainerFrameCombinedBags
        if combined == "1" and previous == "0" then
            SetCVar("combinedBags", previous)
        elseif combined == "1" and frame:IsShown() then
            frame:UpdateFrameSize()
            frame:UpdateItemLayout()
        end
    end
end

Reconcile = function()
    if applying then return end
    if InCombatLockdown() then
        status = "设置已保存，脱战后应用背包布局。"
        UpdateViews()
        return
    end
    applying = true
    local enabled = module.IsEnabled()
    local conflict = enabled and Conflict()
    local gamepad = enabled and InputUtil and InputUtil.IsGamepadUIEnabled()
    if not NativeReady() then
        status = enabled and "等待原生背包界面加载。" or "背包整合已关闭。"
    else
        ApplyActive(enabled and not conflict and not gamepad)
        if conflict then
            status = "已暂停背包整合，" .. conflict .. " 正在接管背包。停用对应背包模块或插件并重载后可启用。"
        elseif gamepad then
            status = "手柄背包模式下暂停分区，使用客户端布局。"
        else
            status = enabled and "背包整合已开启，打开背包后显示分区。" or "背包整合已关闭。"
        end
    end
    applying = false
    UpdateViews()
end

function module.SetEnabled(enabled)
    local config = Config()
    if not config then return false end
    config.enabled = enabled == true
    Reconcile()
    return true
end

function module.BuildSettings(parent)
    local view = {}
    module.views[#module.views + 1] = view
    view.enabled = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    view.enabled:SetPoint("TOPLEFT", 4, -8)
    view.enabled:SetSize(28, 28)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", view.enabled, "RIGHT", 4, 0)
    label:SetText("启用背包整合")
    local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 8, -48)
    hint:SetJustifyH("LEFT")
    hint:SetText("整合窗口按普通背包、材料袋、弹药袋分区，空分区自动隐藏。客户端单独打开的材料袋沿用原生窗口。战斗中切换此开关在脱战后生效。")
    local compatibility = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    compatibility:SetPoint("TOPLEFT", 8, -110)
    compatibility:SetJustifyH("LEFT")
    compatibility:SetText("使用原生物品格子。兼容 !Pig 的行数、缩放与物品标记。检测到完整接管背包的插件时自动暂停。安装更新后首次使用需 /reload。")
    view.status = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    view.status:SetPoint("TOPLEFT", 8, -180)
    view.status:SetJustifyH("LEFT")
    view.enabled:SetScript("OnClick", function(self) module.SetEnabled(self:GetChecked()) end)
    local function Resize()
        local width = math.max(320, parent:GetWidth() - 16)
        hint:SetWidth(width)
        compatibility:SetWidth(width)
        view.status:SetWidth(width)
    end
    parent:SetScript("OnSizeChanged", Resize)
    parent:SetScript("OnShow", UpdateViews)
    Resize()
    UpdateViews()
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CVAR_UPDATE")
events:SetScript("OnEvent", function(_, event, name)
    if event == "BAG_UPDATE_DELAYED" then
        if retryLayout then ScheduleLayout() end
        return
    end
    if event == "CVAR_UPDATE" and name ~= "combinedBags" and name ~= "combinedbags" then return end
    if event == "ADDON_LOADED" and not module.IsEnabled() then return end
    Reconcile()
end)
