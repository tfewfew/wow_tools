-- Execute with Lua 5.1 from the repository root; all WoW APIs and UI objects are mocked.
local root = TEST_ROOT or "."
local frames, names = {}, {}
local scale, dead, pole, hasEnchant, expiration = 0.7, false, true, false, nil
local function widget(name)
    local object = { scripts = {}, events = {}, textures = {}, shown = true }
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:RegisterEvent(event) self.events[event] = true end
    function object:CreateTexture()
        local texture = widget()
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function object:CreateFontString() return widget() end
    function object:GetEffectiveScale() return scale end
    function object:SetColorTexture(...) self.color = { ... } end
    function object:SetPoint(...) self.point = { ... } end
    function object:GetPoint() return "LEFT", nil, "CENTER", -20, 0 end
    function object:Hide() self.shown = false end
    function object:Show() self.shown = true end
    function object:IsShown() return self.shown end
    setmetatable(object, { __index = function() return function() end end })
    if name then names[name] = object end
    return object
end
function CreateFrame(_, name)
    local object = widget(name)
    frames[#frames + 1] = object
    return object
end
UIParent = widget()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
function UnitIsDeadOrGhost() return dead end
function GetInventoryItemLink() return pole and "fishing-pole" or "sword" end
function GetItemInfoInstant() return 1, nil, nil, nil, nil, 2, pole and 20 or 7 end
function GetWeaponEnchantInfo() return hasEnchant, expiration, 0, 266 end
function UnitChannelInfo() return nil end
function UnitCastingInfo() return nil end
function GetContainerNumSlots(bag) return bag == 0 and 16 or 0 end
function GetContainerNumFreeSlots() return 10, 0 end
NUM_BAG_SLOTS = 4
dofile(root .. "/addon/wow_tools/Init.lua")
dofile(root .. "/addon/wow_tools/wowDetector/wowDetector.lua")
local panel = names.wowDetectorPanel
panel.scripts.OnEvent(panel, "ADDON_LOADED", "wow_tools")
local point = panel.textures[3]
local function assertColor(r, g, b)
    assert(point.color[1] == r and point.color[2] == g and point.color[3] == b, "Wrong lure detection color")
end
assertColor(0.5, 0.5, 0.5)
SlashCmdList.WOWDETECTOR("on")
assertColor(1, 0, 1)
assert(math.abs(point.point[4] * scale - 32) < 0.001, "Detection point is not 32 physical pixels away")
hasEnchant, expiration = true, 600000
panel.scripts.OnEvent(panel, "UNIT_INVENTORY_CHANGED", "player")
assertColor(0, 0, 1)
expiration = 1
assert(WoWTools.modules.wowDetector.GetLureState() == "present", "Positive remaining duration should remain active")
expiration = 0
assert(WoWTools.modules.wowDetector.GetLureState() == "missing", "Expired enchant is still active")
expiration = nil
assert(WoWTools.modules.wowDetector.GetLureState() == "unknown", "Unknown duration was treated as missing")
hasEnchant, expiration, pole = true, 600000, false
panel.scripts.OnEvent(panel, "PLAYER_EQUIPMENT_CHANGED", 16)
assertColor(0.5, 0.5, 0.5)
pole, scale = true, 1.25
panel.scripts.OnEvent(panel, "UI_SCALE_CHANGED")
assert(math.abs(point.point[4] * scale - 32) < 0.001, "UI scale moved physical detection offset")
dead = true
panel.scripts.OnEvent(panel, "PLAYER_DEAD")
assertColor(0.5, 0.5, 0.5)
assert(not wowDetectorDB.locked and panel.shown, "Death hid panel or kept position locked")
dead = false
SlashCmdList.WOWDETECTOR("on")
SlashCmdList.WOWDETECTOR("off")
assertColor(0.5, 0.5, 0.5)
print("PASS: fishing-pole temporary enchant, missing/active/expired/unknown, non-pole exclusion, death/off reset and physical pixel offset across UI scales. All WoW APIs mocked.")
