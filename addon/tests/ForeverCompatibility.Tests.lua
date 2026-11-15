-- Initialize each client source against its API contract and typed UI methods.
local flavor = TEST_FLAVOR or "forerver"
local root = TEST_ROOT or "."
local addon = root .. "/addon/"..flavor.."/wow_tools/"
local frames, names, widgets = {}, {}, {}
local scale, width, height, dead, free = 0.7, 1920, 1080, false, 10
local pole, enchants, channelName, channelID, castName, castID = true, {}, nil, nil, nil, nil
local apiFailure, cvarWrites, menuEntries = false, 0, {}
local targetGUID, targetName, interactable, interactCVar = nil, "模拟鱼漂", false, "3"
local guidFailure, interactFailure = false, false
local messages = {}
local gcValues, gcCalls = { setpause = 350, setstepmul = 250 }, 0
function collectgarbage(option, value)
    if option == "count" then return 1024 end
    assert(gcValues[option] and type(value) == "number", "Unexpected GC operation")
    gcCalls = gcCalls + 1
    local previous = gcValues[option]
    gcValues[option] = value
    return previous
end
function date() return "12:00:00" end
function InCombatLockdown() return false end
function ClearOverrideBindings() end
function SetOverrideBindingClick() end
local secret = setmetatable({}, {
    __eq = function() error("Compared a restricted value") end,
    __tostring = function() error("Printed a restricted value") end,
})
function issecretvalue(value) return rawequal(value, secret) end
local VisibilityChanged
local function widget(name, parent, kind)
    local object = { scripts = {}, events = {}, textures = {}, shown = true, text = "", enabled = true, mockParent = parent, kind = kind }
    function object:SetAttribute() end
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:HookScript(event, callback)
        local previous = self.scripts[event]
        self.scripts[event] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function object:RegisterEvent(event) self.events[event] = true end
    function object:UnregisterEvent(event) self.events[event] = nil end
    function object:CreateTexture()
        local texture = widget(nil, self, "Texture")
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function object:CreateMaskTexture() return widget() end
    function object:AddMaskTexture(mask) self.mask=mask end
    function object:RemoveMaskTexture(mask) if self.mask==mask then self.mask=nil end end
    function object:SetTextureSliceMargins(...) self.sliceMargins={ ... } end
    function object:ClearTextureSlice() self.sliceMargins=nil end
    function object:CreateFontString() return widget(nil, self, "FontString") end
    function object:GetParent() return self.mockParent end
    function object:SetFrameStrata(value) self.strata = value end
    function object:GetFrameStrata()
        return self.strata or (self.mockParent and self.mockParent:GetFrameStrata()) or "MEDIUM"
    end
    function object:IsVisible() return self.shown and (not self.mockParent or self.mockParent:IsVisible()) end
    function object:SetParent(parent)
        local visible = self:IsVisible()
        self.mockParent = parent
        VisibilityChanged(self, visible)
    end
    function object:GetEffectiveScale() return scale end
    function object:GetCenter() return 960, 540 end
    function object:SetSize(w, h) self.width, self.height = w, h end
    function object:GetWidth() return self.fill and self.fill:GetWidth() or self.width or 140 end
    function object:GetHeight() return self.fill and self.fill:GetHeight() or self.height or 140 end
    function object:SetWidth(value) self.width = value end
    function object:SetHeight(value) self.height = value end
    function object:SetAllPoints(target) self.fill = target or self.mockParent end
    function object:SetColorTexture(...) self.color = { ... } end
    function object:SetVertexColor(...) self.vertex = { ... } end
    function object:SetAlpha(value) self.alpha = value end
    function object:GetAlpha() return self.alpha or 1 end
    for _, state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
        object["Get"..state.."Texture"] = function(self) return self[state.."Texture"] end
        object["Set"..state.."Texture"] = function(self, texture) self[state.."Texture"] = texture end
    end
    function object:SetPoint(...) self.point = { ... } end
    function object:GetPoint() return "LEFT", nil, "CENTER", -20, 0 end
    function object:SetText(value)
        if self.text == value then return end
        self.text = value
        if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
    end
    function object:GetText() return self.text end
    function object:GetFontString()
        self.buttonText = self.buttonText or widget(nil, self, "FontString")
        return self.buttonText
    end
    function object:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
    function object:GetFont() return "mock-font", 12, "" end
    if kind == "FontString" then
        function object:GetStringHeight() return 36 end
        function object:GetStringWidth() return #self.text * 8 end
        function object:SetWordWrap(value) self.wordWrap = value end
        function object:SetMaxLines(value) self.maxLines = value end
        function object:SetDrawLayer() end
        function object:SetShadowColor() end
        function object:SetShadowOffset() end
    elseif kind == "Texture" then
        function object:SetHorizTile() end
        function object:SetVertTile() end
        function object:SetRotation(value) self.rotation = value end
    elseif kind == "StatusBar" then
        function object:SetStatusBarTexture(texture)
            self.statusTexture = widget(nil, self, "Texture")
            self.statusTexture:SetTexture(texture)
        end
        function object:GetStatusBarTexture() return self.statusTexture end
        function object:SetStatusBarColor(...) self.statusColor = {...} end
    elseif kind == "EditBox" then
        function object:GetNumLines()
            local _, newlines = self.text:gsub("\n", "")
            return self.mockLineCount or newlines + 1
        end
        function object:GetSpacing() return self.spacing or 0 end
    end
    function object:SetEnabled(value) self.enabled = value end
    function object:Enable() self.enabled = true end
    function object:Disable() self.enabled = false end
    function object:GetChecked() return self.checked end
    function object:SetNumeric(value) self.numeric = value end
    function object:SetChecked(value) self.checked = value end
    function object:Hide() local visible=self:IsVisible(); self.shown=false; VisibilityChanged(self,visible) end
    function object:Show() local visible=self:IsVisible(); self.shown=true; VisibilityChanged(self,visible) end
    function object:IsShown() return self.shown end
    function object:GetFrameLevel() return 1 end
    function object:SetValue(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function object:GetValue() return self.value end
    function object:GetThumbTexture() self.thumb = self.thumb or widget(nil, self); return self.thumb end
    function object:IsEnabled() return self.enabled end
    function object:IsMouseOver() return false end
    function object:SetupMenu(generator) self.generator = generator end
    function object:GenerateMenu()
        self.generator(self, {SetScrollMode=function() end, CreateRadio=function() end})
    end
    function object:SetDefaultText(text) self.defaultText = text end
    function object:CloseMenu() self.menuClosed = true end
    local harmless = {
        "SetBackdrop", "SetHitRectInsets", "SetFrameLevel", "SetScale", "SetButtonState", "LockHighlight", "UnlockHighlight", "SetClampedToScreen", "SetMovable", "EnableMouse",
        "RegisterForDrag", "RegisterForClicks", "SetHighlightTexture", "SetTexture",
        "ClearAllPoints", "SetFont", "SetJustifyH", "SetAutoFocus",
        "SetMaxLetters", "ClearFocus", "SetScrollChild", "StartMoving", "StopMovingOrSizing", "SetMultiLine", "SetFontObject", "SetBlendMode", "SetTexCoord",
        "SetOrientation", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture", "EnableMouseWheel", "SetTextColor",
    }
    for _, method in ipairs(harmless) do object[method] = function() end end
    widgets[#widgets + 1] = object
    object.lastVisible = object:IsVisible()
    if name then names[name] = object end
    return object
end
VisibilityChanged = function()
    local changes = {}
    for _, object in ipairs(widgets) do
        local visible = object:IsVisible()
        if visible ~= object.lastVisible then
            object.lastVisible = visible
            changes[#changes + 1] = {object=object, event=visible and "OnShow" or "OnHide"}
        end
    end
    for _, change in ipairs(changes) do
        local callback = change.object.scripts[change.event]
        if callback then callback(change.object) end
    end
end
function CreateFrame(kind, name, parent, template)
    assert(template ~= "UIDropDownMenuTemplate", "Forever still depends on legacy dropdown templates")
    local object = widget(name, parent, kind)
    object.template = template
    if template == "MaximizeMinimizeButtonFrameTemplate" then
        object.MaximizeButton = widget(nil, object, "Button")
        object.MinimizeButton = widget(nil, object, "Button")
    end
    if template == "UICheckButtonTemplate" then object.Text = widget(nil, object, "FontString") end
    if template == "MinimalTabTemplate" then
        object.Text = widget(nil, object, "FontString")
        function object:SetSelected(value) self.selected = value end
        function object:IsSelected() return self.selected == true end
        object:SetScript("OnClick", function(self) self.nativeClicks = (self.nativeClicks or 0) + 1 end)
    end
    if template == "BasicFrameTemplateWithInset" then
        object.TitleText = widget(nil, object, "FontString")
        object.Bg = widget(nil, object, "Texture")
        object.InsetBg = widget(nil, object, "Texture")
        object.TitleBg = widget(nil, object, "Texture")
        object.TopTileStreaks = widget(nil, object, "Texture")
    end
    frames[#frames + 1] = object
    return object
end
function CreateRadioButtonGroup()
    local group = { buttons = {} }
    function group:AddButton(button)
        self.buttons[#self.buttons + 1] = button
        button.selectionGroup = self
        local index = #self.buttons
        button:HookScript("OnClick", function() self:SelectAtIndex(index) end)
    end
    function group:SelectAtIndex(index)
        assert(self.buttons[index], "Radio selection is outside the registered tabs")
        for buttonIndex, button in ipairs(self.buttons) do
            button:SetSelected(buttonIndex == index)
        end
    end
    return group
end
UIParent, Minimap, FramerateFrame, GameTooltip = widget(), widget(), widget(), widget()
FramerateLabel = flavor=="titan" and widget() or nil
function GameTooltip:SetOwner() end
function GameTooltip:AddLine() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
YES, NO = "Yes", "No"
BackdropTemplateMixin = {}
local registeredCategories, addonCategories = {}, {}
Settings = { RegisterCanvasLayoutCategory = function(frame, name)
    local category = {frame=frame,name=name}
    registeredCategories[#registeredCategories + 1] = category
    return category
end, RegisterAddOnCategory = function(category) addonCategories[#addonCategories + 1] = category end }
function GetMinRenderScale() return 0.5 end
function GetMaxRenderScale() return 2 end
local resampleCVars = {ResampleQuality = "3", ResampleAlwaysSharpen = "0", ResampleSharpness = "0.2", RenderScale = "1"}
local textureCVars = {
    graphicsTextureResolution = flavor == "titan" and "1" or "2", textureFilteringMode = "5",
    worldBaseMip = "0", terrainMipLevel = "0", componentTextureLevel = "0", useHighResTextures = "1",
}
local allocationCVars = {
    componentTexCacheSize = "32", componentTexLoadLimit = "16", componentCompress = "1",
    GxAllowCachelessShaderMode = "0", ThreadPoolPerThreadAllocator = "1",
    FrameBufferCacheForceNoHeaps = "0", worldPreloadHighResTextures = "1",
}
C_CVar = { GetCVar = function(key)
    assert(type(key) == "string", "CVar getter requires a name")
    return key == "softTargetInteract" and interactCVar or resampleCVars[key] or textureCVars[key] or allocationCVars[key]
end, SetCVar = function(key, value)
    assert(type(key) == "string" and type(value) == "string", "CVar setter requires name and value strings")
    cvarWrites = cvarWrites + 1
end }
MenuUtil = { CreateContextMenu = function(owner, generator)
    menuEntries = {}
    local description = {
        CreateTitle = function() end,
        CreateCheckbox = function(_, title, isSelected, onSelect)
            menuEntries[#menuEntries + 1] = { title = title, isSelected = isSelected, onSelect = onSelect }
        end,
    }
    generator(owner, description)
end }
Enum = { WeaponSlot = {MainHand = 0}, ItemEnchantType = {Permanent = 1, Temporary = 2, Imbue = 3} }
ItemLocation = { CreateFromEquipmentSlot = function(_, slot) assert(slot == 16); return {slot = slot} end }
C_Item = {
    GetItemID = function(location) assert(location.slot == 16); return 1 end,
    GetItemInfoInstant = function() return 1, nil, nil, nil, nil, 2, pole and 20 or 7 end,
    GetWeaponEnchantInfo = function(slot)
        assert(flavor~="titan", "Titan used Forever's namespaced enchant list")
        assert(slot == Enum.WeaponSlot.MainHand, "Wrong weapon-slot enumeration")
        if apiFailure then error("Unavailable enchant scan") end
        return enchants
    end,
}
C_Spell = { GetSpellName = function() return "Fishing" end }
function GetInventoryItemLink(unit, slot)
    assert(unit=="player" and slot==16)
    return pole and "fishing-pole" or "sword"
end
function GetWeaponEnchantInfo()
    assert(flavor=="titan", "Forever used Titan's legacy enchant tuple")
    if apiFailure then error("Unavailable enchant scan") end
    for _, enchant in ipairs(enchants) do
        if enchant.enchantType==2 then return enchant.hasEnchant, enchant.timeLeft end
    end
    return false, nil
end
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function() return free, 0 end,
}
function UnitIsDeadOrGhost() return dead end
local ghost=false
UnitIsDead=UnitIsDeadOrGhost
function UnitIsGhost() return ghost end
function UnitClass() return "战士", "WARRIOR", 1 end
function GetPhysicalScreenSize() return width, height end
function UnitChannelInfo() return channelName, nil, nil, nil, nil, nil, nil, channelID end
function UnitCastingInfo() return castName, nil, nil, nil, nil, nil, "cast-guid", false, castID end
function UnitGUID(unit)
    assert(unit == "softinteract", "Wrong interaction target")
    if guidFailure then error("Unavailable GUID") end
    return targetGUID
end
function UnitIsInteractable(unit)
    assert(unit == "softinteract", "Wrong interactability target")
    if interactFailure then error("Unavailable interaction") end
    return interactable
end
function UnitName(unit) assert(unit == "softinteract"); return targetName end
function UnitExists() error("Do not reject GameObjects with UnitExists") end
-- Native pet contracts are present in both client sources.
function HasPetUI() return false, false end
function GetPetExperience() return 0, 1000 end
function UnitLevel(unit)
    assert(unit == "player" or unit == "pet", "Unexpected pet-level unit")
    return unit == "player" and 60 or 59
end
if flavor == "titan" then
    function GetMaxLevelForLatestExpansion() return 80 end
else
    function GetMaxPlayerLevel() return 60 end
end
local chatMock = dofile(root .. "/addon/tests/BigFootChannel.Mock.lua")
local originalHook = hooksecurefunc
function hooksecurefunc(target, method, callback)
    if type(target) == "table" and method == "SetBarText" then
        local original = target[method]
        target[method] = function(self, text) original(self, text); callback(self, text) end
    else originalHook(target, method, callback) end
end
local xpText = widget(nil, nil, "FontString")
local xpBar = {OverlayFrame = {Text = xpText}}
function xpBar:SetBarText(text) self.OverlayFrame.Text:SetText(text) end
function xpBar:UpdateCurrentText() self:SetBarText("100 / 1000") end
StatusTrackingBarInfo = {BarsEnum = {Experience = 4}}
StatusTrackingBarManager = {barContainers = {{bars = {[4] = xpBar}}}}
function GetXPExhaustion() return 12345 end
function UnitXP(unit) assert(unit == "player"); return 100 end
function UnitXPMax(unit) assert(unit == "player"); return 1000 end
for line in io.lines(addon .. "wow_tools.toc") do
    if line:match("%.lua%s*$") or line:match("%.xml%s*$") then
        chatMock.LoadAddonFile(addon .. line:gsub("\\", "/"):gsub("%s+$", ""))
    end
end
-- SavedVariables become available after the TOC scripts and before ADDON_LOADED.
if TEST_THIRD_PARTY_DISABLED then
    wowDetectorDB = {thirdPartyAddons = {bigfoot_channel = false, ls_toasts = false, forever_faces = false, better_vendor_ui = false, pet_xp_bar = false}}
end
for _, frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "wow_tools") end
end
assert(WoWTools and type(WoWTools.modules) == "table", "Addon namespace failed to initialize")
for _, name in ipairs({"wowDetector", "fight_detector", "pet_tamer", "button_style", "ui_addons"}) do
    assert(type(WoWTools.modules[name]) == "table", "Missing module export " .. name)
end
assert(WoWTools.settings and type(WoWTools.settings.Open) == "function", "Missing settings interface")
local experienceText = assert(WoWTools.experienceText, "Missing experience text module")
assert(type(experienceText.SetPercentEnabled) == "function"
    and type(experienceText.IsPercentEnabled) == "function", "Missing XP percentage interfaces")
assert(not experienceText.IsPercentEnabled(), "XP percentage must default to disabled")
assert(experienceText.SetEnabled(true) and experienceText.SetPercentEnabled(true), "XP text setters failed")
assert(wowDetectorDB.displayFonts.showRestedXP and wowDetectorDB.displayFonts.showXPPercent
    and xpText:GetText() == "100 / 1000（12345-10.0%）", "XP text API or persistence binding failed")
local experienceControl = assert(WoWTools.displayFonts.controls[1], "Missing experience font controls")
assert(experienceControl.key == "experience" and experienceControl.percent.kind == "CheckButton"
    and experienceControl.rested.kind == "CheckButton", "XP text options require independent checkboxes")
local settingsWindow, settingsCanvas = WoWTools.settings.window, WoWTools.settings.canvas
for _, texture in ipairs({settingsWindow.Bg, settingsWindow.InsetBg, settingsWindow.TitleBg, settingsCanvas.background}) do
    assert(texture.color and texture.color[1] == 32 / 255 and texture.color[2] == 32 / 255
        and texture.color[3] == 32 / 255 and texture.color[4] == 1, "Settings background must use opaque solid dark gray")
end
assert(not settingsWindow.TopTileStreaks:IsShown(), "Settings background retains native streak artwork")
assert(settingsCanvas.background:GetParent() == settingsCanvas and settingsCanvas.background.fill == settingsCanvas,
    "Solid settings background does not cover the shared canvas")
assert(WoWTools.settings.pages.button_style.frame == WoWTools.buttonStyle.panel
    and WoWTools.modules.button_style == WoWTools.buttonStyle, "Button skin page module binding failed")
assert(#WoWTools.buttonStyle.editors == 1, "Button skin editor is registered more than once")

local graphicControls, graphicTabs, uiTabs = {}, {}, {}
local graphicContent = WoWTools.settings.pages.inner_graphic_config.content
local uiContent = WoWTools.settings.pages.ui_addons.content
for _, frame in ipairs(frames) do
    local definition = frame.definition
    if definition and definition.cvar then
        assert(not graphicControls[definition.cvar], "Graphics control was registered twice " .. definition.cvar)
        graphicControls[definition.cvar] = frame
    end
    if frame.template == "MinimalTabTemplate" and frame:GetParent() == graphicContent then
        graphicTabs[frame.Text:GetText()] = frame
    elseif frame.template == "MinimalTabTemplate" and frame:GetParent() == uiContent then
        uiTabs[frame.Text:GetText()] = frame
    end
end
for _, name in ipairs({"缓存与分配", "界面", "字体", "Lua"}) do
    assert(uiTabs[name] and not graphicTabs[name], "UI category is bound to the wrong settings page " .. name)
end
for tabName, values in pairs({["重采样"] = resampleCVars, ["贴图质量"] = textureCVars, ["缓存与分配"] = allocationCVars}) do
    local tabs = tabName == "缓存与分配" and uiTabs or graphicTabs
    local tab = assert(tabs[tabName], "Missing settings tab " .. tabName)
    assert(tab.Text.wordWrap == false and tab:GetWidth() >= tab.Text:GetStringWidth(),
        "Graphics navigation does not fit its single-line label " .. tabName)
    local pageParent
    for key, value in pairs(values) do
        local control = assert(graphicControls[key], "Missing graphics control " .. key)
        local definition = control.definition
        assert(type(definition.description) == "string" and #definition.description > 0, "Missing graphics value descriptions")
        pageParent = pageParent or control:GetParent()
        assert(control:GetParent() == pageParent, "Graphics controls use different category pages")
        local content = tabName == "缓存与分配" and uiContent or graphicContent
        assert(pageParent:GetParent():GetParent() == content, "CVar control has the wrong settings host")
        if definition.numeric then
            assert(control.input.numeric == not definition.decimal, "Numeric CVar input mode does not match its type")
            assert(tonumber(control.input:GetText()) == tonumber(value), "CVar input binding failed")
        else
            assert(control:GetChecked() == (value ~= "0"), "Boolean CVar binding failed")
        end
    end
end
assert(graphicControls.graphicsTextureResolution.definition.maximum == (flavor == "titan" and 1 or 2),
    "Texture resolution enum uses the other client's range")
assert(graphicControls.textureFilteringMode.definition.maximum == 5
    and graphicControls.textureFilteringMode.definition.meanings[5], "Texture filtering enum contract failed")
assert(graphicControls.ThreadPoolPerThreadAllocator.definition.maximum == 2
    and graphicControls.ThreadPoolPerThreadAllocator.definition.meanings[0], "Thread allocator enum contract failed")
assert(graphicControls.ResampleQuality.definition.maximum == 3 and graphicControls.ResampleQuality.definition.meanings[0],
    "Resample quality enum contract failed")
assert(graphicControls.ResampleAlwaysSharpen.definition.meanings[0] and graphicControls.ResampleAlwaysSharpen.definition.meanings[1],
    "Sharpening boolean contract failed")
assert(graphicControls.ResampleSharpness.definition.disabledValue == -1 and graphicControls.ResampleSharpness.definition.maximum == 2,
    "Resample sharpness range contract failed")
assert(graphicControls.RenderScale.definition.minimum == GetMinRenderScale()
    and graphicControls.RenderScale.definition.maximum == GetMaxRenderScale(), "Render scale native bounds binding failed")

assert(WoWTools.luaGC and type(WoWTools.luaGC.Save) == "function", "Missing Lua GC settings interface")
assert(#WoWTools.luaGC.views > 0, "Missing Lua GC settings controls")
for _, view in ipairs(WoWTools.luaGC.views) do
    assert(view.period:GetText() == "60", "Lua GC period must default to 60 seconds")
end
local secondsLabel
for _, object in ipairs(widgets) do
    if object.kind == "FontString" and object:GetText() == "校准周期（秒）" then secondsLabel = object end
end
assert(secondsLabel, "Lua GC period unit must be seconds")

local petXP = WoWTools.petXPBar
assert(petXP == WoWTools.modules.pet_xp_bar, "Pet XP module export failed")
assert(WoWTools.settings.pages.pet_xp_bar.frame == petXP.settingsPanel, "Pet XP settings page binding failed")
assert(petXP.sourceVersion == "1.3.1" and petXP.sourceCommit == "0c5da2aef6b2b56e307a77e37151fe4675be6c82",
    "Pet XP upstream identity mismatch")
assert(petXP.Compat.isForever == (flavor == "forerver"), "Pet XP client identity mismatch")
assert(petXP.Compat.GetLevelCap() == (flavor == "titan" and 80 or 60), "Pet XP level-cap API binding failed")
if TEST_THIRD_PARTY_DISABLED then
    assert(not petXP.ready and not petXP.frame and not petXP.db, "Disabled Pet XP initialized its runtime")
else
    assert(petXP.ready and petXP.db == wowDetectorDB.petXPBar.db, "Pet XP account persistence binding failed")
    WoWTools.settings.Open("pet_xp_bar")
    assert(petXP.optionsPanel and petXP.optionsPanel.name == "宠物经验", "Pet XP options builder contract failed")
    assert(type(petXP.Refresh) == "function" and type(petXP.HandleCommand) == "function", "Pet XP runtime load order failed")
    WoWTools.settings.Open("wowDetector")
end

local vendor = WoWTools.betterVendorUI
assert(vendor and vendor == WoWTools.modules.better_vendor_ui, "Embedded vendor module export failed")
assert(WoWTools.settings.pages.better_vendor_ui.frame == vendor.settingsPanel, "Vendor settings page binding failed")
assert(vendor.sourceVersion == "1.3.1" and vendor.sourceFileID == 9436965, "Vendor upstream identity mismatch")
if TEST_THIRD_PARTY_DISABLED then
    assert(not vendor.ready and not vendor.DB, "Disabled vendor registered its runtime")
else
    assert(vendor.ready and vendor.DB == wowDetectorDB.betterVendorUI.db, "Vendor account persistence binding failed")
    assert(type(vendor.ToggleConfig) == "function" and type(vendor.PassesFilters) == "function", "Vendor source load order failed")
    assert(vendor.Get("knownRecipes") == true, "Known recipe marks lack their default")
    WoWTools.settings.Open("better_vendor_ui")
    assert(vendor.optionsPanel and vendor.optionsPanel:GetParent() == vendor.settingsPanel, "Vendor options were not embedded")
    assert(vendor.optionsPanel.name == "商人增强", "Vendor settings title is not localized")
    WoWTools.settings.Open("wowDetector")
end

local expectedCategories = {
    wowDetector="game_assist", fight_detector="game_assist", pet_tamer="game_assist",
    button_style="game_settings", inner_graphic_config="game_settings", ui_addons="game_settings", sound_control="game_settings",
    bigfoot_channel="third_party", ls_toasts="third_party", forever_faces="third_party", better_vendor_ui="third_party", pet_xp_bar="third_party", third_party="third_party",
}
assert(#WoWTools.settings.categories == 3, "Wrong primary settings category count")
local categoryWidth = math.max(1, settingsCanvas:GetWidth() - 16) / #WoWTools.settings.categories
local divider = assert(settingsCanvas.categoryDivider, "Missing primary navigation divider")
assert(divider:GetParent() == settingsCanvas and divider.kind == "Texture" and divider:GetHeight() == 1,
    "Primary divider texture binding failed")
assert(divider.point[1] == "TOPRIGHT" and divider.point[2] == settingsCanvas
    and divider.point[3] == "TOPRIGHT" and divider.point[4] == -8 and divider.point[5] == -49,
    "Primary divider must stretch across the canvas below the tabs")
assert(divider.color[1] == 0.4 and divider.color[2] == 0.4 and divider.color[3] == 0.4 and divider.color[4] == 1,
    "Primary divider color binding failed")
for index, label in ipairs({"游戏辅助", "游戏设置", "三方插件"}) do
    local category = WoWTools.settings.categories[index]
    local tab = WoWTools.settings.categoryTabs[category.key]
    assert(category.label == label and tab.Text:GetText() == label and tab.Text.wordWrap == false,
        "Primary category label binding failed")
    assert(tab.template == "MinimalTabTemplate" and tab.selectionGroup,
        "Primary navigation lacks the native tab/radio interface")
    assert(tab:GetParent() == settingsCanvas and tab.point[1] == "TOPLEFT"
        and tab.point[2] == 8 + (index - 1) * categoryWidth and tab.point[3] == -8,
        "Primary category anchor must use the top horizontal row")
    assert(tab:GetWidth() == categoryWidth and tab:GetHeight() == 37,
        "Primary tabs must divide the canvas width equally")
end
local secondaryRow = 0
for _, group in ipairs(WoWTools.settings.groups) do
    assert(group.category == expectedCategories[group.key], "Settings page has the wrong primary category " .. group.key)
    local tab = WoWTools.settings.tabs[group.key]
    assert(tab.Text:GetText() == group.label and tab.Text.wordWrap == false,
        "Secondary tab label is not a single unwrapped line")
    local activeCategory = group.category == WoWTools.settings.selectedCategory
    assert(tab:IsShown() == activeCategory, "Secondary navigation has the wrong category binding")
    if activeCategory then
        assert(tab.point[1] == "TOPLEFT" and tab.point[2] == 8 and tab.point[3] == -57 - secondaryRow * 45,
            "Secondary tab anchor must use the left column")
        secondaryRow = secondaryRow + 1
    end
end
assert(WoWTools.settings.tabs.third_party.Text:GetText() == "插件管理", "Plugin manager label binding failed")
assert(WoWTools.settings.pages.third_party and WoWTools.modules.third_party.BuildSettings,
    "Missing third-party settings interface")
assert(#WoWTools.thirdParty.entries == (flavor == "forerver" and 5 or 4), "Wrong client plugin list")
if TEST_THIRD_PARTY_DISABLED then
    assert(not WoWTools.lsToasts.C.db, "Disabled toast addon initialized its database")
    assert(not WoWTools.bigfootChannel.addon.db, "Disabled chat addon initialized its database")
else
    assert(WoWTools.lsToasts.C.db and WoWTools.bigfootChannel.addon.db, "Enabled addons failed to initialize")
end
if flavor == "forerver" then
    assert(WoWTools.foreverFaces ~= WoWTools.lsToasts, "Portrait and toast namespaces overlap")
    assert(WoWTools.settings.pages.forever_faces and WoWTools.modules.forever_faces == WoWTools.foreverFaces,
        "Missing unified portrait settings page or module")
    assert(WoWTools.settings.pages.forever_faces.frame == WoWTools.foreverFaces.settingsPanel,
        "Portrait settings page did not use the embedded settings interface")
    assert(WoWTools.foreverFaces.ToggleWindow == WoWTools.foreverFaces.Toggle,
        "Portrait legacy settings entry did not use the unified interface")
    assert(WoWTools.foreverFaces.DB() == wowDetectorDB.foreverFaces.db, "Portrait persistence binding failed")
    if not TEST_THIRD_PARTY_DISABLED then
        WoWTools.foreverFaces.InitLevelCircle()
        WoWTools.foreverFaces.InitPortraits()
        WoWTools.foreverFaces.InitUI()
        local portraitPanel = WoWTools.foreverFaces.settingsPanel
        local isVisible = portraitPanel.IsVisible
        portraitPanel.IsVisible = function() return true end
        WoWTools.foreverFaces.RefreshSettings()
        portraitPanel.IsVisible = isVisible
        assert(ForeverFacesWindow:GetParent() == portraitPanel.content,
            "Portrait controls did not initialize in the unified settings card")
        local unitPortraitHook = chatMock.hooks.UnitFramePortrait_Update
        assert(type(unitPortraitHook) == "function", "Missing native unit-frame portrait hook")
        local unitFrame = CreateFrame("Frame")
        unitFrame:SetAttribute("unit", "target")
        unitFrame.unit = "target"
        unitFrame.portrait = {
            GetObjectType = function() return "Texture" end,
            GetParent = function() return unitFrame end,
            GetSize = function() return 58, 58 end,
            GetAlpha = function() return 1 end,
            IsShown = function() return false end,
        }
        local originalGUID, boundUnit = UnitGUID
        UnitGUID = function(unit) boundUnit = unit end
        unitPortraitHook(unitFrame)
        UnitGUID = originalGUID
        assert(boundUnit == "target", "Native unit-frame portrait argument binding failed")
    end
else
    assert(not WoWTools.foreverFaces, "Forever portraits loaded on Titan")
    assert(not WoWTools.settings.pages.forever_faces, "Forever portrait settings registered on Titan")
end
assert(#registeredCategories == 1 and #addonCategories == 1, "Settings category interface failed")
for _, name in ipairs({"WOWDETECTOR", "FIGHTDETECTOR", "WOWTOOLS"}) do
    assert(type(SlashCmdList[name]) == "function", "Missing slash-command interface " .. name)
end
print("PASS: " .. flavor .. " TOC initialization, third-party " .. (TEST_THIRD_PARTY_DISABLED and "disabled" or "enabled")
    .. " module exports, native templates and typed UI/API compatibility.")
