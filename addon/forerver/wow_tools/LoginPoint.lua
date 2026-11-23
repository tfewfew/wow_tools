-- One in-world marker carries the active mode, independent of detector panels.
local point=CreateFrame("Frame","wowToolsLoginPoint",UIParent)
WoWTools.loginPoint=point
point:SetFrameStrata("TOOLTIP")
point:SetFrameLevel(10000)
point:EnableMouse(false)
if point.SetIgnoreParentAlpha then point:SetIgnoreParentAlpha(true) end
local fill=point:CreateTexture(nil,"OVERLAY")
fill:SetAllPoints()
point:Hide()
local inWorld,elapsed,modeElapsed=false,0,0
local dead=false
local displayedMode
local detectorModes={"wowDetector","fight_detector","auto_shop"}
-- This palette is also decoded by wowAuto.Rotation.Native.cs.
local colors={
    rest={255,255,255},
    wowDetector={64,170,255},
    fight_detector={255,112,76},
    auto_shop={181,104,255},
    dead={220,48,69},
}
local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function RefreshDeath()
    local ok,value=pcall(UnitIsDeadOrGhost,"player")
    if ok and Readable(value) and type(value)=="boolean" then dead=value end
end
local function PaintMode()
    local mode=dead and "dead" or "rest"
    if not dead then
        for _,name in ipairs(detectorModes) do
            local detector=WoWTools.modules[name]
            if detector and detector.IsEnabled() then mode=name;break end
        end
    end
    if mode~=displayedMode then
        local color=colors[mode]
        fill:SetColorTexture(color[1]/255,color[2]/255,color[3]/255,1)
        displayedMode=mode
    end
end
PaintMode()

SLASH_WOWTOOLSREST1="/wowrest"
SlashCmdList.WOWTOOLSREST=function()
    WoWTools.ActivateDetector("rest")
    PaintMode()
end
local function Position()
    if not inWorld or type(GetPhysicalScreenSize)~="function" then point:Hide(); return end
    local ok,width,height=pcall(GetPhysicalScreenSize)
    local scale=point:GetEffectiveScale()
    if not ok or not Readable(width) or not Readable(height) or not Readable(scale)
        or type(width)~="number" or type(height)~="number" or type(scale)~="number"
        or width<48 or height<48 or scale<=0 then point:Hide(); return end
    -- WoW's 768 reference height and effective UI scale convert to physical client pixels.
    local unit=768/height/scale
    point:ClearAllPoints()
    -- Windows rounds the visible client corners. Keep the full point inside them.
    point:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",-16*unit,16*unit)
    point:SetSize(16*unit,16*unit)
    point:Show()
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT",
    "PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED"}) do
    pcall(events.RegisterEvent,events,event)
end
local function Poll(_,delta)
    elapsed=elapsed+delta
    modeElapsed=modeElapsed+delta
    if modeElapsed>=0.1 then
        modeElapsed=0
        RefreshDeath()
        PaintMode()
    end
    if elapsed>=1 then elapsed=0; Position() end
end
events:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_ENTERING_WORLD" then
        inWorld,elapsed,modeElapsed=true,0,0
        RefreshDeath()
        PaintMode()
        events:SetScript("OnUpdate",Poll)
    elseif event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then
        inWorld,dead,elapsed=false,false,0
        events:SetScript("OnUpdate",nil)
    elseif event=="PLAYER_DEAD" or event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST" then
        if event=="PLAYER_DEAD" then dead=true
        elseif event=="PLAYER_UNGHOST" then dead=false
        else RefreshDeath() end
        PaintMode()
        return
    end
    Position()
end)
