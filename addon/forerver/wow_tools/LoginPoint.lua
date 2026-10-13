-- Always present in the game world, independent of detector panels and settings.
local point=CreateFrame("Frame","wowToolsLoginPoint",UIParent)
WoWTools.loginPoint=point
point:SetFrameStrata("TOOLTIP")
point:SetFrameLevel(10000)
point:EnableMouse(false)
if point.SetIgnoreParentAlpha then point:SetIgnoreParentAlpha(true) end
local white=point:CreateTexture(nil,"OVERLAY")
white:SetAllPoints()
white:SetColorTexture(1,1,1,1)
point:Hide()
local inWorld,elapsed=false,0
local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function Position()
    if not inWorld or type(GetPhysicalScreenSize)~="function" then point:Hide(); return end
    local ok,width,height=pcall(GetPhysicalScreenSize)
    local scale=point:GetEffectiveScale()
    if not ok or not Readable(width) or not Readable(height) or not Readable(scale)
        or type(width)~="number" or type(height)~="number" or type(scale)~="number"
        or width<16 or height<16 or scale<=0 then point:Hide(); return end
    -- WoW's 768 reference height and effective UI scale convert to physical client pixels.
    local unit=768/height/scale
    point:ClearAllPoints()
    point:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",0,0)
    point:SetSize(16*unit,16*unit)
    point:Show()
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT",
    "DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_ENTERING_WORLD" then inWorld=true
    elseif event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then inWorld=false end
    Position()
end)
events:SetScript("OnUpdate",function(_,delta)
    if not inWorld then return end
    elapsed=elapsed+delta
    if elapsed>=.1 then elapsed=0; Position() end
end)
