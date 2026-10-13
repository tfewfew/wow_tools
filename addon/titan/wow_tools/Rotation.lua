-- Character-menu navigation belongs to the desktop script. This marker only confirms world entry.
local frame = CreateFrame("Frame", nil, UIParent)
frame:SetFrameStrata("TOOLTIP")
frame:SetPoint("CENTER", WoWTools.detectorAnchor, "CENTER", 0, 0)
local texture = frame:CreateTexture(nil, "OVERLAY")
texture:SetAllPoints(frame)
frame:Hide()
local inWorld, active, elapsed = false, false, 0
local function SafeValue(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end
local function SafeBoolean(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 or value == nil then return false end
    return nil
end
local function Update()
    if not active or not inWorld then frame:Hide(); return end
    local guid = SafeValue(UnitGUID, "player")
    local dead = SafeBoolean(UnitIsDeadOrGhost, "player")
    local combat = SafeBoolean(UnitAffectingCombat, "player")
    local height
    if GetPhysicalScreenSize then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        height = ok and h or nil
    end
    local uiHeight = UIParent:GetHeight()
    if issecretvalue and (issecretvalue(height) or issecretvalue(uiHeight)) then frame:Hide(); return end
    if not guid or dead ~= false or type(combat) ~= "boolean" or type(height) ~= "number" or height <= 0 or type(uiHeight) ~= "number" or uiHeight <= 0 then frame:Hide(); return end
    frame:SetSize(32 * uiHeight / height, 32 * uiHeight / height)
    local token = tonumber(wowRotationDB and wowRotationDB.Token) or 0
    if token < 0 or token > 200 or token ~= math.floor(token) then token = 0 end
    texture:SetColorTexture((20 + token) / 255, 231 / 255, (combat and 181 or 157) / 255, 1)
    frame:Show()
end
WoWTools.Rotation = {}
function WoWTools.Rotation.Hide()
    active = false
    frame:Hide()
    if wowRotationDB then wowRotationDB.Token = nil end
end
SLASH_WOWROTATE1 = "/wowrotate"
SlashCmdList.WOWROTATE = function(message)
    local token = tonumber(message:match("^arm%s+(%d+)$"))
    if message == "clear" then WoWTools.Rotation.Hide(); return end
    if not token or token < 1 or token > 200 or token ~= math.floor(token) then return end
    wowRotationDB = wowRotationDB or {}
    wowRotationDB.Token = token
    for _, name in ipairs({"wowDetector", "fight_detector"}) do
        local module = WoWTools.modules[name]
        if module then module.Hide() end
    end
    active = true
    Update()
end
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:SetScript("OnEvent", function(_, event)
    inWorld = event == "PLAYER_ENTERING_WORLD"
    if inWorld then active = true end
    Update()
end)
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    Update()
end)
