local root=TEST_ROOT or "."
local flavor = TEST_FLAVOR or "forerver"
local function Widget()
    local frame={scripts={},events={},shown=false,text="",width=224,height=48}
    function frame:SetScript(event,callback) self.scripts[event]=callback end
    function frame:RegisterEvent(event) self.events[event]=true end
    function frame:UnregisterEvent(event) self.events[event]=nil end
    function frame:SetText(text) self.text=text end
    function frame:GetText() return self.text end
    function frame:SetSize(width,height) self.width,self.height=width,height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetPoint(...) self.point={...} end
    function frame:GetPoint() return unpack(self.point or {"BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",0,0}) end
    function frame:Show() if self.shown then return end; self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function frame:Hide() if not self.shown then return end; self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function frame:IsShown() return self.shown end
    function frame:AddMessage() end
    function frame:CreateTexture() return Widget() end
    function frame:CreateFontString() return Widget() end
    function frame:GetAlpha() return 1 end
    for _,method in ipairs({"SetHeight","SetWidth","SetFrameStrata","SetAlpha","ClearAllPoints","SetClampedToScreen",
        "SetMovable","RegisterForDrag","RegisterForClicks","SetHighlightTexture","SetAllPoints","SetScale",
        "SetAutoFocus","SetMultiLine","SetFontObject","SetScrollChild","SetOwner","EnableMouse"}) do frame[method]=function() end end
    return frame
end
CreateFrame=function() return Widget() end
UIParent,GameTooltip,DEFAULT_CHAT_FRAME=Widget(),Widget(),Widget()
SlashCmdList,UISpecialFrames={},{}
Settings={RegisterAddOnCategory=function() end,RegisterCanvasLayoutCategory=function() return {} end}
WoWTools={modules={}}
local chat=dofile(root.."/addon/tests/BigFootChannel.Mock.lua")
local mock=dofile(root.."/addon/tests/LsToasts.Mock.lua")(chat)
wowDetectorDB={soundControl={minimapAngle=315},lsToasts={db={profiles={Default={skin="beautycase",font={size=15}}}}}}
mock.itemInfo[100]={name="测试物品",quality=3}
mock.bags[0]={}
mock.LoadXML(root.."/addon/"..flavor.."/wow_tools/ls_toasts/ls_toasts.xml")
assert(not WoWTools.modules.ls_toasts.IsShown())
mock.Fire("ADDON_LOADED","another_addon")
assert(not WoWTools.lsToasts.C.db,"Another addon initialized toast settings")
mock.Fire("ADDON_LOADED","wow_tools")
mock.loggedIn=true
mock.Fire("PLAYER_LOGIN")
local module=WoWTools.lsToasts
local E,P,C=module.E,module.P,module.C
assert(module.ready and C.db.profile.skin=="beautycase" and C.db.profile.font.size==15)
assert(C.db.raw==wowDetectorDB.lsToasts.db and wowDetectorDB.soundControl.minimapAngle==315)
assert(C.options.args.types.args.loot_items and C.options.args.types.args.loot_gold)
assert(C.options.args.anchors and C.options.args.profiles and C.options.args.general)
WoWTools.modules.ls_toasts.Toggle();assert(WoWTools.modules.ls_toasts.IsShown())
WoWTools.modules.ls_toasts.Toggle();assert(not WoWTools.modules.ls_toasts.IsShown())
SlashCmdList.LSTOASTS("");assert(WoWTools.modules.ls_toasts.IsShown())
mock.combat=true;mock.Fire("PLAYER_REGEN_DISABLED");assert(not WoWTools.modules.ls_toasts.IsShown())
WoWTools.modules.ls_toasts.Show();assert(not WoWTools.modules.ls_toasts.IsShown());mock.combat=false
C.options.args.general.args.font.args.size.set(nil,17)
assert(C.db.profile.font.size==17)
C.options.args.toggle_anchors.func();assert(P:GetAnchor(1):IsShown())
C.options.args.toggle_anchors.func();assert(not P:GetAnchor(1):IsShown())

-- Exercise the real toast factory, skin, queue and animation setup.
local toast=E:GetToast("TEST")
assert(toast.Border and toast.Icon and toast.AnimOut and toast._data)
toast:Spawn(1,false)
assert(#P:GetActiveToasts(1)==1)
assert(
    toast.FadeIn and toast.FadeIn:IsPlaying() and not toast.AnimOut:IsPlaying(),
    "Popup started its fade-out before fade-in completed"
)
assert(
    toast.FadeIn.Anim1.duration == 0.15 and toast.FadeIn.Anim1.smoothing == "OUT",
    "Popup has no eased fade-in"
)
assert(toast.AnimOut.Anim1.smoothing == "IN_OUT", "Fade-out has no easing")
assert(toast.AnimIn.Anim1.childKey == "Glow", "Decorative animation still controls root opacity")
toast.FadeIn.Anim1.smoothProgress = 0.4
toast:RestartFadeOut()
assert(
    toast.FadeIn.playCalls == 1 and toast.FadeIn.Anim1.smoothProgress == 0.4,
    "Receipt interrupted the active fade-in"
)
mock.FinishAnimation(toast.FadeIn)
assert(toast:GetAlpha() == 1 and toast.AnimOut:IsPlaying())
toast.AnimOut.Anim1.smoothProgress = 0.75
toast:RestartFadeOut()
assert(
    math.abs(toast:GetAlpha() - 0.25) < 0.0001 and toast.FadeIn:IsPlaying() and not toast.AnimOut:IsPlaying(),
    "Receipt during fade-out snapped instead of restoring current opacity"
)
toast.scripts.OnEnter(toast)
mock.FinishAnimation(toast.FadeIn)
assert(not toast.AnimOut:IsPlaying(), "Hovered toast resumed fading")
toast.scripts.OnLeave(toast)
assert(toast.AnimOut:IsPlaying())
toast.AnimOut.Anim1.smoothProgress = 0.5
toast.Slot1.scripts.OnEnter(toast.Slot1)
assert(toast._data.hovered and toast.FadeIn:IsPlaying())
toast.Slot1.scripts.OnLeave(toast.Slot1)
assert(not toast.AnimOut:IsPlaying(), "Slot leave interrupted fade-in")
mock.FinishAnimation(toast.FadeIn)
assert(toast.AnimOut:IsPlaying())
local second = E:GetToast("TEST")
second:Spawn(1, false)
local third = E:GetToast("TEST")
third:Spawn(1, false)
local firstWrites, secondWrites, thirdWrites = toast.pointWrites, second.pointWrites, third.pointWrites
local firstShows, secondShows, thirdShows = toast.showCalls, second.showCalls, third.showCalls
P:RefreshQueues()
P:RefreshQueues()
assert(
    toast.pointWrites == firstWrites
        and second.pointWrites == secondWrites
        and third.pointWrites == thirdWrites,
    "Unchanged queue rewrote toast positions"
)
assert(
    toast.showCalls == firstShows and second.showCalls == secondShows and third.showCalls == thirdShows,
    "Unchanged queue showed active toasts again"
)
second:Release()
assert(
    third.point[2] == toast and third.pointWrites > thirdWrites,
    "Queue removal did not reflow following toasts"
)
local anchorConfig = C.db.profile.anchors[1]
local direction, offset = anchorConfig.growth_direction, anchorConfig.growth_offset_x
anchorConfig.growth_direction, anchorConfig.growth_offset_x = "RIGHT", 13
P:RefreshQueues()
assert(
    third.point[1] == "LEFT"
        and third.point[2] == toast
        and third.point[3] == "RIGHT"
        and third.point[4] == 13,
    "Queue ignored changed growth settings"
)
third:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 1, 1)
P:RefreshQueues()
assert(third.point[2] == toast, "Queue did not correct an external reanchor")
anchorConfig.growth_direction, anchorConfig.growth_offset_x = direction, offset
P:FlushQueue()
assert(#P:GetActiveToasts(1) == 0)
assert(
    toast:GetAlpha() == 1 and not toast.FadeIn:IsPlaying() and not toast.AnimOut:IsPlaying(),
    "Released toast retained opacity animation"
)
local reused = E:GetToast("TEST")
reused:Spawn(1, false)
assert(
    reused:GetAlpha() == 0 and reused.FadeIn.Anim1.fromAlpha == 0 and reused.FadeIn:IsPlaying(),
    "Recycled toast did not restart from transparent"
)
mock.FinishAnimation(reused.FadeIn)
mock.FinishAnimation(reused.AnimOut)
assert(#P:GetActiveToasts(1) == 0, "Completed fade-out did not release its toast")

-- Exercise receipt merges through the actual item and gold systems.
mock.money = 10100
mock.Fire("PLAYER_MONEY")
local goldToast = E:FindToast(nil, "event", "PLAYER_MONEY")
assert(goldToast and goldToast.FadeIn:IsPlaying())
mock.FinishAnimation(goldToast.FadeIn)
goldToast.AnimOut.Anim1.smoothProgress = 0.6
mock.money = 10200
mock.Fire("PLAYER_MONEY")
assert(E:FindToast(nil, "event", "PLAYER_MONEY") == goldToast and goldToast._data.count == 200)
assert(
    math.abs(goldToast.FadeIn.Anim1.fromAlpha - 0.4) < 0.0001 and goldToast.FadeIn:IsPlaying(),
    "Gold merge snapped the fading toast"
)
mock.Fire("CHAT_MSG_LOOT", "你获得了物品：item:100。")
local itemToast = E:FindToast(nil, "item_id", 100)
assert(itemToast and itemToast.FadeIn:IsPlaying())
mock.FinishAnimation(itemToast.FadeIn)
itemToast.AnimOut.Anim1.smoothProgress = 0.8
mock.Fire("CHAT_MSG_LOOT", "你获得了物品：item:100。")
assert(E:FindToast(nil, "item_id", 100) == itemToast and itemToast._data.count == 2)
assert(
    math.abs(itemToast.FadeIn.Anim1.fromAlpha - 0.2) < 0.0001 and itemToast.FadeIn:IsPlaying(),
    "Item merge snapped the fading toast"
)
P:FlushQueue()
mock.money = 10000
mock.Fire("PLAYER_MONEY")

-- Use lightweight toast surfaces to inspect business event quantities.
local receipts={}
local function Surface()
    local surface={_data={},Icon=CreateFrame("Frame"),IconBorder={SetVertexColor=function() end,Show=function() end},
        Border={SetVertexColor=function() end},Title=CreateFrame("Frame"),Text=CreateFrame("Frame"),
        IconText1=CreateFrame("Frame"),IconHL=CreateFrame("Frame"),Dragon=CreateFrame("Frame")}
    surface.IconText1.SetAnimatedValue=function(self,value) self.value=value end
    surface.Text.SetAnimatedValue=function(self,value) self.value=value end
    surface.Spawn=function(self,anchor,dnd) receipts[#receipts+1]=self end
    surface.HookScript=function() end
    return surface
end
E.FindToast=function() return nil end
E.GetToast=function() return Surface(),true,false end
mock.money=10500;mock.Fire("PLAYER_MONEY")
assert(#receipts==1 and receipts[1]._data.count==500)
mock.money=10000;mock.Fire("PLAYER_MONEY");assert(#receipts==1)
C.db.profile.types.loot_gold.track_loss=true
mock.money=9900;mock.Fire("PLAYER_MONEY");assert(receipts[2]._data.count==-100)
local goldOptions=C.options.args.types.args.loot_gold
goldOptions.args.enabled.set(nil,false)
mock.money=11000;mock.Fire("PLAYER_MONEY");assert(#receipts==2)
goldOptions.args.enabled.set(nil,true)
mock.Advance(1.5)
mock.Fire("CHAT_MSG_LOOT","你获得了物品：item:100x2。")
assert(receipts[#receipts]._data.count==2)
local count=#receipts
mock.bags[0]={{itemID=100,stackCount=2}};mock.Fire("BAG_UPDATE",0);mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(.1)
assert(#receipts==count,"Chat and bag gain generated duplicate loot toasts")
mock.bags[0][1].stackCount=5;mock.Fire("BAG_UPDATE",0);mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(.1)
assert(#receipts==count+1 and receipts[#receipts]._data.count==3)
local itemOptions=C.options.args.types.args.loot_items
itemOptions.args.enabled.set(nil,false)
mock.bags[0][1].stackCount=8;mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(2)
assert(#receipts==count+1,"Disabled loot system still generated toasts")
itemOptions.args.enabled.set(nil,true);mock.Advance(1.5)
mock.bags[0][1].stackCount=9;mock.Fire("BAG_UPDATE_DELAYED")
itemOptions.args.enabled.set(nil,false);mock.Advance(.1)
assert(#receipts==count+1,"Canceled scan still generated loot")
local secret=setmetatable({}, {__tostring=function() error("Printed a restricted toast value") end})
issecretvalue=function(value) return rawequal(value,secret) end
local before=#receipts
mock.money=secret;mock.Fire("PLAYER_MONEY")
mock.money=12000;mock.Fire("PLAYER_MONEY")
assert(#receipts==before,"Unknown money produced a false change")
itemOptions.args.enabled.set(nil,true);mock.Advance(1.5)
mock.Fire("CHAT_MSG_LOOT",secret)
assert(#receipts==before)
mock.Fire("CHAT_MSG_LOOT","你获得了物品：item:100。",nil,nil,nil,"测试角色-测试服务器",nil,nil,nil,nil,nil,nil,"Player-test")
assert(#receipts==before+1,"Realm-qualified self loot rejected")
before=#receipts
mock.bags[0]={{itemID=secret,stackCount=9}};mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(.1)
mock.bags[0]={{itemID=100,stackCount=10}};mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(.1)
assert(#receipts==before,"Restricted bag scan generated a false gain")
mock.bags[0][1].stackCount=11;mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(.1)
assert(#receipts==before+1)
C.db.callbacks.OnProfileChanged()
assert(C.db.profile.font.size==17 and C.db.raw==wowDetectorDB.lsToasts.db)
assert(chat.options.WoWToolsLsToasts==C.options and _G.ls_Toasts[1]==E)
mock.Advance(1.5)
local immediateCount=#receipts
mock.bags[0][1].stackCount=12
mock.Fire("BAG_UPDATE",0)
assert(#receipts==immediateCount,"Bag scan ran inside the native update event")
mock.Advance(0)
assert(#receipts==immediateCount+1,"BAG_UPDATE waited for the delayed notification")
mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(0)
assert(#receipts==immediateCount+1,"Delayed notification duplicated the immediate bag gain")
mock.bags[0]={};mock.bags[1]={{itemID=100,stackCount=12}}
mock.Fire("BAG_UPDATE",1);mock.Advance(0)
assert(#receipts==immediateCount+1,"Cross-bag move was counted as loot before its second event")
mock.Fire("BAG_UPDATE",0);mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(0)
assert(#receipts==immediateCount+1)
local beforeQueries=mock.slotQueries
mock.bags[1][1].stackCount=13
mock.Fire("BAG_UPDATE",1);mock.Fire("BAG_UPDATE",0);mock.Fire("BAG_UPDATE_DELAYED")
assert(mock.slotQueries==beforeQueries)
mock.Advance(0)
assert(mock.slotQueries==beforeQueries+5,"Same-frame bag events ran multiple full scans")
assert(#receipts==immediateCount+2)
MerchantFrame=CreateFrame("Frame");MerchantFrame:Show()
mock.bags[1][1].stackCount=14;mock.Fire("BAG_UPDATE",1)
MerchantFrame:Hide();mock.Advance(0)
assert(#receipts==immediateCount+2,"Closing the merchant before the deferred scan lost suppression")
mock.bags[1][1].stackCount=15;mock.Fire("BAG_UPDATE_DELAYED");mock.Advance(0)
assert(#receipts==immediateCount+3,"Delayed-only event did not retain the fallback")
beforeQueries=mock.slotQueries
mock.Fire("BAG_UPDATE",secret);mock.Fire("BAG_UPDATE",-1);mock.Fire("BAG_UPDATE",5);mock.Advance(0)
assert(mock.slotQueries==beforeQueries,"Invalid bag event triggered a scan")
print("PASS: "..flavor.." lsToast settings/lifecycle, real skins/queue/opacity animation, loot/gold, next-frame/coalesced complete bag snapshots, cross-bag moves, merchant suppression, restricted data, deduplication and cancellation. Offline APIs only.")
