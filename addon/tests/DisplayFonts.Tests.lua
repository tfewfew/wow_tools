-- Native font edits only: no game APIs or input are performed.
local root=TEST_ROOT or "."
local widgets, frames={}, {}
local function Widget()
    local w={shown=true,path="Fonts\\native.ttf",size=12,flags="",writes=0,scripts={},events={}}
    function w:GetFont() return self.path,self.size,self.flags end
    function w:SetFont(path,size,flags)
        if path=="missing.ttf" or self.rejectFont then return false end
        self.path,self.size,self.flags=path,size,flags
        self.writes=self.writes+1
        return true
    end
    function w:SetScript(key,fn) self.scripts[key]=fn end
    function w:RegisterEvent(key) self.events[key]=true end
    function w:UnregisterEvent(key) self.events[key]=nil end
    function w:CreateFontString() local x=Widget();widgets[#widgets+1]=x;return x end
    function w:SetText(text) self.text=text end
    function w:GetText() return self.text end
    function w:IsShown() return self.shown end
    for _,key in ipairs({"SetPoint","SetSize","SetWidth","SetJustifyH","SetAutoFocus","SetNumeric","SetMaxLetters","SetHeight","ClearFocus"}) do w[key]=function() end end
    return w
end
function CreateFrame(kind) local w=Widget();w.kind=kind;frames[#frames+1]=w;return w end
function hooksecurefunc() error("Font settings must not install persistent hooks") end
C_Timer={After=function() error("Font settings must not schedule repeat/timer applies") end}
local function Event(event,name)
    for _,frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame,event,name) end
    end
end
WoWTools={};wowDetectorDB={unrelated=42,displayFonts={
    experience={path="",size=24,flags="OUTLINE"},
    bags={path="Fonts\\custom.ttf",size=20,flags="THICKOUTLINE"},
    ammo={path="",size=18,flags=""},
}};STANDARD_TEXT_FONT="Fonts\\native.ttf"
local experience,experienceSecond,bag,ammo=Widget(),Widget(),Widget(),Widget()
local bagCounts={ammo,Widget(),Widget(),Widget()}
local unrelated=Widget()
StatusTrackingBarInfo={BarsEnum={Experience=4}}
StatusTrackingBarManager={
    barContainers={
        primary={bars={[4]={OverlayFrame={Text=experience}}}},
        secondary={bars={[4]={OverlayFrame={Text=experienceSecond}}}},
        alias={bars={[4]={OverlayFrame={Text=experience}}}},
    },
    bars={{isExpBar=true,StatusBar={Text=unrelated}}},
}
MainMenuBarBackpackButton={FreeSlots=bag};CharacterAmmoSlot={Count=unrelated};CharacterAmmoSlotCount=unrelated
MainMenuExpBarText=unrelated
for i=0,3 do _G["CharacterBag"..i.."Slot"]=nil end
local source=root.."/addon/forerver/wow_tools/DisplayFonts.lua"
dofile(source)
local module=WoWTools.displayFonts
local startupFrame=frames[#frames]
local parent=Widget();module.BuildSettings(parent)
assert(#module.controls==3 and module.controls[1].size:GetText()=="24", "Settings page did not restore saved values")
local inputs=0
for _,frame in ipairs(frames) do if frame.kind=="EditBox" then inputs=inputs+1 end end
assert(inputs==3, "Each font setting must have only one size input")
for _,control in ipairs(module.controls) do assert(control.path==nil and control.sizeLabel.text:find("字号",1,true)) end
assert(experience.writes==0 and bag.writes==0, "Fonts changed before native startup layout")
Event("ADDON_LOADED","another_addon")
assert(experience.writes==0 and bag.writes==0)
Event("PLAYER_ENTERING_WORLD")
assert(experience.size==24 and experience.flags=="OUTLINE" and experience.writes==1)
assert(bag.size==20 and bag.path=="Fonts\\native.ttf" and bag.writes==1, "Legacy font paths must be ignored")
assert(experienceSecond.size==24 and experienceSecond.writes==1)
assert(unrelated.writes==0 and wowDetectorDB.unrelated==42)
assert(not startupFrame.events.PLAYER_ENTERING_WORLD and not startupFrame.events.PLAYER_REGEN_ENABLED)
-- Zoning, combat and other addon loads must not apply an existing font again.
Event("PLAYER_ENTERING_WORLD");Event("PLAYER_REGEN_ENABLED");Event("ADDON_LOADED","unrelated")
assert(experience.writes==1 and bag.writes==1)
experience:SetFont("Fonts\\other.ttf",9,"")
Event("ADDON_LOADED","another_addon")
assert(experience.size==9 and experience.writes==2, "A native font update was persistently overridden")
-- Only the missing ammo control is set once when its native addon finally loads.
for i=0,3 do _G["CharacterBag"..i.."Slot"]={Count=bagCounts[i+1]} end
Event("ADDON_LOADED","Blizzard_UIPanels_Game")
assert(ammo.size==18 and ammo.writes==1, "Delayed bag-slot counter font was missed")
for _,count in ipairs(bagCounts) do assert(count.size==18 and count.writes==1) end
assert(unrelated.writes==0, "An obsolete XP/ammo widget was styled instead of the verified targets")
assert(experience.writes==2 and bag.writes==1)
assert(not next(startupFrame.events), "Initialization events remained active after all fonts were applied")
-- A deliberate UI save applies its target immediately and persists independently.
module.controls[1].size:SetText("16");module.controls[1].apply.scripts.OnClick()
assert(experience.size==16 and experienceSecond.size==16 and bag.writes==1 and ammo.writes==1)
assert(experience.path=="Fonts\\other.ttf", "Size changes must preserve each target's current native font")
assert(wowDetectorDB.displayFonts.experience.size==16 and wowDetectorDB.displayFonts.experience.path==nil)
for _,case in ipairs({{"experience",7,""},{"experience",49,""},{"experience",12.5,""},{"other",12,""},{"bags",12,"BOGUS"},{"bags","invalid",""}}) do
    assert(not module.Save(unpack(case)))
end
assert(experience.size==16 and bag.size==20)
module.controls[1].reset.scripts.OnClick()
assert(experience.size==12 and experience.path=="Fonts\\native.ttf" and experience.flags=="")
assert(wowDetectorDB.displayFonts.experience==nil and bag.writes==1)
-- Recreate the addon with persisted account settings and new native startup fonts.
WoWTools={};bag=Widget();ammo=Widget();bagCounts={ammo,Widget(),Widget(),Widget()}
MainMenuBarBackpackButton={FreeSlots=bag}
for i=0,3 do _G["CharacterBag"..i.."Slot"]={Count=bagCounts[i+1]} end
experience=Widget();experienceSecond=Widget()
StatusTrackingBarManager.barContainers={
    {bars={[4]={OverlayFrame={Text=experience}}}},
    {bars={[4]={OverlayFrame={Text=experienceSecond}}}},
}
dofile(source)
local reloadedFrame=frames[#frames]
Event("PLAYER_ENTERING_WORLD")
assert(bag.size==20 and ammo.size==18 and bag.writes==1 and ammo.writes==1 and experience.writes==0)
assert(not next(reloadedFrame.events) and not reloadedFrame.scripts.OnUpdate)
Event("PLAYER_ENTERING_WORLD");Event("ADDON_LOADED","other");Event("PLAYER_REGEN_ENABLED")
assert(bag.writes==1 and ammo.writes==1, "Saved font reapplied more than once in a load")
bag.rejectFont=true
local saved,message=WoWTools.displayFonts.Save("bags",22,"")
assert(saved and message:find("应用失败",1,true) and bag.size==20, "Failed native font apply was reported as success")
print("PASS: persistent account fonts, single startup apply, verified XP overlays and four bag counters, size-only UI/legacy font-path migration, targeted manual saves, validation/reset and no hooks/timers/repeated event applies.")
