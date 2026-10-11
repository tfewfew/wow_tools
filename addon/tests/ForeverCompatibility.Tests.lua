-- Full addon smoke test with Forever's namespaced APIs, modern menu and FPS frame.
local root = TEST_ROOT or "."
local addon = root .. "/addon/forerver/wow_tools/"
local frames, names, widgets = {}, {}, {}
local scale, width, height, dead, free = 0.7, 1920, 1080, false, 10
local pole, enchants, channelName, channelID, castName, castID = true, {}, nil, nil, nil, nil
local apiFailure, cvarWrites, menuEntries = false, 0, {}
local secret = setmetatable({}, {
    __eq = function() error("Compared a restricted value") end,
    __tostring = function() error("Printed a restricted value") end,
})
function issecretvalue(value) return rawequal(value, secret) end
local function widget(name)
    local object = { scripts = {}, events = {}, textures = {}, shown = true, text = "", enabled = true }
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:RegisterEvent(event) self.events[event] = true end
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
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList, UISpecialFrames = {}, {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
C_CVar = { GetCVar = function() return nil end, SetCVar = function() cvarWrites = cvarWrites + 1 end }
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
function GetPhysicalScreenSize() return width, height end
function UnitChannelInfo() return channelName, nil, nil, nil, nil, nil, nil, channelID end
function UnitCastingInfo() return castName, nil, nil, nil, nil, nil, "cast-guid", false, castID end
for _, file in ipairs({ "Init.lua", "Compatibility.lua", "wowDetector/Audio.lua", "wowDetector/wowDetector.lua", "inner_graphic_config/Core.lua", "Core.lua" }) do
    dofile(addon .. file)
end
for _, frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "wow_tools") end
end
local panel, compat = names.wowDetectorPanel, WoWTools.compat
local indicator, lure = panel.textures[2], panel.textures[3]
local function assertColor(texture, r, g, b)
    assert(texture.color[1] == r and texture.color[2] == g and texture.color[3] == b, "Unexpected detection color")
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
assertColor(indicator, 0, 1, 0)
channelName, channelID, castName, castID = nil, nil, "Localized fishing", 7620
assert(compat.GetFishingState() == true, "Casting spell ID not read from return 9")
castName, castID = "Other cast", 123
assert(compat.GetFishingState() == false, "Non-fishing cast accepted")
castName, castID, channelName, channelID = nil, nil, secret, secret
panel.scripts.OnEvent(panel, "UNIT_SPELLCAST_CHANNEL_START", "player")
assertColor(indicator, 0.5, 0.5, 0.5)
assert(compat.GetFishingState() == nil, "Restricted cast did not stay unknown")
SlashCmdList.WOWDETECTOR("status") -- must not print restricted values.
channelName, channelID, free = nil, nil, 0
panel.scripts.OnEvent(panel, "BAG_UPDATE_DELAYED")
assertColor(indicator, 1, 1, 0)
free = 10
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
SlashCmdList.WOWTOOLS()
assert(#menuEntries == 2, "Modern module menu is missing")
menuEntries[2].onSelect()
assert(names.InnerGraphicConfigWindow.shown and not wowDetectorDB.locked, "Menu toggled wrong module")
menuEntries[1].onSelect()
assert(not panel.shown, "Monitor close did not hide")
menuEntries[1].onSelect()
assert(panel.shown and wowDetectorDB.locked, "Monitor open did not start/lock")
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
print("PASS: Forever full addon load, namespaced temporary enchants, permanent/imbue exclusion, restricted/failed data, casting/channel IDs, bags/death, resize, native module menu and Mainline FPS frame. All client APIs mocked.")
