-- Native font edits only: no game APIs or input are performed.
local root=TEST_ROOT or "."
local widgets, frames, hooks={}, {}, {}
local function Widget()
    local w={shown=true,path="Fonts\\native.ttf",size=12,flags="",scripts={},events={}}
    function w:GetFont() return self.path,self.size,self.flags end
    function w:SetFont(path,size,flags)
        if path=="missing.ttf" then return false end
        self.path,self.size,self.flags=path,size,flags
        if hooks[self] then hooks[self]() end
        return true
    end
    function w:SetScript(key,fn) self.scripts[key]=fn end
    function w:RegisterEvent(key) self.events[key]=true end
    function w:CreateFontString() local x=Widget();widgets[#widgets+1]=x;return x end
    function w:SetText(text) self.text=text end
    function w:GetText() return self.text end
    function w:IsShown() return self.shown end
    for _,key in ipairs({"SetPoint","SetSize","SetWidth","SetJustifyH","SetAutoFocus","SetNumeric","SetMaxLetters","SetHeight","ClearFocus"}) do w[key]=function() end end
    return w
end
function CreateFrame() local w=Widget();frames[#frames+1]=w;return w end
function hooksecurefunc(region,method,fn) assert(method=="SetFont");hooks[region]=fn end
WoWTools={};wowDetectorDB={unrelated=42};STANDARD_TEXT_FONT="Fonts\\native.ttf"
local experience,bag,ammo=Widget(),Widget(),Widget()
local unrelated=Widget()
StatusTrackingBarManager={bars={{isExpBar=true,StatusBar={Text=experience}},{StatusBar={Text=unrelated}}}}
MainMenuBarBackpackButton={FreeSlots=bag};CharacterAmmoSlot=nil
dofile(root.."/addon/forerver/wow_tools/DisplayFonts.lua")
local module=WoWTools.displayFonts
local parent=Widget();module.BuildSettings(parent);module.Refresh()
assert(#module.controls==3 and module.controls[1].size:GetText()=="12")
assert(experience.size==12 and bag.size==12 and unrelated.size==12)
module.controls[1].size:SetText("16");module.controls[1].apply.scripts.OnClick()
assert(experience.size==16 and bag.size==12, "Experience page control applied the wrong font")
module.controls[1].reset.scripts.OnClick();assert(experience.size==12)
local ok=module.Save("experience","",24,"OUTLINE");assert(ok and experience.size==24 and experience.flags=="OUTLINE")
assert(bag.size==12 and unrelated.size==12 and wowDetectorDB.unrelated==42)
experience:SetFont("Fonts\\other.ttf",9,"");assert(experience.size==24 and experience.path=="Fonts\\native.ttf", "Native refresh overwrote chosen font")
ok=module.Save("bags","Fonts\\custom.ttf",20,"THICKOUTLINE");assert(ok and bag.size==20 and bag.path=="Fonts\\custom.ttf")
ok=module.Save("ammo","",18,"");assert(ok)
CharacterAmmoSlot={Count=ammo};module.Refresh();assert(ammo.size==18, "Late ammo frame did not apply saved font")
for _,case in ipairs({{"experience","",7,""},{"experience","",49,""},{"experience","",12.5,""},{"other","",12,""},{"bags","missing.ttf",12,""},{"bags","",12,"BOGUS"}}) do
    assert(not module.Save(unpack(case)))
end
assert(experience.size==24 and bag.size==20)
module.Reset("experience");assert(experience.size==12 and experience.flags=="" and experience.path=="Fonts\\native.ttf")
assert(wowDetectorDB.displayFonts.experience==nil and bag.size==20)
-- Recreate addon state, keeping SavedVariables and the native regions.
WoWTools={};dofile(root.."/addon/forerver/wow_tools/DisplayFonts.lua");WoWTools.displayFonts.Refresh()
assert(bag.size==20 and ammo.size==18 and unrelated.size==12)
assert(not frames[#frames].scripts.OnUpdate, "Font settings must not create a polling loop")
print("PASS: Forever font settings, isolated native regions, validation/rollback, reset, native font hooks, late ammo load and persistence.")
