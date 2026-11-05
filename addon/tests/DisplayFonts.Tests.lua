-- Native font edits only: no game APIs or input are performed.
local root=TEST_ROOT or "."
local widgets, frames={}, {}
local function Widget()
    local w={shown=true,path="Fonts\\native.ttf",size=12,flags="",writes=0,scripts={},events={}}
    function w:GetFont() return self.path,self.size,self.flags end
    function w:SetFont(path,size,flags)
        if path=="missing.ttf" then return false end
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
function CreateFrame() local w=Widget();frames[#frames+1]=w;return w end
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
local experience,bag,ammo=Widget(),Widget(),Widget()
local unrelated=Widget()
StatusTrackingBarManager={bars={{isExpBar=true,StatusBar={Text=experience}},{StatusBar={Text=unrelated}}}}
MainMenuBarBackpackButton={FreeSlots=bag};CharacterAmmoSlot=nil;CharacterAmmoSlotCount=nil
local source=root.."/addon/forerver/wow_tools/DisplayFonts.lua"
dofile(source)
local module=WoWTools.displayFonts
local startupFrame=frames[#frames]
local parent=Widget();module.BuildSettings(parent)
assert(#module.controls==3 and module.controls[1].size:GetText()=="24", "Settings page did not restore saved values")
assert(experience.writes==0 and bag.writes==0, "Fonts changed before native startup layout")
Event("ADDON_LOADED","another_addon")
assert(experience.writes==0 and bag.writes==0)
Event("PLAYER_ENTERING_WORLD")
assert(experience.size==24 and experience.flags=="OUTLINE" and experience.writes==1)
assert(bag.size==20 and bag.path=="Fonts\\custom.ttf" and bag.writes==1)
assert(unrelated.writes==0 and wowDetectorDB.unrelated==42)
assert(not startupFrame.events.PLAYER_ENTERING_WORLD and not startupFrame.events.PLAYER_REGEN_ENABLED)
-- Zoning, combat and other addon loads must not apply an existing font again.
Event("PLAYER_ENTERING_WORLD");Event("PLAYER_REGEN_ENABLED");Event("ADDON_LOADED","unrelated")
assert(experience.writes==1 and bag.writes==1)
experience:SetFont("Fonts\\other.ttf",9,"")
Event("ADDON_LOADED","another_addon")
assert(experience.size==9 and experience.writes==2, "A native font update was persistently overridden")
-- Only the missing ammo control is set once when its native addon finally loads.
CharacterAmmoSlot={Count=ammo};CharacterAmmoSlotCount=ammo
Event("ADDON_LOADED","Blizzard_UIPanels_Game")
assert(ammo.size==18 and ammo.writes==1, "Delayed ammo font was missed or its aliases were applied twice")
assert(experience.writes==2 and bag.writes==1)
assert(not next(startupFrame.events), "Initialization events remained active after all fonts were applied")
-- A deliberate UI save applies its target immediately and persists independently.
module.controls[1].size:SetText("16");module.controls[1].apply.scripts.OnClick()
assert(experience.size==16 and bag.writes==1 and ammo.writes==1)
assert(wowDetectorDB.displayFonts.experience.size==16)
for _,case in ipairs({{"experience","",7,""},{"experience","",49,""},{"experience","",12.5,""},{"other","",12,""},{"bags","missing.ttf",12,""},{"bags","",12,"BOGUS"}}) do
    assert(not module.Save(unpack(case)))
end
assert(experience.size==16 and bag.size==20)
module.controls[1].reset.scripts.OnClick()
assert(experience.size==12 and experience.path=="Fonts\\native.ttf" and experience.flags=="")
assert(wowDetectorDB.displayFonts.experience==nil and bag.writes==1)
-- Recreate the addon with persisted account settings and new native startup fonts.
WoWTools={};bag=Widget();ammo=Widget()
MainMenuBarBackpackButton={FreeSlots=bag};CharacterAmmoSlot={Count=ammo};CharacterAmmoSlotCount=ammo
experience=Widget();StatusTrackingBarManager.bars[1].StatusBar.Text=experience
dofile(source)
local reloadedFrame=frames[#frames]
Event("PLAYER_ENTERING_WORLD")
assert(bag.size==20 and ammo.size==18 and bag.writes==1 and ammo.writes==1 and experience.writes==0)
assert(not next(reloadedFrame.events) and not reloadedFrame.scripts.OnUpdate)
Event("PLAYER_ENTERING_WORLD");Event("ADDON_LOADED","other");Event("PLAYER_REGEN_ENABLED")
assert(bag.writes==1 and ammo.writes==1, "Saved font reapplied more than once in a load")
print("PASS: persistent account fonts, single startup apply, one-time delayed ammo, targeted manual saves, validation/reset and no hooks/timers/repeated event applies.")
