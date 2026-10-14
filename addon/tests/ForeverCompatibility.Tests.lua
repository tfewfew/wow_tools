-- Full addon smoke test with Forever's namespaced APIs, modern menu and FPS frame.
local root = TEST_ROOT or "."
local addon = root .. "/addon/forerver/wow_tools/"
local frames, names, widgets = {}, {}, {}
local scale, width, height, dead, free = 0.7, 1920, 1080, false, 10
local pole, enchants, channelName, channelID, castName, castID = true, {}, nil, nil, nil, nil
local apiFailure, cvarWrites, menuEntries = false, 0, {}
local targetGUID, targetName, interactable, interactCVar = nil, "模拟鱼漂", false, "3"
local guidFailure, interactFailure = false, false
local messages = {}
function InCombatLockdown() return false end
function ClearOverrideBindings() end
function SetOverrideBindingClick() end
local secret = setmetatable({}, {
    __eq = function() error("Compared a restricted value") end,
    __tostring = function() error("Printed a restricted value") end,
})
function issecretvalue(value) return rawequal(value, secret) end
local function widget(name)
    local object = { scripts = {}, events = {}, textures = {}, shown = true, text = "", enabled = true }
    function object:SetAttribute() end
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:RegisterEvent(event) self.events[event] = true end
    function object:UnregisterEvent(event) self.events[event] = nil end
    function object:CreateTexture()
        local texture = widget()
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function object:CreateFontString() return widget() end
    function object:GetEffectiveScale() return scale end
    function object:SetSize(w, h) self.width, self.height = w, h end
    function object:GetWidth() return self.width or 140 end
    function object:GetHeight() return self.height or 140 end
    function object:SetColorTexture(...) self.color = { ... } end
    function object:SetPoint(...) self.point = { ... } end
    function object:GetPoint() return "LEFT", nil, "CENTER", -20, 0 end
    function object:SetText(value) self.text = value end
    function object:GetText() return self.text end
    function object:GetFont() return "mock-font", 12, "" end
    function object:GetStringHeight() return 36 end
    function object:SetEnabled(value) self.enabled = value end
    function object:Enable() self.enabled = true end
    function object:Disable() self.enabled = false end
    function object:GetChecked() return self.checked end
    function object:SetChecked(value) self.checked = value end
    function object:Hide() self.shown = false end
    function object:Show() self.shown = true end
    function object:IsShown() return self.shown end
    function object:GetFrameLevel() return 1 end
    local harmless = {
        "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetMovable", "EnableMouse",
        "RegisterForDrag", "RegisterForClicks", "SetHighlightTexture", "SetTexture", "SetAllPoints",
        "ClearAllPoints", "SetFont", "SetWidth", "SetHeight", "SetJustifyH", "SetAutoFocus",
        "SetMaxLetters", "SetNumeric", "ClearFocus", "SetScrollChild", "StartMoving", "StopMovingOrSizing",
    }
    for _, method in ipairs(harmless) do object[method] = function() end end
    widgets[#widgets + 1] = object
    if name then names[name] = object end
    return object
end
function CreateFrame(_, name, _, template)
    assert(template ~= "UIDropDownMenuTemplate", "Forever still depends on legacy dropdown templates")
    local object = widget(name)
    if template == "MinimalTabTemplate" then object.Text = widget() end
    if template == "BasicFrameTemplateWithInset" then object.TitleText = widget() end
    frames[#frames + 1] = object
    return object
end
function CreateRadioButtonGroup()
    return { AddButton = function() end, SelectAtIndex = function() end }
end
UIParent, Minimap, FramerateFrame, GameTooltip = widget(), widget(), widget(), widget()
function GameTooltip:SetOwner() end
function GameTooltip:AddLine() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList, UISpecialFrames = {}, {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
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
        assert(slot == Enum.WeaponSlot.MainHand, "Wrong weapon-slot enumeration")
        if apiFailure then error("Unavailable enchant scan") end
        return enchants
    end,
}
C_Spell = { GetSpellName = function() return "Fishing" end }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function() return free, 0 end,
}
function UnitIsDeadOrGhost() return dead end
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
for line in io.lines(addon .. "wow_tools.toc") do
    if line:match("%.lua%s*$") then dofile(addon .. line:gsub("\\", "/"):gsub("%s+$", "")) end
end
for _, frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "wow_tools") end
end
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
assert(compat.GetFishingState() == false, "Cast counted as a ready fishing channel")
panel.scripts.OnEvent(panel, "UNIT_SPELLCAST_START", "player")
assertColor(indicator, 1, 0, 0)
castName, castID = "Other cast", 123
assert(compat.GetFishingState() == false, "Non-fishing cast accepted")
castName, castID, channelName, channelID = nil, nil, "Fishing", 7731
assert(compat.GetFishingState() == true, "Localized name fallback rejected another fishing rank")
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
assert(compat.GetFishingState() == nil, "Restricted cast did not stay unknown")
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
dead = true
panel.scripts.OnEvent(panel, "PLAYER_DEAD")
assertColor(indicator, 0.5, 0.5, 0.5)
assert(not wowDetectorDB.locked and panel.shown, "Death changed visibility/kept lock")
dead = false
panel.scripts.OnEvent(panel, "PLAYER_ALIVE")
assertColor(indicator, 0.5, 0.5, 0.5)
SlashCmdList.WOWTOOLS()
assert(#menuEntries == 3 and menuEntries[2].title == "fight_detector", "Modern module menu is missing")
menuEntries[3].onSelect()
assert(names.InnerGraphicConfigWindow.shown and not wowDetectorDB.locked, "Menu toggled wrong module")
menuEntries[1].onSelect()
assert(not panel.shown, "Monitor close did not hide")
menuEntries[1].onSelect()
assert(panel.shown and wowDetectorDB.locked, "Monitor open did not start/lock")
assert(WoWTools.modules.wowDetector.IsEnabled(),"Forever active fishing not exposed to loot")
SlashCmdList.WOWDETECTOR("off")
assert(not WoWTools.modules.wowDetector.IsEnabled(),"Forever visible disabled panel enables loot")
SlashCmdList.WOWDETECTOR("on")
SlashCmdList.WOWDETECTOR("hide")
assert(WoWTools.modules.wowDetector.IsEnabled(),"Forever hidden active fishing disables loot")
dead=true; panel.scripts.OnEvent(panel,"PLAYER_DEAD")
assert(not WoWTools.modules.wowDetector.IsEnabled(),"Forever death leaves loot enabled")
local fpsApplied = false
for _, control in ipairs(widgets) do
    if control.definition and control.definition.action then
        control.inputX:SetText("0"); control.inputY:SetText("180")
        control.apply.scripts.OnClick()
        fpsApplied = true
        break
    end
end
assert(fpsApplied and FramerateFrame.point[1] == "BOTTOM" and FramerateFrame.point[5] == 180,
    "Mainline FPS frame could not be repositioned")
assert(cvarWrites == 0, "Read-only actions changed graphics CVars")
print("PASS: Forever full addon load; fishing channel plus interactable soft target, cast/other channel rejection, event/polling arrival and loss, restricted event/target diagnostics, missing/failed APIs and bag/off/death priority; temporary enchants, resize, native menu and Mainline FPS frame. All client APIs mocked.")
