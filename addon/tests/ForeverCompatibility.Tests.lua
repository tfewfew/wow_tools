-- Full addon smoke test with Forever's namespaced APIs, modern menu and FPS frame.
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
        local texture = widget(nil, self)
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
    function object:GetFont() return "mock-font", 12, "" end
    if kind == "FontString" then
        function object:GetStringHeight() return 36 end
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
    function object:SetupMenu(generator) self.generator = generator end
    function object:GenerateMenu()
        self.generator(self, {SetScrollMode=function() end, CreateRadio=function() end})
    end
    function object:SetDefaultText(text) self.defaultText = text end
    function object:CloseMenu() self.menuClosed = true end
    local harmless = {
        "SetFrameLevel", "SetScale", "SetButtonState", "LockHighlight", "UnlockHighlight", "SetClampedToScreen", "SetMovable", "EnableMouse",
        "RegisterForDrag", "RegisterForClicks", "SetHighlightTexture", "SetTexture",
        "ClearAllPoints", "SetFont", "SetJustifyH", "SetAutoFocus",
        "SetMaxLetters", "SetNumeric", "ClearFocus", "SetScrollChild", "StartMoving", "StopMovingOrSizing", "SetMultiLine", "SetFontObject", "SetBlendMode", "SetTexCoord",
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
    if template == "MinimalTabTemplate" then
        object.Text = widget(nil, object, "FontString")
        function object:SetSelected(value) self.selected = value end
        function object:IsSelected() return self.selected == true end
        object:SetScript("OnClick", function(self) self.nativeClicks = (self.nativeClicks or 0) + 1 end)
    end
    if template == "BasicFrameTemplateWithInset" then object.TitleText = widget() end
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
SlashCmdList, UISpecialFrames = {}, {}
local registeredCategories, addonCategories = {}, {}
Settings = { RegisterCanvasLayoutCategory = function(frame, name)
    local category = {frame=frame,name=name}
    registeredCategories[#registeredCategories + 1] = category
    return category
end, RegisterAddOnCategory = function(category) addonCategories[#addonCategories + 1] = category end }
C_CVar = { GetCVar = function(key) return key == "softTargetInteract" and interactCVar or nil end,
    SetCVar = function() cvarWrites = cvarWrites + 1 end }
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
for line in io.lines(addon .. "wow_tools.toc") do
    if line:match("%.lua%s*$") or line:match("%.xml%s*$") then
        chatMock.LoadAddonFile(addon .. line:gsub("\\", "/"):gsub("%s+$", ""))
    end
end
for _, frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "wow_tools") end
end
chatMock.toasts.loggedIn=true
chatMock.toasts.Fire("PLAYER_LOGIN")
local panel, compat = names.wowDetectorPanel, WoWTools.compat
local indicator, lure = panel.textures[2], panel.textures[3]
local function assertColor(texture, r, g, b)
    assert(texture.color[1] == r and texture.color[2] == g and texture.color[3] == b, "Unexpected detection color")
end
local function tick()
    for _, frame in ipairs(frames) do
        if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.1) end
    end
end
assert(not panel.shown and not wowDetectorDB.locked, "Monitor did not default off/hidden")
assert(cvarWrites == 0, "Port changed graphics automatically")
assert(gcCalls == 0 and WoWTools.luaGC and #WoWTools.luaGC.views == 1,
    "Lua settings changed GC during addon loading or duplicated the shared settings view")
local restedControl = WoWTools.displayFonts.controls[1].rested
assert(restedControl and not restedControl:GetChecked(), "Unified font settings missed the default-off rested XP checkbox")
restedControl:SetChecked(true)
restedControl.scripts.OnClick(restedControl)
assert(xpText:GetText() == "100 / 1000（12345）" and wowDetectorDB.displayFonts.showRestedXP,
    "The full TOC/settings entry point failed to enable the digits-only rested XP suffix")
restedControl:SetChecked(false)
restedControl.scripts.OnClick(restedControl)
assert(xpText:GetText() == "100 / 1000" and not wowDetectorDB.displayFonts.showRestedXP,
    "The full TOC/settings checkbox failed to remove the suffix immediately")
local luaTabs, luaTab = 0, nil
for _, frame in ipairs(frames) do
    if frame.Text and frame.Text.text == "Lua" then
        luaTabs = luaTabs + 1
        luaTab = frame
        frame.scripts.OnClick()
    end
end
assert(luaTabs == 1, "The unified settings canvas must own exactly one Lua tab")
local luaView = WoWTools.luaGC.views[1]
luaView.refresh.scripts.OnClick()
assert(gcValues.setpause == 350 and gcValues.setstepmul == 250 and luaView.system.pause.text == "350")
luaView.inputs.pause:SetText("400")
luaView.inputs.stepmul:SetText("200")
luaView.period:SetText("0")
luaView.apply.scripts.OnClick()
assert(gcValues.setpause == 400 and gcValues.setstepmul == 200 and wowDetectorDB.luaGC.pause == 400)
gcValues.setpause = 150
luaView.calibrate.scripts.OnClick()
assert(gcValues.setpause == 400 and luaView.saved.pause.text == "400" and luaView.system.pause.text == "400",
    "Full-TOC Lua settings entry points did not restore saved values")
for _, control in ipairs(widgets) do
    if control.definition and control.definition.cvar then
        if control.definition.numeric then
            assert(not control.input.enabled and not control.apply.enabled, "Unsupported numeric CVar remained editable")
        else
            assert(not control.enabled, "Unsupported boolean CVar remained editable")
        end
    end
end
SlashCmdList.WOWDETECTOR("on")
assertColor(indicator, 1, 0, 0)
assertColor(lure, 1, 0, 1)
enchants = { {hasEnchant=true, enchantType=1, timeLeft=600000}, {hasEnchant=true, enchantType=3, timeLeft=600000} }
if compat then
assert(compat.GetLureState() == "missing", "Permanent enchant/imbue counted as lure")
enchants[#enchants + 1] = {hasEnchant=true, enchantType=2, timeLeft=600000}
panel.scripts.OnEvent(panel, "WEAPON_ENCHANT_CHANGED")
assertColor(lure, 0, 0, 1)
enchants[3].timeLeft = 0
assert(compat.GetLureState() == "missing", "Expired lure remained effective")
enchants[3].timeLeft = secret
assert(compat.GetLureState() == "unknown", "Restricted duration treated as missing")
apiFailure = true
assert(compat.GetLureState() == "unknown", "Failed enchant scan treated as missing")
apiFailure = false
enchants = {{hasEnchant=true}}
assert(compat.GetLureState() == "unknown", "Malformed enchant treated as missing")
pole = false
assert(compat.GetLureState() == "unknown", "Non-pole accepted")
else
    enchants[#enchants + 1] = {hasEnchant=true, enchantType=2, timeLeft=600000}
    panel.scripts.OnEvent(panel, "PLAYER_EQUIPMENT_CHANGED")
    assertColor(lure, 0, 0, 1)
    enchants[3].timeLeft = 0
    panel.scripts.OnEvent(panel, "PLAYER_EQUIPMENT_CHANGED")
    assertColor(lure, 1, 0, 1)
    apiFailure = true
    panel.scripts.OnEvent(panel, "PLAYER_EQUIPMENT_CHANGED")
    assertColor(lure, 0.5, 0.5, 0.5)
    apiFailure = false
end
pole, enchants = true, {}
channelName, channelID = "Fishing", 7620
panel.scripts.OnEvent(panel, "UNIT_SPELLCAST_CHANNEL_START", "player")
assertColor(indicator, 1, 0, 0)
assert(panel.events.PLAYER_SOFT_INTERACT_CHANGED, "Soft interaction event was not registered")
targetGUID, interactable = "GameObject-0-1-2-3-4-5", true
panel.scripts.OnEvent(panel, "PLAYER_SOFT_INTERACT_CHANGED", secret, secret)
assertColor(indicator, 0, 1, 0)
SlashCmdList.WOWDETECTOR("status")
local diagnostic = messages[#messages - 1]
assert(diagnostic:find("交互目标=present", 1, true) and diagnostic:find(targetGUID, 1, true)
    and diagnostic:find(targetName, 1, true) and diagnostic:find("softTargetInteract=3", 1, true),
    "Missing interaction diagnostics")
targetGUID = nil
panel.scripts.OnEvent(panel, "PLAYER_SOFT_INTERACT_CHANGED", secret, secret)
assertColor(indicator, 1, 0, 0)
targetGUID = "GameObject-0-1-2-3-4-6"
tick()
assertColor(indicator, 0, 1, 0)
interactable = false
tick()
assertColor(indicator, 1, 0, 0)
interactable = true
tick()
assertColor(indicator, 0, 1, 0)
targetGUID = nil
tick()
assertColor(indicator, 1, 0, 0)
targetGUID = "GameObject-0-1-2-3-4-6"
channelName, channelID = "Other channel", 123
panel.scripts.OnEvent(panel, "UNIT_SPELLCAST_CHANNEL_START", "player")
assertColor(indicator, 1, 0, 0)
channelName, channelID, castName, castID = nil, nil, "Localized fishing", 7620
if compat then assert(compat.GetFishingState() == false, "Cast counted as a ready fishing channel") end
panel.scripts.OnEvent(panel, "UNIT_SPELLCAST_START", "player")
assertColor(indicator, 1, 0, 0)
castName, castID = "Other cast", 123
if compat then assert(compat.GetFishingState() == false, "Non-fishing cast accepted") end
castName, castID, channelName, channelID = nil, nil, "Fishing", 7731
if compat then assert(compat.GetFishingState() == true, "Localized name fallback rejected another fishing rank") end
tick()
assertColor(indicator, 0, 1, 0)
local guidAPI, interactAPI = UnitGUID, UnitIsInteractable
UnitGUID = nil
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
UnitGUID, UnitIsInteractable = guidAPI, nil
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
UnitIsInteractable, guidFailure = interactAPI, true
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
guidFailure, interactFailure = false, true
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
interactFailure, interactable = false, nil
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
interactable, targetGUID = true, 42
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
targetGUID, targetName, interactCVar = secret, secret, secret
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
SlashCmdList.WOWDETECTOR("status") -- must not compare or print restricted target/CVar data.
targetGUID, targetName, interactCVar, interactable = "GameObject-0-1-2-3-4-6", "模拟鱼漂", "3", secret
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
SlashCmdList.WOWDETECTOR("status")
interactable = true
tick()
assertColor(indicator, 0, 1, 0)
SlashCmdList.WOWDETECTOR("off")
assertColor(indicator, 0.5, 0.5, 0.5)
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
targetGUID = nil
SlashCmdList.WOWDETECTOR("on")
assertColor(indicator, 1, 0, 0)
castName, castID, channelName, channelID = nil, nil, secret, secret
panel.scripts.OnEvent(panel, "UNIT_SPELLCAST_CHANNEL_START", "player")
assertColor(indicator, 0.5, 0.5, 0.5)
if compat then assert(compat.GetFishingState() == nil, "Restricted cast did not stay unknown") end
SlashCmdList.WOWDETECTOR("status") -- must not print restricted values.
channelName, channelID, free, targetGUID = "Fishing", 7620, 0, secret
panel.scripts.OnEvent(panel, "BAG_UPDATE_DELAYED")
assertColor(indicator, 1, 1, 0)
free = nil
tick()
assertColor(indicator, 0.5, 0.5, 0.5)
channelName, channelID, targetGUID, free = nil, nil, nil, 10
for _, viewport in ipairs({{800,450},{1920,1080},{3840,2160}}) do
    width, height = viewport[1], viewport[2]
    panel.scripts.OnEvent(panel, "DISPLAY_SIZE_CHANGED")
    assert(math.abs(lure.point[4] * scale * height / 768 - 32) < 0.001, "Forever lure offset moved on resize")
end
dead = secret
panel.scripts.OnEvent(panel, "BAG_UPDATE_DELAYED")
assertColor(indicator, 0.5, 0.5, 0.5)
assert(WoWTools.modules.wowDetector.IsEnabled(), "Unreadable death status stopped or falsely excluded the character")
dead = true
panel.scripts.OnEvent(panel, "PLAYER_DEAD")
assertColor(indicator, 0, 1, 1)
assert(not wowDetectorDB.locked and panel.shown, "Death changed visibility/kept lock")
dead = false
panel.scripts.OnEvent(panel, "PLAYER_ALIVE")
assertColor(indicator, 0, 1, 1)
SlashCmdList.WOWTOOLS()
local unified = WoWTools.settings
assert(#unified.groups == 7 and unified.window:IsShown() and not WoWTools.modules.wowDetector.IsEnabled(),
    "Opening unified settings started a detector or omitted an existing menu group")
assert(#registeredCategories == 1 and #addonCategories == 1 and addonCategories[1] == unified.category
    and registeredCategories[1] == unified.category and registeredCategories[1].name == "wow_tools"
    and registeredCategories[1].frame == unified.panel, "Duplicate or indirect addon settings categories remain")
local expectedTabLabels = {
    wowDetector = "钓鱼\n检测", fight_detector = "战斗\n检测", inner_graphic_config = "画面\n设置",
    pet_tamer = "自动\n抓宠", sound_control = "声音\n控制", bigfoot_channel = "大脚\n聊天",
    ls_toasts = "lsTo\nast",
}
local primaryTabGroup
for _, group in ipairs(unified.groups) do
    local tab = unified.tabs[group.key]
    assert(tab and unified.pages[group.key] and tab.template == "MinimalTabTemplate",
        "Primary settings navigation must use the native tab template")
    assert(tab.Text:GetText() == expectedTabLabels[group.key],
        "Tab labels must split evenly by UTF-8 characters, with the extra character on the first line")
    primaryTabGroup = primaryTabGroup or tab.selectionGroup
    assert(tab.selectionGroup == primaryTabGroup and #primaryTabGroup.buttons == #unified.groups,
        "Primary tabs must share one native radio selection group")
    tab.scripts.OnClick(tab)
    assert(unified.selected == group.key and tab.nativeClicks == 1,
        "Clicking a primary tab must retain its native handler and select the matching page")
    tab.scripts.OnClick(tab)
    assert(tab:IsSelected() and tab.nativeClicks == 2, "Clicking the active tab must keep it selected")
    for _, other in ipairs(unified.groups) do
        local active = other.key == group.key
        assert(unified.tabs[other.key]:IsSelected() == active and unified.pages[other.key]:IsShown() == active,
            "Tab selection and page visibility must change together")
    end
end
unified.Select("wowDetector")
assert(unified.tabs.wowDetector:IsSelected(), "Programmatic navigation did not select the native tab")
WoWTools.modules.ls_toasts.Toggle()
assert(WoWTools.modules.ls_toasts.IsShown(), "Toast settings menu did not open")
assert(chatMock.customContainers.ls_Toasts and not LibStub("AceConfigDialog-3.0").OpenFrames.ls_Toasts,
    "Toast settings escaped into a standalone Ace window")
WoWTools.modules.ls_toasts.Toggle()
assert(not WoWTools.modules.ls_toasts.IsShown(), "Toast settings menu did not close")
WoWTools.modules.bigfoot_channel.Toggle()
assert(WoWTools.modules.bigfoot_channel.IsShown(), "Chat settings menu did not open")
SlashCmdList.WOWTOOLSBIGFOOTFILTER()
assert(chatMock.selectedTab == "filters" and chatMock.customContainers.WoWToolsBigFootChannel,
    "Chat filter shortcut failed to select the embedded group")
WoWTools.modules.bigfoot_channel.Toggle()
assert(not WoWTools.modules.bigfoot_channel.IsShown(), "Chat settings menu did not close")
WoWTools.modules.inner_graphic_config.Show()
assert(unified.IsGroupShown("inner_graphic_config") and not wowDetectorDB.locked, "Graphics shortcut selected the wrong group")
WoWTools.modules.wowDetector.Toggle()
assert(not panel.shown, "Monitor close did not hide")
WoWTools.modules.wowDetector.Toggle()
assert(panel.shown and wowDetectorDB.locked, "Monitor open did not start/lock")
assert(WoWTools.modules.wowDetector.IsEnabled(),"Forever active fishing not exposed to loot")
unified.Open("pet_tamer")
assert(WoWTools.modules.wowDetector.IsEnabled() and not WoWTools.modules.pet_tamer.IsEnabled(),
    "Browsing the taming page changed the active detector")
WoWTools.modules.pet_tamer.Toggle()
assert(WoWTools.modules.pet_tamer.IsEnabled() and not WoWTools.modules.wowDetector.IsEnabled(),"Taming menu did not exclude real fishing detector")
unified.Select("sound_control")
unified.window:Hide()
assert(WoWTools.modules.pet_tamer.IsEnabled() and names.wowToolsPetTamerSignal:IsShown(),
    "Switching tabs or closing settings stopped the active taming detector")
assert(not names.wowToolsSoundSettingsPanel.events.CVAR_UPDATE,
    "Hidden embedded sound controls retained their UI subscriptions")
SlashCmdList.WOWDETECTOR("on")
assert(not WoWTools.modules.pet_tamer.IsEnabled() and not names.wowToolsPetTamerSignal.shown,"Fishing retained real taming pixels")
SlashCmdList.WOWDETECTOR("off")
assert(not WoWTools.modules.wowDetector.IsEnabled(),"Forever visible disabled panel enables loot")
SlashCmdList.WOWDETECTOR("on")
SlashCmdList.WOWDETECTOR("hide")
assert(WoWTools.modules.wowDetector.IsEnabled(),"Forever hidden active fishing disables loot")
dead=true; panel.scripts.OnEvent(panel,"PLAYER_DEAD")
assert(not WoWTools.modules.wowDetector.IsEnabled(),"Forever death leaves loot enabled")
dead=false;SlashCmdList.WOWDETECTOR("on");ghost=true
panel.scripts.OnEvent(panel,"PLAYER_ENTERING_WORLD")
assertColor(indicator,0.5,0.5,0.5)
assert(not WoWTools.modules.wowDetector.IsEnabled(),"Ghost state emitted a death signal or kept fishing active")
ghost=false
local fpsApplied = false
for _, control in ipairs(widgets) do
    if control.definition and control.definition.action then
        control.inputX:SetText("0"); control.inputY:SetText("180")
        control.apply.scripts.OnClick()
        fpsApplied = true
        break
    end
end
local fpsRegion = flavor=="titan" and FramerateLabel or FramerateFrame
assert(fpsApplied and fpsRegion.point[1] == "BOTTOM" and fpsRegion.point[5] == 180,
    "The client's native FPS region could not be repositioned")
assert(cvarWrites == 0, "Read-only actions changed graphics CVars")
-- Both normal settings entry points attach the same canvas and retain uncommitted edits.
unified.Open("inner_graphic_config")
luaView.inputs.pause:SetText("666")
luaView.inputs.pause.scripts.OnTextChanged(luaView.inputs.pause, true)
local sharedCanvas = unified.canvas
unified.panel:SetFrameStrata("FULLSCREEN_DIALOG")
unified.panel:Show()
assert(not unified.window:IsShown() and sharedCanvas:GetParent() == unified.panel and sharedCanvas:IsShown(),
    "The native addon category did not directly host the shared settings canvas")
assert(unified.tabs.inner_graphic_config:IsSelected()
    and unified.tabs.inner_graphic_config.Text:GetText() == expectedTabLabels.inner_graphic_config,
    "Changing settings hosts lost native tab selection or its two-line label")
assert(#WoWTools.luaGC.views == 1 and luaView.inputs.pause:GetText() == "666"
    and luaView.saved.pause.text == "400", "Moving settings into the native category lost or saved a draft")
assert(names.wowToolsFightDetectorPanel:GetFrameStrata() == "FULLSCREEN_DIALOG"
    and names.wowToolsSoundSettingsPanel:GetFrameStrata() == "FULLSCREEN_DIALOG",
    "Embedded controls remained below the native settings host")
names.wowToolsMinimapButton.scripts.OnClick(names.wowToolsMinimapButton, "RightButton")
assert(not unified.window:IsShown() and sharedCanvas:GetParent() == unified.panel,
    "A minimap click created a second settings surface while the native category was open")
unified.panel:Hide()
names.wowToolsMinimapButton.scripts.OnClick(names.wowToolsMinimapButton, "RightButton")
assert(unified.window:IsShown() and sharedCanvas == unified.canvas and sharedCanvas:GetParent() ~= unified.panel)
assert(names.wowToolsFightDetectorPanel:GetFrameStrata() == "DIALOG",
    "Returning to the standalone host retained the old native settings layer")
assert(luaView.inputs.pause:GetText() == "666" and #WoWTools.luaGC.views == 1)

-- Embedded Ace groups retain their normal registry refresh and combat lifecycle.
unified.Open("bigfoot_channel")
local embeddedChat = unified.pages.bigfoot_channel.container
local opens = embeddedChat.opens
unified.Select("sound_control")
LibStub("AceConfigRegistry-3.0"):NotifyChange("WoWToolsBigFootChannel")
unified.Select("bigfoot_channel")
assert(embeddedChat == unified.pages.bigfoot_channel.container and embeddedChat.opens == opens + 1,
    "A hidden Ace page missed a configuration/profile refresh")
unified.Open("ls_toasts")
local toastPage = unified.pages.ls_toasts
chatMock.toasts.combat = true
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_DISABLED then frame.scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED") end
end
assert(not toastPage.container.frame:IsShown() and toastPage.message:IsShown(), "Combat left toast settings editable")
chatMock.toasts.combat = false
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_ENABLED then frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED") end
end
assert(toastPage.container.frame:IsShown() and not toastPage.message:IsShown())
WoWTools.modules.fight_detector.Show()
assert(WoWTools.modules.fight_detector.IsEnabled())
unified.Open("fight_detector")
unified.panel:Show()
unified.Select("inner_graphic_config")
unified.panel:Hide()
assert(WoWTools.modules.fight_detector.IsEnabled() and names.wowToolsFightDetectorPanel:IsShown()
    and not names.wowToolsFightDetectorPanel:IsVisible(), "Host/tab changes stopped combat detection or hid its protocol source")
WoWTools.modules.fight_detector.Hide()
unified.window:Hide()
assert(not unified.canvas.scripts.OnUpdate and not WoWTools.modules.wowDetector.IsEnabled(),
    "Closed settings retained UI polling or started a detector")
assert(cvarWrites == 0 and wowDetectorDB.luaGC.pause == 400, "Browsing settings applied an unsaved setting")
-- Speaker clicks keep a compact independent view and a separate embedded settings view.
local speaker = names.wowToolsSoundMinimapButton
speaker.scripts.OnClick(speaker, "LeftButton")
local compactAudio = names.wowToolsSoundControlPanel
assert(compactAudio:IsShown() and compactAudio:GetParent() == UIParent and not unified.window:IsShown(),
    "Speaker left click opened the unified settings instead of the independent audio panel")
speaker.scripts.OnClick(speaker, "RightButton")
assert(unified.IsGroupShown("sound_control") and compactAudio:IsShown()
    and unified.pages.sound_control.frame ~= compactAudio, "Speaker right click reused the compact audio frame")
speaker.scripts.OnClick(speaker, "LeftButton")
assert(not compactAudio:IsShown() and unified.IsGroupShown("sound_control"), "Closing compact audio also closed unified settings")

local previousY
for _, group in ipairs(unified.groups) do
    local tab = unified.tabs[group.key]
    local point = tab.point
    assert(point[2] == 8 and (not previousY or point[3] < previousY), "Primary tabs are not stacked vertically")
    assert(tab:GetHeight() == 37 and (not previousY or previousY - point[3] > tab:GetHeight()),
        "Two-line primary tabs must retain the native height and avoid overlapping")
    previousY = point[3]
end
local function ResizePage(key, width, height)
    local page = unified.pages[key]
    page:SetSize(width, height)
    if key == "wowDetector" then
        page.frame:SetSize(width, height - 160)
        names.WoWToolsSellFishScroll:SetSize(width - 56, height - 326)
    elseif key == "pet_tamer" then
        names.wowToolsPetTamerNames:GetParent():SetSize(width - 56, height - 176)
    end
    if page.content.scripts.OnSizeChanged then page.content.scripts.OnSizeChanged(page.content, width, height) end
    if page.frame and page.frame.scripts.OnSizeChanged then page.frame.scripts.OnSizeChanged(page.frame, width, height) end
end
local fontsHost = WoWTools.displayFonts.controls[1].row:GetParent()
local buttonHost = WoWTools.buttonStyle.editors[1].preview:GetParent()
local luaHost = luaView.inputs.pause:GetParent()
local originalGcCalls = gcCalls
local tamingInput = names.wowToolsPetTamerNames
assert(tamingInput.GetStringHeight == nil, "Forever EditBox mock exposed a FontString-only method")
tamingInput.spacing = 3
tamingInput:SetText(string.rep("pet\n", 39) .. "pet")
assert(tamingInput:GetHeight() == 617, "Embedded taming text missed line height, spacing or padding")
for _, size in ipairs({{880,620},{540,460}}) do
    local width, height = unpack(size)
    for _, key in ipairs({"wowDetector","fight_detector","pet_tamer","sound_control","inner_graphic_config"}) do
        ResizePage(key, width, height)
    end
    for _, host in ipairs({fontsHost, buttonHost, luaHost}) do host.scripts.OnSizeChanged(host) end
    assert(unified.pages.fight_detector.frame:GetWidth() == width
        and unified.pages.pet_tamer.frame:GetWidth() == width, "A native settings page retained its fixed frame width")
    assert(names.wowToolsPetTamerNames:GetWidth() == width - 60, "Taming input did not fill its resized viewport")
    assert(tamingInput:GetHeight() == 617, "Resizing truncated a long taming list")
    tamingInput.mockLineCount = 50
    ResizePage("pet_tamer", width, height)
    assert(tamingInput:GetHeight() == 767, "Taming layout missed wrapped EditBox lines")
    tamingInput.mockLineCount = nil
    assert(names.wowToolsSoundSettingsPanel.rows[1].slider:GetWidth() == width - 270
        and compactAudio:GetWidth() == 344, "Audio resize changed the compact frame or missed the embedded slider")
    assert(luaView.inputs.pause.point[2] == math.floor((width - 50) * 0.36)
        and luaView.inputs.pause:GetText() == "666", "Lua column layout lost a draft or retained a fixed width")
    assert(WoWTools.buttonStyle.editors[1].material:GetWidth() == width - 150, "Button settings did not span the graphics page")
    assert(luaTab.point[3] == -70, "Secondary graphics tabs lost their horizontal row")
    local columns = width - 50 >= 640 and 2 or 1
    assert(WoWTools.displayFonts.settingsHeight == 154 + math.ceil(4 / columns) * 122, "Font settings did not adapt their column count")
end
tamingInput:SetText("")
assert(tamingInput:GetHeight() == 284, "Clearing the taming list did not restore the viewport height")
assert(wowDetectorDB.petTamer == nil or #wowDetectorDB.petTamer.names == 0, "Editing or resizing saved the taming draft")
assert(gcCalls == originalGcCalls and cvarWrites == 0, "Resizing settings wrote live game parameters")
-- Blizzard hides an ancestor of an addon category when closing SettingsPanel.
local nativeSettingsHost = CreateFrame("Frame", nil, UIParent)
unified.panel:SetParent(nativeSettingsHost)
unified.panel:Show()
nativeSettingsHost:Hide()
assert(unified.panel:IsShown() and not unified.panel:IsVisible(), "Fixture did not retain the hidden category's shown flag")
names.wowToolsMinimapButton.scripts.OnClick(names.wowToolsMinimapButton, "RightButton")
assert(unified.window:IsVisible() and unified.canvas:IsVisible(),
    "Main minimap right click attached settings to a hidden native settings ancestor")
nativeSettingsHost:Show()
assert(unified.canvas:GetParent() == unified.panel and unified.canvas:IsVisible() and not unified.window:IsShown(),
    "Reopening native settings did not reclaim the shared canvas")
nativeSettingsHost:Hide()
assert(not unified.IsGroupShown("sound_control"), "A hidden native category was reported as an open settings group")
speaker.scripts.OnClick(speaker, "RightButton")
assert(unified.window:IsVisible() and unified.IsGroupShown("sound_control"),
    "Speaker right click attached settings to a hidden native settings ancestor")
print("PASS: "..flavor.." full TOC, seven unified settings tabs, one direct native category, minimap/IGC/chat/toast shortcuts, shared canvas/drafts, embedded Ace refresh/combat, sound teardown, detector isolation, fishing/loot/death protocols and FPS placement. All client APIs mocked.")
return chatMock
