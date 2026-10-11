-- Execute with Lua 5.1 from the repository root; all WoW APIs and UI objects are mocked.
local root = TEST_ROOT or "."
local frames, names = {}, {}
local scale, dead, pole, hasEnchant, expiration = 0.7, false, true, false, nil
local physicalWidth, physicalHeight = 1920, 1080
local channelName, channelID, casting = nil, nil, false
local targetGUID, interactable, guidError, interactError = nil, false, false, false
local bagFree, bagDataMissing = 10, false
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
    function object:SetSize(width, height) self.size = { width, height } end
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
local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}
function UnitIsDeadOrGhost() return dead end
function GetPhysicalScreenSize() return physicalWidth, physicalHeight end
function GetInventoryItemLink() return pole and "fishing-pole" or "sword" end
function GetItemInfoInstant() return 1, nil, nil, nil, nil, 2, pole and 20 or 7 end
function GetWeaponEnchantInfo() return hasEnchant, expiration, 0, 266 end
function UnitChannelInfo() return channelName, nil, nil, nil, nil, nil, nil, channelID end
function UnitCastingInfo() return casting and "钓鱼" or nil, nil, nil, nil, nil, nil, nil, nil, 7620 end
function UnitGUID(unit)
    assert(unit == "softinteract", "Wrong interaction unit token")
    if guidError then error("mock unreadable GUID") end
    return targetGUID
end
function UnitIsInteractable(unit)
    assert(unit == "softinteract", "Wrong interactability unit token")
    if interactError then error("mock unreadable interaction") end
    return interactable
end
function UnitExists() error("GameObjects must not be rejected by UnitExists") end
function UnitName(unit) assert(unit == "softinteract"); return targetGUID and "模拟鱼漂" or nil end
function GetContainerNumSlots(bag) return bag == 0 and 16 or 0 end
function GetContainerNumFreeSlots() if bagDataMissing then return nil end; return bagFree, 0 end
NUM_BAG_SLOTS = 4
dofile(root .. "/addon/titan/wow_tools/Init.lua")
dofile(root .. "/addon/titan/wow_tools/wowDetector/Audio.lua")
dofile(root .. "/addon/titan/wow_tools/wowDetector/wowDetector.lua")
local panel = names.wowDetectorPanel
panel.scripts.OnEvent(panel, "ADDON_LOADED", "wow_tools")
local point = panel.textures[3]
local function assertColor(r, g, b)
    assert(point.color[1] == r and point.color[2] == g and point.color[3] == b, "Wrong lure detection color")
end
assertColor(0.5, 0.5, 0.5)
SlashCmdList.WOWDETECTOR("on")
assertColor(1, 0, 1)
local function assertMain(r, g, b)
    local color = panel.textures[2].color
    assert(color[1] == r and color[2] == g and color[3] == b, "Wrong fishing/interaction color")
end
local function event(name, unit) panel.scripts.OnEvent(panel, name, unit or "player") end
local function tick()
    for _, frame in ipairs(frames) do
        if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.1) end
    end
end
assert(panel.events.PLAYER_SOFT_INTERACT_CHANGED, "Missing soft interaction event")
assertMain(1, 0, 0)
-- A target alone, or the cast before the channel begins, must not turn green.
targetGUID, interactable = "GameObject-0-1-2-3-4-5", true
event("PLAYER_SOFT_INTERACT_CHANGED", "old-target-guid")
assertMain(1, 0, 0)
casting = true
event("UNIT_SPELLCAST_START")
assertMain(1, 0, 0)
casting, channelName, channelID = false, "other channel", 123
event("UNIT_SPELLCAST_CHANNEL_START")
assertMain(1, 0, 0)
channelName, channelID, targetGUID = "钓鱼", 7620, nil
event("UNIT_SPELLCAST_CHANNEL_START")
assertMain(1, 0, 0)
targetGUID = "GameObject-0-1-2-3-4-5"
event("PLAYER_SOFT_INTERACT_CHANGED", "old-target-guid")
assertMain(0, 1, 0)
-- GameObject GUIDs work without UnitExists; status makes the selected target reviewable.
SlashCmdList.WOWDETECTOR("status")
local diagnostic = messages[#messages - 1]
assert(diagnostic:find("交互目标=present", 1, true) and diagnostic:find(targetGUID, 1, true)
    and diagnostic:find("模拟鱼漂", 1, true), "Missing interaction diagnostics")
targetGUID = nil
event("PLAYER_SOFT_INTERACT_CHANGED", "old-target-guid")
assertMain(1, 0, 0)
-- Polling covers lost/delayed events, both arrival and disappearance.
targetGUID = "GameObject-0-1-2-3-4-6"
tick()
assertMain(0, 1, 0)
interactable = false
tick()
assertMain(1, 0, 0)
interactable = true
tick()
assertMain(0, 1, 0)
channelName, channelID = nil, nil
event("UNIT_SPELLCAST_CHANNEL_STOP")
assertMain(1, 0, 0)
-- Localized-name fallback still recognizes other fishing ranks.
channelName, channelID = "钓鱼", 7731
function GetSpellInfo() return "钓鱼" end
event("UNIT_SPELLCAST_CHANNEL_START")
assertMain(0, 1, 0)
GetSpellInfo = nil
channelID = 7620
local guidApi, interactApi = UnitGUID, UnitIsInteractable
UnitGUID = nil
tick()
assertMain(0.5, 0.5, 0.5)
UnitGUID, UnitIsInteractable = guidApi, nil
tick()
assertMain(0.5, 0.5, 0.5)
UnitIsInteractable, guidError = interactApi, true
tick()
assertMain(0.5, 0.5, 0.5)
guidError, interactError = false, true
tick()
assertMain(0.5, 0.5, 0.5)
interactError, interactable = false, nil
tick()
assertMain(0.5, 0.5, 0.5)
interactable, targetGUID = true, 42
tick()
assertMain(0.5, 0.5, 0.5)
targetGUID = "secret-guid"
function issecretvalue(value) return value == "secret-guid" or value == "secret-interaction" end
tick()
assertMain(0.5, 0.5, 0.5)
targetGUID, interactable = "GameObject-0-1-2-3-4-6", "secret-interaction"
tick()
assertMain(0.5, 0.5, 0.5)
issecretvalue, interactable = nil, true
tick()
assertMain(0, 1, 0)
bagFree, targetGUID = 0, nil
tick()
assertMain(1, 1, 0)
UnitGUID = nil
tick()
assertMain(1, 1, 0)
UnitGUID, bagFree, bagDataMissing = guidApi, 10, true
tick()
assertMain(0.5, 0.5, 0.5)
bagDataMissing = false
targetGUID = "GameObject-0-1-2-3-4-6"
tick()
assertMain(0, 1, 0)
SlashCmdList.WOWDETECTOR("off")
assertMain(0.5, 0.5, 0.5)
tick()
assertMain(0.5, 0.5, 0.5)
-- Restart re-reads the target; no previous fishing success survives.
targetGUID = nil
SlashCmdList.WOWDETECTOR("on")
assertMain(1, 0, 0)
channelName, channelID, targetGUID, interactable = nil, nil, nil, false
local function assertPhysicalOffset()
    -- WoW region units also scale with the viewport height, not only UI scale.
    local pixelsPerUnit = scale * physicalHeight / 768
    assert(math.abs(point.point[4] * pixelsPerUnit - 32) < 0.001,
        "Detection point is not 32 physical pixels away at " .. physicalWidth .. "x" .. physicalHeight)
    assert(math.abs(point.size[1] * pixelsPerUnit - 12) < 0.001
        and math.abs(point.size[2] * pixelsPerUnit - 12) < 0.001,
        "Lure marker physical size changed after resize/scale")
    assert(panel.textures[2].point[1] == "TOPLEFT" and panel.textures[2].point[2] == 8
        and panel.textures[2].point[3] == -8 and panel.point[4] == -20,
        "Lure positioning moved the original center detection marker")
end
assertPhysicalOffset()
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
assertPhysicalOffset()
for _, viewport in ipairs({ {800, 450}, {1280, 720}, {1365, 768}, {1920, 1080}, {2560, 1440}, {3840, 2160}, {1024, 1024} }) do
    physicalWidth, physicalHeight = viewport[1], viewport[2]
    for _, uiScale in ipairs({0.64, 0.7, 1, 1.25}) do
        scale = uiScale
        panel.scripts.OnEvent(panel, "DISPLAY_SIZE_CHANGED")
        assertPhysicalOffset()
        assertColor(0, 0, 1)
    end
end
-- The periodic refresh must also track a resize when no display event is delivered.
physicalWidth, physicalHeight, scale = 1600, 900, 0.8
for _, frame in ipairs(frames) do
    if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.1) end
end
assertPhysicalOffset()
SlashCmdList.WOWDETECTOR("status")
assert(messages[#messages]:find("1600x900", 1, true)
    and messages[#messages]:find("32px", 1, true), "Status lacks pixel positioning diagnostics")
-- Invalid/missing viewport data must not leave a misleading active color at an old position.
physicalHeight = 0
panel.scripts.OnEvent(panel, "DISPLAY_SIZE_CHANGED")
assertColor(0.5, 0.5, 0.5)
assert(not point.shown, "Invalid viewport left the lure marker visible")
local physicalSizeApi = GetPhysicalScreenSize
GetPhysicalScreenSize = nil
panel.scripts.OnEvent(panel, "UI_SCALE_CHANGED")
assertColor(0.5, 0.5, 0.5)
GetPhysicalScreenSize = physicalSizeApi
physicalHeight = 900
panel.scripts.OnEvent(panel, "DISPLAY_SIZE_CHANGED")
assert(point.shown, "Valid viewport did not restore the lure marker")
assertColor(0, 0, 1)
assertPhysicalOffset()
dead = true
panel.scripts.OnEvent(panel, "PLAYER_DEAD")
assertColor(0.5, 0.5, 0.5)
assertMain(0.5, 0.5, 0.5)
assert(not wowDetectorDB.locked and panel.shown, "Death hid panel or kept position locked")
dead = false
panel.scripts.OnEvent(panel, "PLAYER_ALIVE")
assertMain(0.5, 0.5, 0.5)
SlashCmdList.WOWDETECTOR("on")
SlashCmdList.WOWDETECTOR("off")
assertColor(0.5, 0.5, 0.5)
print("PASS: Titan fishing channel plus interactable soft target, cast/other channel rejection, event/polling arrival and loss, unreadable APIs, bag/death/off priority and diagnostics; temporary enchants, 32px offset and 12px marker across window sizes/UI scales. All WoW APIs mocked.")
