-- Native font edits only: no game APIs or input are performed.
local flavor = TEST_FLAVOR or "forerver"
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
    function w:SetChecked(value) self.checked=value end
    function w:GetChecked() return self.checked end
    function w:GetWidth() return self.width or 420 end
    function w:SetPoint(...) self.point={...} end
    function w:ClearAllPoints() self.point=nil end
    function w:SetWidth(width) self.width=width end
    function w:SetHeight(height) self.height=height end
    function w:SetSize(width,height) self.width,self.height=width,height end
    function w:IsShown() return self.shown end
    for _,key in ipairs({"SetJustifyH","SetAutoFocus","SetNumeric","SetMaxLetters","ClearFocus"}) do w[key]=function() end end
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
    clock={size=20,flags="OUTLINE"},
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
MainMenuBarBackpackButtonCount=flavor=="titan" and bag or unrelated
if flavor=="titan" then MainMenuBarBackpackButton.FreeSlots=unrelated end
MainMenuExpBarText=unrelated
for i=0,3 do _G["CharacterBag"..i.."Slot"]=nil;_G["CharacterBag"..i.."SlotCount"]=nil end
TimeManagerClockTicker=nil
local source=root.."/addon/"..flavor.."/wow_tools/DisplayFonts.lua"
dofile(root.."/addon/"..flavor.."/wow_tools/ExperienceText.lua")
dofile(source)
local module=WoWTools.displayFonts
local startupFrame=frames[#frames]
local parent=Widget();module.BuildSettings(parent)
assert(#module.controls==4 and module.controls[1].size:GetText()=="24" and module.controls[4].key=="clock" and module.controls[4].size:GetText()=="20", "Settings page did not restore saved values or expose the clock")
assert(module.settingsHeight>=56+3*122+118, "Scrollable settings height clips the fourth font row")
local inputs=0
for _,frame in ipairs(frames) do if frame.kind=="EditBox" then inputs=inputs+1 end end
assert(inputs==4, "Each font setting must have only one size input")
for _,control in ipairs(module.controls) do assert(control.path==nil and control.sizeLabel.text:find("字号",1,true)) end
assert(experience.writes==0 and bag.writes==0, "Fonts changed before native startup layout")
local rested=module.controls[1].rested
assert(rested and not rested:GetChecked() and module.controls[2].rested==nil,
    "Rested XP checkbox must default off and belong only to the experience row")
assert(rested.point[1]=="LEFT" and rested.point[2]==module.controls[1].size,
    "Rested XP checkbox did not follow the experience size input")
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
if flavor=="titan" then
    for i=0,3 do
        _G["CharacterBag"..i.."SlotCount"]=bagCounts[i+1]
        _G["CharacterBag"..i.."Slot"].Count=unrelated
    end
end
Event("ADDON_LOADED","Blizzard_UIPanels_Game")
assert(ammo.size==18 and ammo.writes==1, "Delayed bag-slot counter font was missed")
for _,count in ipairs(bagCounts) do assert(count.size==18 and count.writes==1) end
assert(unrelated.writes==0, "An obsolete XP/ammo widget was styled instead of the verified targets")
assert(experience.writes==2 and bag.writes==1)
assert(startupFrame.events.ADDON_LOADED, "Missing clock was not retained for one-time late loading")
local clock=Widget();clock.path="Fonts\\clock.ttf";clock.size=11;clock.flags="OUTLINE"
TimeManagerClockTicker=clock
Event("ADDON_LOADED","Blizzard_TimeManager")
assert(clock.size==20 and clock.path=="Fonts\\clock.ttf" and clock.flags=="OUTLINE" and clock.writes==1, "Clock did not apply saved size once while preserving the native font")
assert(experience.writes==2 and bag.writes==1 and ammo.writes==1, "Late clock loading reapplied another font")
Event("PLAYER_ENTERING_WORLD");Event("ADDON_LOADED","unrelated")
assert(clock.writes==1)
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
module.controls[4].size:SetText("22");module.controls[4].apply.scripts.OnClick()
assert(clock.size==22 and wowDetectorDB.displayFonts.clock.size==22 and bag.writes==1 and ammo.writes==1)
module.controls[4].reset.scripts.OnClick()
assert(clock.size==11 and clock.flags=="OUTLINE" and clock.path=="Fonts\\clock.ttf" and wowDetectorDB.displayFonts.clock==nil)
assert(module.Save("clock",20,"OUTLINE"))
local fontWrites=experience.writes
rested:SetChecked(true)
rested.scripts.OnClick(rested)
assert(wowDetectorDB.displayFonts.showRestedXP==true and experience.writes==fontWrites,
    "Rested XP toggle failed to save immediately or reapplied a font")
assert(module.Save("experience",19,""))
module.Reset("experience")
assert(wowDetectorDB.displayFonts.showRestedXP==true,
    "A font save/reset erased the independent rested XP setting")
-- Recreate the addon with persisted account settings and new native startup fonts.
local fontDraft=module.controls[1]
fontDraft.size:SetText("27")
fontDraft.size.scripts.OnTextChanged(fontDraft.size,true)
local previousWrites=experience.writes
parent:SetWidth(800)
parent.scripts.OnSizeChanged()
assert(module.settingsHeight==398 and module.controls[2].row.point[2]>module.controls[1].row.point[2],
    "Wide font settings did not form two columns")
parent:SetWidth(480)
parent.scripts.OnSizeChanged()
fontDraft.row.scripts.OnShow()
assert(module.settingsHeight==642 and fontDraft.size:GetText()=="27" and experience.writes==previousWrites
    and wowDetectorDB.displayFonts.experience==nil, "Font resizing or re-showing lost or applied an unsaved draft")
rested:SetChecked(false)
rested.scripts.OnClick(rested)
assert(fontDraft.dirty and fontDraft.size:GetText()=="27" and not WoWTools.experienceText.IsEnabled(),
    "Rested XP toggle lost an unsaved font draft")
WoWTools={};bag=Widget();ammo=Widget();bagCounts={ammo,Widget(),Widget(),Widget()}
MainMenuBarBackpackButton={FreeSlots=bag}
MainMenuBarBackpackButtonCount=flavor=="titan" and bag or unrelated
if flavor=="titan" then MainMenuBarBackpackButton.FreeSlots=unrelated end
for i=0,3 do _G["CharacterBag"..i.."Slot"]={Count=bagCounts[i+1]} end
if flavor=="titan" then
    for i=0,3 do
        _G["CharacterBag"..i.."SlotCount"]=bagCounts[i+1]
        _G["CharacterBag"..i.."Slot"].Count=unrelated
    end
end
experience=Widget();experienceSecond=Widget()
StatusTrackingBarManager.barContainers={
    {bars={[4]={OverlayFrame={Text=experience}}}},
    {bars={[4]={OverlayFrame={Text=experienceSecond}}}},
}
clock=Widget();clock.path="Fonts\\clock.ttf";clock.size=11;clock.flags="OUTLINE";TimeManagerClockTicker=clock
dofile(root.."/addon/"..flavor.."/wow_tools/ExperienceText.lua")
dofile(source)
local reloadedFrame=frames[#frames]
local reloadedParent=Widget();WoWTools.displayFonts.BuildSettings(reloadedParent)
assert(not WoWTools.displayFonts.controls[1].rested:GetChecked(), "Disabled rested XP checkbox did not survive reload")
Event("PLAYER_ENTERING_WORLD")
assert(bag.size==20 and ammo.size==18 and bag.writes==1 and ammo.writes==1 and experience.writes==0)
assert(clock.size==20 and clock.writes==1 and clock.path=="Fonts\\clock.ttf" and clock.flags=="OUTLINE", "Clock size was not restored after addon reload")
assert(not next(reloadedFrame.events) and not reloadedFrame.scripts.OnUpdate)
Event("PLAYER_ENTERING_WORLD");Event("ADDON_LOADED","other");Event("PLAYER_REGEN_ENABLED")
assert(bag.writes==1 and ammo.writes==1, "Saved font reapplied more than once in a load")
assert(clock.writes==1, "Clock font was reapplied after initialization")
bag.rejectFont=true
local saved,message=WoWTools.displayFonts.Save("bags",22,"")
assert(saved and message:find("应用失败",1,true) and bag.size==20, "Failed native font apply was reported as success")
print("PASS: "..flavor.." persistent account fonts, single startup apply, clock persistence/late loading/reset, client-specific backpack/XP/four bag counters, size-only UI/legacy font-path migration, targeted manual saves, validation/reset and no hooks/timers/repeated font applies.")
