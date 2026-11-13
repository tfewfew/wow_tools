-- One settings canvas is shared by the minimap window and Blizzard's addon category.
local settings = { pages = {}, tabs = {} }
WoWTools.settings = settings
local groups = {
    { key="wowDetector", label="钓鱼检测" },
    { key="fight_detector", label="战斗检测" },
    { key="inner_graphic_config", label="画面设置" },
    { key="pet_tamer", label="自动抓宠" },
    { key="sound_control", label="声音控制" },
    { key="bigfoot_channel", label="大脚聊天", app="WoWToolsBigFootChannel" },
    { key="ls_toasts", label="lsToast", app="ls_Toasts" },
    { key="forever_faces", label="3D头像" },
    { key="third_party", label="三方插件" },
}
settings.groups = groups
local selected = "wowDetector"

local window = CreateFrame("Frame", "WoWToolsSettingsWindow", UIParent, "BasicFrameTemplateWithInset")
window:SetSize(980, 680)
window:SetPoint("CENTER")
window:SetFrameStrata("DIALOG")
window:SetClampedToScreen(true)
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window.TitleText:SetText("wow_tools")
window:Hide()
UISpecialFrames[#UISpecialFrames + 1] = "WoWToolsSettingsWindow"
local windowContent = CreateFrame("Frame", nil, window)
windowContent:SetPoint("TOPLEFT", 8, -32)
windowContent:SetPoint("BOTTOMRIGHT", -8, 8)

local panel = CreateFrame("Frame", "WoWToolsSettingsPanel", UIParent)
panel.name = "wow_tools"
panel:Hide()
local canvas = CreateFrame("Frame", "WoWToolsSettingsCanvas", windowContent)
canvas:SetAllPoints(windowContent)
canvas:Hide()
settings.window, settings.panel, settings.canvas = window, panel, canvas

local function RenderAce(page, subgroup)
    if not WoWTools.thirdParty.IsActive(page.key) then
        if page.container then page.container.frame:Hide() end
        page.message:SetText("此插件已停用，可在“三方插件”中勾选并重载后启用。")
        page.message:Show()
        return
    end
    local ready = page.key == "ls_toasts" and WoWTools.lsToasts.ready
        or page.key == "bigfoot_channel" and WoWTools.bigfootChannel.addon and WoWTools.bigfootChannel.addon.db
    local blocked = page.key == "ls_toasts" and InCombatLockdown()
    if not ready or blocked then
        if page.container then page.container.frame:Hide() end
        page.message:SetText(blocked and "战斗中暂停编辑 lsToast 设置，脱战后恢复。" or "模块正在初始化，请稍候。")
        page.message:Show()
        page.subgroup = subgroup or page.subgroup
        return
    end
    local dialog = LibStub("AceConfigDialog-3.0")
    if not page.container then
        local container = LibStub("AceGUI-3.0"):Create("SimpleGroup")
        container:SetAutoAdjustHeight(false)
        container:SetLayout("Fill")
        container.frame:SetParent(page)
        container.frame:SetFrameStrata(page:GetFrameStrata())
        container.frame:SetFrameLevel(page:GetFrameLevel() + 1)
        container.frame:SetAllPoints(page)
        container:SetWidth(page:GetWidth())
        container:SetHeight(page:GetHeight())
        -- Ace's custom-container registry preserves its normal option/profile refresh path.
        dialog.BlizOptions = dialog.BlizOptions or {}
        dialog.BlizOptions[page.app] = dialog.BlizOptions[page.app] or {}
        dialog.BlizOptions[page.app].wow_tools = container
        page.container = container
        dialog:Open(page.app, container)
    elseif page.needsRefresh then
        dialog:Open(page.app, page.container)
    end
    page.needsRefresh = false
    page.message:Hide()
    page.container.frame:Show()
    local path = subgroup or page.subgroup
    if path then dialog:SelectGroup(page.app, path) end
    page.subgroup = nil
end

function settings:OnConfigChanged(_, app)
    for _, page in pairs(self.pages) do
        if page.app == app and not page:IsVisible() then page.needsRefresh = true end
    end
end
LibStub("AceConfigRegistry-3.0").RegisterCallback(settings, "ConfigTableChange", "OnConfigChanged")

local tabGroup = CreateRadioButtonGroup()
local function Select(key, subgroup)
    local selectedPage = settings.pages[key]
    if not selectedPage then return end
    selected = key
    settings.selected = key
    for index, group in ipairs(groups) do
        local page = settings.pages[group.key]
        if group.key == selected then
            tabGroup:SelectAtIndex(index)
            page:Show()
        else
            page:Hide()
        end
    end
    if selectedPage.app then RenderAce(selectedPage, subgroup) end
end
settings.Select = Select

local function LayoutTabs()
    for index, group in ipairs(groups) do
        local tab = settings.tabs[group.key]
        tab:SetSize(132, 37)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", 8, -12 - (index - 1) * 45)
    end
end

for _, group in ipairs(groups) do
    local key = group.key
    local page = CreateFrame("Frame", nil, canvas)
    page:SetPoint("TOPLEFT", 156, -8)
    page:SetPoint("BOTTOMRIGHT", -8, 8)
    page.key, page.app = key, group.app
    page:Hide()
    settings.pages[key] = page
    local tab = CreateFrame("Button", nil, canvas, "MinimalTabTemplate")
    tab.Text:SetText(group.label)
    tab.Text:SetWordWrap(false)
    tab.Text:SetJustifyH("CENTER")
    tabGroup:AddButton(tab)
    tab:HookScript("OnClick", function() Select(key) end)
    settings.tabs[key] = tab
    if group.app then
        page.message = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        page.message:SetPoint("TOPLEFT", 16, -16)
        page.message:SetWidth(540)
        page.message:SetJustifyH("LEFT")
        page:SetScript("OnShow", function() RenderAce(page) end)
    else
        local content = CreateFrame("Frame", nil, page)
        content:SetAllPoints(page)
        page.content = content
        page.frame = WoWTools.modules[key].BuildSettings(content)
    end
end
Select(selected)
LayoutTabs()
canvas:SetScript("OnSizeChanged", LayoutTabs)

local elapsed = 0
canvas:SetScript("OnShow", function(self)
    elapsed = 0
    LayoutTabs()
    self:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then
            elapsed = 0
            local module = WoWTools.modules[selected]
            if module.RefreshSettings then module.RefreshSettings() end
        end
    end)
end)
canvas:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

local function Attach(host)
    if canvas:GetParent() == host and canvas:IsVisible() then return end
    canvas:Hide()
    canvas:SetParent(host)
    canvas:ClearAllPoints()
    canvas:SetAllPoints(host)
    local strata = host:GetFrameStrata()
    canvas:SetFrameStrata(strata)
    for _, page in pairs(settings.pages) do
        if page.frame then
            page.frame:SetFrameStrata(strata)
            page.frame:SetFrameLevel(page.content:GetFrameLevel() + 1)
        end
        if page.container then
            page.container.frame:SetFrameStrata(strata)
            page.container.frame:SetFrameLevel(page:GetFrameLevel() + 1)
        end
    end
    canvas:Show()
    LayoutTabs()
end

function settings.Open(key, subgroup)
    if panel:IsVisible() then
        window:Hide()
        Attach(panel)
    else
        local scale = math.min(1, (UIParent:GetWidth() - 32) / 980, (UIParent:GetHeight() - 48) / 680)
        window:SetScale(math.max(0.1, scale))
        window:Show()
        Attach(windowContent)
    end
    Select(key or selected, subgroup)
end

function settings.IsGroupShown(key)
    return canvas:IsVisible() and selected == key
end

function settings.HideGroup(key)
    if not settings.IsGroupShown(key) then return end
    if window:IsShown() then window:Hide() else Select("wowDetector") end
end

function settings.Toggle(key)
    if settings.IsGroupShown(key) then settings.HideGroup(key) else settings.Open(key) end
end

window:SetScript("OnShow", function() Attach(windowContent) end)
window:SetScript("OnHide", function()
    if canvas:GetParent() == windowContent then canvas:Hide() end
end)
panel:SetScript("OnShow", function()
    window:Hide()
    Attach(panel)
end)
panel:SetScript("OnHide", function()
    if canvas:GetParent() == panel then canvas:Hide() end
end)
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    settings.category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settings.category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    local page = settings.pages[selected]
    if canvas:IsShown() and page.app then RenderAce(page) end
end)
