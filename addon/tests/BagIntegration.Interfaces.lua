-- Forever 1.60.1.70938, native container interfaces at bebcb6bf309cf41b41bd74f8ca651e6a105b2676.
local root = TEST_ROOT or "."
local hooks, pending, frames = {}, {}, {}
local cvar, loaded, anchorUpdates = "0", {}, 0
local windowPointWrites, nativeHides = 0, 0
local parentScale, resetOnHide = 0.8, false
local closeCallbacks = {}
local itemPointWrites, familyReads = 0, 0
local familiesReady = true
local combat = false
local backpackExtra, rejectReagent = 0, false
local slots = {[0] = 16, 4, 4, 4, 0, 4}
local families = {[0] = 0, 0, 0, 1, 0, 0}
WoWTools, wowDetectorDB = {}, {}
UIParent = {
    GetLeft = function() return 0 end,
    GetTop = function() return 900 end,
    GetEffectiveScale = function() return parentScale end,
}
EventRegistry = {
    RegisterCallback = function(_, event, callback, owner)
        assert(event == "ContainerFrame.CloseBag" and type(callback) == "function" and type(owner) == "table",
            "Native bag-close callbacks must preserve the event, callback and owner signature")
        closeCallbacks[#closeCallbacks + 1] = {callback = callback, owner = owner}
    end,
    TriggerEvent = function(_, event, frame)
        assert(event == "ContainerFrame.CloseBag" and type(frame) == "table")
        for _, entry in ipairs(closeCallbacks) do entry.callback(entry.owner, frame) end
    end,
}
Enum = {BagIndex = {ReagentBag = 5}, ItemClass = {Quiver = 11}}
C_AddOns = {IsAddOnLoaded = function(name) assert(type(name) == "string") return loaded[name] end}
InputUtil = {IsGamepadUIEnabled = function() return false end}
C_Container = {
    GetContainerNumSlots = function(bagID)
        assert(type(bagID) == "number" and slots[bagID], "Unexpected container ID")
        return slots[bagID]
    end,
    GetContainerNumFreeSlots = function(bagID)
        assert(type(bagID) == "number" and families[bagID], "Unexpected family query")
        familyReads = familyReads + 1
        if not familiesReady then return 0, nil end
        return 0, families[bagID]
    end,
    ContainerIDToInventoryID = function(bagID)
        assert(bagID >= 1 and bagID <= 4, "Bag slots must use the native inventory conversion")
        return bagID + 19
    end,
}
function GetInventoryItemLink(unit, inventoryID)
    assert(unit == "player" and inventoryID >= 20 and inventoryID <= 23, "Equipment link signature mismatch")
    return "bag:" .. inventoryID
end
C_Item = {GetItemInfoInstant = function(link)
    assert(type(link) == "string" and link:match("^bag:"), "Instant item query must use a link")
    return 1, "Container", "Bag", "INVTYPE_BAG", 1, 1, 0
end}
C_XMLUtil = {GetTemplateInfo = function(template)
    assert(template == "ContainerFrameItemButtonTemplate", "Native item pool template mismatch")
    return {width = 37, height = 37}
end}
C_Timer = {After = function(delay, callback)
    assert(delay == 0 and type(callback) == "function", "Layout timer signature mismatch")
    pending[#pending + 1] = callback
end}
bit = {band = function(value, mask)
    assert(mask == 3 and type(value) == "number", "Ammo bag-family mask mismatch")
    return value % 4
end}
function InCombatLockdown() return combat end
function GetCVar(name) assert(name == "combinedBags") return cvar end
function GetCVarBool(name) return GetCVar(name) == "1" end
function SetCVar(name, value)
    assert(name == "combinedBags" and (value == "0" or value == "1"), "Unexpected CVar write")
    cvar = value
end
local function Region(kind)
    local region = {kind = kind, shown = false, scripts = {}, events = {}}
    function region:SetPoint(point, relative, relativePoint, x, y)
        assert(type(point) == "string" and type(relative) == "table" and type(relativePoint) == "string"
            and type(x) == "number" and type(y) == "number", "Native anchor signature mismatch")
        if self.kind == "ItemButton" then itemPointWrites = itemPointWrites + 1 end
        if self == ContainerFrameCombinedBags then
            assert(relative == UIParent, "Saved bag position must use the root frame")
            windowPointWrites = windowPointWrites + 1
            self.anchor = {point, relative, relativePoint, x, y}
            if point == "TOPLEFT" and relativePoint == "TOPLEFT" then
                local ratio = relative:GetEffectiveScale() / self:GetEffectiveScale()
                self.left = relative:GetLeft() * ratio + x
                self.top = relative:GetTop() * ratio + y
            end
        end
    end
    function region:ClearAllPoints() end
    function region:SetText(value) assert(type(value) == "string") end
    function region:SetHeight(value) assert(type(value) == "number") end
    function region:SetColorTexture(r, g, b, a)
        assert(type(r) == "number" and type(g) == "number" and type(b) == "number" and a == 1)
    end
    function region:Show() self.shown = true end
    function region:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function region:IsShown() return self.shown end
    function region:SetScript(event, callback) self.scripts[event] = callback end
    function region:RegisterEvent(event) self.events[event] = true end
    function region:UnregisterEvent(event) self.events[event] = nil end
    return region
end
function CreateFrame(kind)
    assert(kind == "Frame", "Runtime integration must use the native item pool")
    local frame = Region(kind)
    frames[#frames + 1] = frame
    return frame
end
local container = Region("Frame")
ContainerFrameCombinedBags = container
container.left, container.top = 120, 700
function container:GetLeft() return self.left end
function container:GetTop() return self.top end
function container:GetEffectiveScale() return (self.scale or 1) * parentScale end
function container:GetPoint(index)
    assert(index == 1, "Native bag anchor reads must use the first anchor")
    if self.pointOverride then return unpack(self.pointOverride) end
    if self.left == nil or self.top == nil then return end
    local ratio = UIParent:GetEffectiveScale() / self:GetEffectiveScale()
    return "TOPLEFT", UIParent, "TOPLEFT", self.left - UIParent:GetLeft() * ratio, self.top - UIParent:GetTop() * ratio
end
function container:OnHide()
    EventRegistry:TriggerEvent("ContainerFrame.CloseBag", self)
    nativeHides = nativeHides + 1
    if resetOnHide then self.left, self.top = 10, 20 end
end
-- XML binds this script when the frame is created, before the addon changes instance methods.
container.scripts.OnHide = container.OnHide
local nativeOnHide = container.OnHide
container.itemButtonPool = {
    GetTemplate = function() return "ContainerFrameItemButtonTemplate" end,
    Release = function(_, button) button:Hide() end,
}
function container:CreateFontString(name, layer, font)
    assert(name == nil and layer == "ARTWORK" and font == "GameFontHighlightSmall")
    return Region("FontString")
end
function container:CreateTexture(name, layer)
    assert(name == nil and layer == "ARTWORK")
    return Region("Texture")
end
function container:ClearItems() self.Items = {} end
function container:AcquireNewItemButton()
    local button = Region("ItemButton")
    function button:Initialize(containerFrame, bagID, slotID)
        assert(containerFrame == container, "Native Initialize requires its container frame before bag and slot")
        assert(type(bagID) == "number" and type(slotID) == "number" and slotID >= 1
            and slotID <= slots[bagID] + (bagID == 0 and backpackExtra or 0), "Pooled item Initialize signature mismatch")
        if bagID == 5 and rejectReagent then error("Native Initialize rejected reagent slot") end
        self.containerFrame = containerFrame
        self.bagID, self.slotID = bagID, slotID
    end
    function button:GetBagID() return self.bagID end
    function button:GetID() return self.slotID end
    self.Items[#self.Items + 1] = button
    return button
end
function container:SetBagSize()
    self.size = backpackExtra
    for bagID = 0, 4 do self.size = self.size + slots[bagID] end
end
function container:UpdateItemSlots()
    self:ClearItems()
    for bagID = 4, 0, -1 do
        local bagSize = slots[bagID] + (bagID == 0 and backpackExtra or 0)
        for slotID = bagSize, 1, -1 do self:AcquireNewItemButton():Initialize(self, bagID, slotID) end
    end
end
function container:EnumerateValidItems()
    return function(self, index)
        index = index + 1
        if index <= self.size then return index, self.Items[index] end
    end, self, 0
end
function container:MatchesBagID(bagID) return bagID >= 0 and bagID <= 4 end
function container:IsBagOpen(bagID) if self.shown and self:MatchesBagID(bagID) then return bagID end end
function container:UpdateItemLayout() end
function container:UpdateFrameSize() end
function container:HookScript(event, callback) self.scripts[event] = callback end
function container:GetColumns() return 10 end
function container:GetPaddingWidth() return 15 end
function container:CalculateExtraHeight() return 28 end
function container:LayoutAddSlots() end
function container:SetSize(width, height) assert(width > 0 and height > 0) self.height = height end
function container:GetHeight() return self.height end
function container:SetScale(value) assert(value > 0) self.scale = value end
ContainerFrameSettingsManager = {
    IsUsingCombinedBags = function(_, bagID) return (not bagID or bagID <= 4) and cvar == "1" end,
    OnCombinedBagSettingChanged = function(_, combined) assert(type(combined) == "boolean") end,
}
function IsAnyBagOpen() return container.shown end
function CloseAllBags() container:Hide() end
function OpenBackpack() container:Show() end
function UpdateContainerFrameAnchors()
    anchorUpdates = anchorUpdates + 1
    container:SetScale(0.75)
end
NineSliceUtil = {UpdateCornerCropping = function(frame, height)
    assert(frame == container and height == container:GetHeight(), "NineSlice interface mismatch")
end}
function hooksecurefunc(target, method, callback)
    assert(target == container and type(target[method]) == "function" and type(callback) == "function")
    hooks[method] = callback
end
dofile(root .. "/addon/forerver/wow_tools/BagIntegration.lua")
local bags = WoWTools.bagIntegration
assert(bags.SetEnabled(true) and bags.active and wowDetectorDB.bagIntegration.enabled,
    "Enabled account setting must bind the native container integration")
assert(container.OnHide == nativeOnHide and container.scripts.OnHide == nativeOnHide and #closeCallbacks == 1,
    "Position capture must use the native close event while preserving the XML-bound OnHide script")
assert(container:MatchesBagID(5) and ContainerFrameSettingsManager:IsUsingCombinedBags(5),
    "Reagent container routing must participate in the same native window")
assert(not container:MatchesBagID(6), "Bank container routing changed")
container:SetBagSize()
container:UpdateItemSlots()
hooks.UpdateItemSlots(container)
assert(container.size == #container.Items and container.size == 32,
    "Native enumeration size must include every pooled reagent slot exactly once")
hooks.UpdateItemSlots(container)
assert(container.size == #container.Items, "Reagent buttons were acquired twice")
for _, button in container:EnumerateValidItems() do
    assert(button.containerFrame == container, "Every native item button must retain its owning container")
end
backpackExtra = 4
container:SetBagSize()
container:UpdateItemSlots()
hooks.UpdateItemSlots(container)
assert(container.size == #container.Items and container.size == 36,
    "Native account-extension slots must remain part of the enumeration")
slots[5] = 0
container:SetBagSize()
container:UpdateItemSlots()
hooks.UpdateItemSlots(container)
assert(container.size == #container.Items and container.size == 32,
    "An unequipped reagent bag must preserve the native slot-count contract")
slots[5] = 4
container:SetBagSize()
container:UpdateItemSlots()
hooks.UpdateItemSlots(container)
container.meihang, container.suofang = 8, 1.1
container:Show()
container.scripts.OnShow(container)
hooks.UpdateFrameSize(container)
hooks.UpdateItemLayout(container)
for _, callback in ipairs(pending) do callback() end
assert(container.scale == 1.1, "Grouped item layout must preserve !Pig's scale binding")
assert(anchorUpdates == 0, "Grouped item layout must preserve ownership of the bag window's anchors")
assert(windowPointWrites == 0, "A new account without a closed position must retain its native opening anchor")
pending = {}
local bagEvents
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_LOGIN then bagEvents = frame end
end
assert(bagEvents and type(bagEvents.scripts.OnEvent) == "function", "Missing native bag event handler")
assert(not bagEvents.events.BAG_UPDATE_DELAYED, "A complete native layout must release the content-update subscription")
local previousPoints, previousReads = itemPointWrites, familyReads
bagEvents.scripts.OnEvent(bagEvents, "BAG_UPDATE_DELAYED")
assert(#pending == 0 and itemPointWrites == previousPoints and familyReads == previousReads,
    "Ordinary item updates must retain the existing layout without extra timers or native geometry calls")
for _, callback in ipairs(pending) do callback() end
assert(anchorUpdates == 0, "Item-update callbacks must preserve the bag window's positioning interface")
container:Hide()
hooks.UpdateFrameSize(container)
hooks.UpdateItemLayout(container)
assert(#pending == 0, "Hidden native containers must defer layout work until shown")
container:Show()
familiesReady = false
hooks.UpdateItemLayout(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(bagEvents.events.BAG_UPDATE_DELAYED, "Unavailable bag families must subscribe for native-data recovery")
familiesReady = true
bagEvents.scripts.OnEvent(bagEvents, "BAG_UPDATE_DELAYED")
bagEvents.scripts.OnEvent(bagEvents, "BAG_UPDATE_DELAYED")
assert(#pending == 1, "Native-data retries must share one next-frame callback")
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(not bagEvents.events.BAG_UPDATE_DELAYED, "Native-data recovery must release the retry subscription")
previousPoints = itemPointWrites
hooks.UpdateFrameSize(container)
hooks.UpdateItemLayout(container)
assert(#pending == 1, "Native layout and size hooks must remain coalesced")
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(itemPointWrites > previousPoints, "Native layout regeneration must reapply the grouped geometry")
combat = true
previousPoints = itemPointWrites
hooks.UpdateFrameSize(container)
hooks.UpdateItemLayout(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(itemPointWrites > previousPoints and anchorUpdates == 0,
    "Combat native-layout callbacks must reapply grouped item geometry while retaining window anchors")
container:SetBagSize()
container:UpdateItemSlots()
hooks.UpdateItemSlots(container)
container:Show()
previousPoints = itemPointWrites
assert(type(container.scripts.OnShow) == "function", "Missing native container show hook")
container.scripts.OnShow(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(itemPointWrites > previousPoints and container.size == #container.Items,
    "Native buttons generated while in combat must bind to the same grouped presentation")
previousPoints = itemPointWrites
bagEvents.scripts.OnEvent(bagEvents, "BAG_UPDATE_DELAYED")
assert(#pending == 0 and itemPointWrites == previousPoints,
    "Ordinary combat item updates must retain the existing grouped presentation")
combat = false
local positionConfig = wowDetectorDB.bagIntegration
container.left, container.top = 240, 650
local ratio = container:GetEffectiveScale() / UIParent:GetEffectiveScale()
local expectedX = container:GetLeft() * ratio - UIParent:GetLeft()
local expectedY = container:GetTop() * ratio - UIParent:GetTop()
local previousHides = nativeHides
resetOnHide = true
container:Hide()
assert(nativeHides == previousHides + 1 and math.abs(positionConfig.position.x - expectedX) < 0.000001
    and math.abs(positionConfig.position.y - expectedY) < 0.000001 and container:GetLeft() == 10,
    "Closing must save the current root-relative position before the native OnHide reanchors it")
container.suofang, parentScale = 0.9, 0.7
container:Show()
local previousWindowPoints = windowPointWrites
container.scripts.OnShow(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
ratio = container:GetEffectiveScale() / UIParent:GetEffectiveScale()
assert(windowPointWrites == previousWindowPoints + 1
    and math.abs(container:GetLeft() * ratio - UIParent:GetLeft() - expectedX) < 0.000001
    and math.abs(container:GetTop() * ratio - UIParent:GetTop() - expectedY) < 0.000001,
    "Opening must restore the closed position once after applying native and !Pig scaling")
previousWindowPoints = windowPointWrites
hooks.UpdateFrameSize(container)
hooks.UpdateItemLayout(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(windowPointWrites == previousWindowPoints, "An existing open window must retain its current positioning interface")
container:Hide()
local closedPosition = positionConfig.position
container:Show()
container.scripts.OnShow(container)
container:Hide()
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(positionConfig.position == closedPosition and windowPointWrites == previousWindowPoints,
    "Closing before the native opening completes must retain the last completed close position")
positionConfig.position = {x = "invalid", y = 0}
container:Show()
container.scripts.OnShow(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(windowPointWrites == previousWindowPoints, "Invalid saved coordinates must retain the native opening anchor")
container:Hide()
positionConfig.position = closedPosition
combat = true
container:Show()
container.scripts.OnShow(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(windowPointWrites == previousWindowPoints + 1, "Combat opening must retain the closed-position restoration interface")
combat = false
closedPosition = positionConfig.position
container.left = nil
container:Hide()
assert(positionConfig.position == closedPosition, "An unavailable native rect must preserve the last valid saved position")
container.left, container.top = 240, 650
container:Show()
container.pointOverride = {"CENTER", UIParent, "BOTTOMRIGHT", -350, 250}
container.left, container.top = nil, nil
container:Hide()
ratio = container:GetEffectiveScale() / UIParent:GetEffectiveScale()
assert(positionConfig.position.point == "CENTER" and positionConfig.position.relativePoint == "BOTTOMRIGHT"
    and positionConfig.position.x == -350 * ratio and positionConfig.position.y == 250 * ratio,
    "Native close callbacks must capture root-relative anchors even when the hidden rect is unavailable")
closedPosition = positionConfig.position
EventRegistry:TriggerEvent("ContainerFrame.CloseBag", {})
assert(positionConfig.position == closedPosition, "Closing another bag must preserve the combined window's saved anchor")
container.suofang, parentScale = 1.2, 0.9
container:Show()
container.scripts.OnShow(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
ratio = UIParent:GetEffectiveScale() / container:GetEffectiveScale()
assert(container.anchor[1] == "CENTER" and container.anchor[3] == "BOTTOMRIGHT"
    and math.abs(container.anchor[4] - closedPosition.x * ratio) < 0.000001
    and math.abs(container.anchor[5] - closedPosition.y * ratio) < 0.000001,
    "Restoring a native anchor must retain both anchor names and convert offsets for the current scale")
container:Hide()
container.pointOverride = nil
positionConfig.position = {x = 150, y = -200}
container:Show()
container.scripts.OnShow(container)
for _, callback in ipairs(pending) do callback() end
pending = {}
assert(container.anchor[1] == "TOPLEFT" and container.anchor[3] == "TOPLEFT"
    and math.abs(container.anchor[4] - 150 * ratio) < 0.000001
    and math.abs(container.anchor[5] + 200 * ratio) < 0.000001,
    "Legacy coordinate-only records must retain their root-relative TOPLEFT anchor contract")
container.pointOverride = {"TOPLEFT", {}, "TOPLEFT", 1, 2}
container:Hide()
local fallbackX, fallbackY = positionConfig.position.x, positionConfig.position.y
assert(math.abs(fallbackX - 150) < 0.000001 and math.abs(fallbackY + 200) < 0.000001,
    "Anchors relative to another window must use the native rect to preserve root-relative coordinates")
container.pointOverride = nil
assert(bags.SetEnabled(false) and not bags.active and cvar == "0",
    "Disabling must restore the prior combinedBags interface setting")
assert(not container:MatchesBagID(5) and not ContainerFrameSettingsManager:IsUsingCombinedBags(5),
    "Inactive native routing must delegate to its original interfaces")
assert(bags.SetEnabled(true) and bags.active, "Native integration did not rebind")
assert(#closeCallbacks == 1, "Re-enabling integration must reuse its native close callback")
rejectReagent = true
container:SetBagSize()
container:UpdateItemSlots()
hooks.UpdateItemSlots(container)
assert(container.size == #container.Items and container.size == 32,
    "A rejected reagent initializer must leave the original native enumeration complete")
for _, button in container:EnumerateValidItems() do
    assert(button and button.containerFrame == container and button:GetBagID() ~= 5,
        "Native enumeration contains an uninitialized item after rejection")
end
for _, callback in ipairs(pending) do callback() end
assert(not bags.active and cvar == "0", "A rejected native interface must restore the prior UI setting")
rejectReagent = false
loaded.Baganator = true
assert(bags.SetEnabled(true) and not bags.active and cvar == "0", "A full bag replacement must retain native UI ownership")
print("PASS: forerver native bag pool, reagent routing, presentation signatures and addon ownership contracts.")
