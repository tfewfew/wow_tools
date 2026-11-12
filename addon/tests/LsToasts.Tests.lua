local root=TEST_ROOT or "."
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
mock.LoadXML(root.."/addon/forerver/wow_tools/ls_toasts/ls_toasts.xml")
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
P:FlushQueue();assert(#P:GetActiveToasts(1)==0)

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
print("PASS: Forever lsToast namespace/login, full settings/profile persistence, menu/slash/combat, anchors, real toast skins/queue, gold/loss, loot chat/bag deduplication and disabled/pending scans. Offline APIs only.")
