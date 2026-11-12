local root = TEST_ROOT or "."
local addon = root .. "/addon/forerver/wow_tools/"
local frames, messages = {}, {}
local function Widget(name)
    local object = {scripts={}, events={}, shown=true, text="", width=500, height=300}
    function object:SetScript(event, callback) self.scripts[event]=callback end
    function object:RegisterEvent(event) self.events[event]=true end
    function object:UnregisterEvent(event) self.events[event]=nil end
    function object:Show() local was=self.shown; self.shown=true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function object:Hide() local was=self.shown; self.shown=false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function object:IsShown() return self.shown end
    function object:SetText(text) self.text=text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function object:GetText() return self.text end
    function object:SetPoint(...) self.point={...} end
    function object:GetPoint() return unpack(self.point or {"TOPLEFT",UIParent,"TOPLEFT",0,0}) end
    function object:SetSize(width,height) self.width,self.height=width,height end
    function object:GetWidth() return self.width end
    function object:GetHeight() return self.height end
    function object:GetFont() return "test-font",12,"" end
    function object:GetEffectiveScale() return 1 end
    function object:AddMessage(text) messages[#messages+1]=text end
    for _, method in ipairs({"SetFrameStrata","SetClampedToScreen","SetMovable","SetAlpha","SetFontObject",
        "SetWidth","SetMultiLine","SetAutoFocus","ClearAllPoints","SetNormalTexture","SetOwner","SetScrollChild",
        "RegisterForDrag","EnableMouse","StartMoving","StopMovingOrSizing","SetHighlightTexture"}) do
        object[method]=function() end
    end
    frames[#frames+1]=object
    return object
end
CreateFrame=function(kind,name,parent,template)
    assert(template ~= "UIDropDownMenuTemplate", "Legacy dropdown restored")
    local object=Widget(name)
    if template == "BasicFrameTemplateWithInset" then object.TitleText=Widget() end
    return object
end
GameTooltip=Widget()
DEFAULT_CHAT_FRAME=Widget()
SlashCmdList,UISpecialFrames={},{}
WoWTools={modules={}}
Settings={OpenToCategory=function(category) assert(category=="keybindings") end}
local mock=dofile(root .. "/addon/tests/BigFootChannel.Mock.lua")
local secret=setmetatable({}, {__tostring=function() error("Printed restricted chat") end})
issecretvalue=function(value) return rawequal(value,secret) end
local originalTextChanges=0
ChatFrame1EditBox:SetScript("OnTextChanged",function() originalTextChanges=originalTextChanges+1 end)
wowDetectorDB={soundControl={minimapAngle=315}, bigfootChannel={chat={profiles={Default={mute=true,enablecopy=true}}},
    filter={Enabled=1,BanEnabled=1,IgnoreWords={"测试广告"},OrderWords={"组队"}}}}
for line in io.lines(addon .. "wow_tools.toc") do
    if line:match("^bigfoot_channel") then
        local path=addon .. line:gsub("\\","/"):gsub("%s+$","")
        mock.LoadAddonFile(path)
    end
end
for _,frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame,"ADDON_LOADED","wow_tools") end
end
local channel=WoWTools.bigfootChannel
local chat=channel.addon
local options=mock.options.WoWToolsBigFootChannel()
C_CVar={GetCVar=function() return mock.timestamp or "none" end,
    SetCVar=function(_,value) mock.timestamp=value end}
assert(not options.args.general.args.enabletimestamp.get())
options.args.general.args.enabletimestamp.set(nil,true)
assert(CHAT_TIMESTAMP_FORMAT=="%I:%M %p" and options.args.general.args.enabletimestamp.get())
options.args.general.args.enabletimestamp.set(nil,false)
assert(CHAT_TIMESTAMP_FORMAT==nil and mock.timestamp=="none")
assert(options.name=="bigfoot_channel" and options.childGroups=="tab")
for _,tab in ipairs({"general","CHATFRAME","ICONFRAME","world","filters","Profiles"}) do assert(options.args[tab],tab) end
assert(chat.db.profile.mute and chat.db.profile.enablecopy and wowDetectorDB.soundControl.minimapAngle==315)
assert(wowToolsChatCopyButton:IsShown() and not ChatFrame1.channelEnabled)
SlashCmdList.WOWTOOLSBIGFOOT("filter")
assert(WoWTools.modules.bigfoot_channel.IsShown() and mock.selectedTab=="filters")
WoWTools.modules.bigfoot_channel.Toggle()
assert(not WoWTools.modules.bigfoot_channel.IsShown())

local settings=channel.GetFilterSettings()
local line=0
local function Filter(text,sender,event,name,index,identity)
    line=line+1
    return channel.FilterMessage(ChatFrame1,event or "CHAT_MSG_CHANNEL",text,sender or "其他玩家",nil,
        name or "6. 大脚世界频道",nil,nil,0,index or 6,name or "大脚世界频道",nil,identity or line)
end
assert(Filter("测 试 广 告"),"Punctuation/keyword filtering lost")
assert(not Filter("普通消息"),"Normal message blocked")
assert(Filter("普通消息"),"Repeated message passed")
mock.now=111
assert(not Filter("普通消息"),"10-second duplicate limit did not expire")
assert(not Filter("测试广告","测试角色-测试服务器"),"Own message filtered")
assert(not Filter(secret),"Restricted message filtered")
assert(not Filter("x",secret),"Restricted sender inspected")
mock.lockdown=true; assert(not Filter("测试广告"));mock.lockdown=false
settings.OrderEnabled=1
assert(Filter("出售物品","白名单测试"),"Whitelist did not filter")
assert(not Filter("组队下本","白名单命中"),"Whitelist match blocked")
settings.OrderEnabled=nil
settings.mute=1
assert(Filter("综合消息","普通频道","CHAT_MSG_CHANNEL","综合",1))
assert(not Filter("世界消息","世界频道静音测试"))
assert(Filter("制造物品","专业频道","CHAT_MSG_TRADESKILLS"))
settings.mute=nil
settings.Enabled=nil;assert(not Filter("测试广告"));settings.Enabled=1
options.args.filters.args.IgnoreWords.set(nil,"一个词\n一个词\n第二个词\n[")
assert(#settings.IgnoreWords==3 and not Filter("正常消息","模式错误测试"))
options.args.filters.args.OrderEnabled.set(nil,true)
assert(settings.OrderEnabled==1,"Whitelist setting not persisted")
options.args.filters.args.OrderEnabled.set(nil,false)
SlashCmdList.GUOLV("+ 新关键词");assert(settings.IgnoreWords[4]=="新关键词")
SlashCmdList.GUOLV("- 新关键词");assert(#settings.IgnoreWords==3)

local world=channel.worldChannel
world.scripts.OnEvent(world,"PLAYER_ENTERING_WORLD")
assert(#mock.timers==1 and mock.timers[1].delay==3 and mock.joins==0)
local first=table.remove(mock.timers,1); first.callback()
assert(mock.joins==1 and mock.timers[1].delay==5)
options.args.world.args.autoJoin.set(nil,false)
table.remove(mock.timers,1).callback()
assert(mock.joins==1 and not world.active,"Canceled join timer still ran")
options.args.world.args.autoJoin.set(nil,true)
mock.channelID=6
table.remove(mock.timers,1).callback()
assert(world.state=="muted" and not ChatFrame1.channelEnabled)
options.args.world.args.mute.set(nil,false)
assert(ChatFrame1.channelEnabled)
mock.channelID=0;mock.timers={};SlashCmdList.BIGFOOTWORLDCHANNEL("join")
while #mock.timers>0 do table.remove(mock.timers,1).callback() end
assert(world.state=="failed" and world.attempts==6,"Join retries not bounded")
channel.StartWorldChannel()
world.scripts.OnEvent(world,"CHAT_MSG_CHANNEL_NOTICE","BANNED",nil,nil,"大脚世界频道")
assert(world.state=="failed" and not world.active)
while #mock.timers>0 do table.remove(mock.timers,1).callback() end

chat:SetModuleEnabled("ICONFRAME",false)
assert(not BFCIconFrameCalloutButton:IsShown() and not BFCIconFrameReportButton:IsShown())
chat:SetModuleEnabled("ICONFRAME",true)
ChatFrame1EditBox:SetText("original")
assert(originalTextChanges>0,"Emote hook replaced native OnTextChanged")
local emote=mock.filters.CHAT_MSG_SAY[1]
local blocked,text=emote(ChatFrame1,"CHAT_MSG_SAY","{大笑}")
assert(not blocked and text:find("wow_tools\\bigfoot_channel\\icon\\biglaugh.tga",1,true))
chat:SetModuleEnabled("CHATFRAME",false)
for _,frame in ipairs(frames) do assert(not frame.events.CHANNEL_UI_UPDATE or frame==world,"Disabled shortcut bar retained event") end
chat:SetModuleEnabled("CHATFRAME",true)
BFC_SetChatType("/g ");assert(ChatFrame1EditBox:GetText()=="/g original")
ChatFrame1.messages={"|cffffffff你好|r |Hplayer:Test|h[玩家]|h",secret,"第二行"}
wowToolsChatCopyButton.scripts.OnClick()
assert(wowToolsChatCopyPanel:IsShown())
local copied
for _,frame in ipairs(frames) do if frame.highlighted then copied=frame:GetText() end end
assert(copied=="你好 [玩家]\n第二行","Copy failed to preserve readable text")
options.args.general.set({"general","enablecopy"},false)
assert(not wowToolsChatCopyButton:IsShown() and not wowToolsChatCopyPanel:IsShown())
chat.db.profile.enablecopy=true
chat.db.callbacks.OnProfileChanged()
assert(wowToolsChatCopyButton:IsShown(),"Profile callback retained stale settings")
assert(wowDetectorDB.bigfootChannel.chat==chat.db.raw,"Chat DB detached from account settings")
local menuButtons={}
MenuUtil={CreateContextMenu=function(owner,generator)
    generator(owner,{CreateTitle=function() end,CreateButton=function(_,title,callback)
        menuButtons[#menuButtons+1]=callback
    end})
end}
mock.zone=next(Raid_List)
createRaidersFrame()
assert(BFCIconFrameRaidersButton:IsShown())
BFCIconFrameRaidersButton.scripts.OnClick(BFCIconFrameRaidersButton)
assert(#menuButtons>0)
menuButtons[1]()
local preview=messages[#messages]:match("|H(wowtoolsraider:%d+)|h")
assert(preview,"Raid strategy preview link absent")
mock.hooks.SetItemRef(preview)
assert(#mock.sent==2 and mock.sent[1][2]=="SAY","Strategy action did not use the native chat API")
mock.hooks.SetItemRef("item:123")
assert(#mock.sent==2)
MAX_SPELL_SCHOOLS=7
CR_CRIT_SPELL,CR_CRIT_RANGED,CR_CRIT_MELEE,CR_MASTERY=1,2,3,4
C_SpecializationInfo={GetSpecialization=function() return 1 end,
    GetSpecializationInfo=function() return 1,"测试专精",nil,nil,"DAMAGER" end}
DAMAGER="伤害"
UnitLevel=function() return 70 end
UnitClass=function() return "战士","WARRIOR" end
GetAverageItemLevel=function() return 123,120 end
GetMasteryEffect,GetSpellCritChance,GetRangedCritChance,GetCritChance,GetHaste=function() return 10 end,
    function() return 10 end,function() return 10 end,function() return 10 end,function() return 10 end
GetCombatRating,GetCombatRatingBonus=function() return 10 end,function() return 10 end
ChatFrame1EditBox:SetText("")
BFCIconFrameReportButton_OnClick(BFCIconFrameReportButton,"LeftButton")
assert(ChatFrame1EditBox:GetText():find("测试专精",1,true),"Personal stat report failed")
print("PASS: Forever chat/XML/Ace lifecycle, six settings tabs, account profiles, native text hooks, emotes/copy/shortcuts, blacklist/whitelist/mute/restrictions, bounded join retries/cancellation and menu APIs. Offline mocks only.")
