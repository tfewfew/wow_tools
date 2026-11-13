-- Extend the existing offline UI and Ace adapters for the imported toast module.
return function(chatMock)
    local mock = {frames={}, timers={}, now=0, money=10000, bags={}, itemInfo={}, slotQueries=0, loggedIn=false, combat=false}
    local function Noop() end
    local function Adapt(frame)
        if frame.lsToastMock then return frame end
        frame.lsToastMock = true
        local createTexture, createFont, show = frame.CreateTexture, frame.CreateFontString, frame.Show
        function frame:CreateTexture(...) return Adapt(createTexture and createTexture(self, ...) or CreateFrame("Frame")) end
        function frame:CreateFontString(...) return Adapt(createFont and createFont(self, ...) or CreateFrame("Frame")) end
        function frame:CreateAnimationGroup() return Adapt(CreateFrame("Frame",nil,self)) end
        function frame:CreateAnimation() return Adapt(CreateFrame("Frame",nil,self)) end
        function frame:SetID(value) self.mockID=value end
        function frame:HookScript(event, callback)
            local previous = self.scripts[event]
            self:SetScript(event, function(...)
                if previous then previous(...) end
                callback(...)
            end)
        end
        function frame:SetShown(value) if value then self:Show() else self:Hide() end end
        function frame:GetID() return self.mockID or 1 end
        function frame:GetTextWidth() return #(self:GetText() or "") * 8 end
        function frame:GetCenter() return 960,540 end
        function frame:GetRight() return 1920 end
        function frame:GetTop() return 1080 end
        function frame:GetFrameLevel() return self.frameLevel or 1 end
        function frame:GetAlpha() return self.alpha or 1 end
        function frame:SetAlpha(value) self.alpha=value end
        function frame:SetFromAlpha(value) self.fromAlpha=value end
        function frame:SetToAlpha(value) self.toAlpha=value end
        function frame:SetChildKey(value) self.childKey=value end
        function frame:SetSmoothing(value) self.smoothing=value end
        function frame:GetSmoothProgress() return self.smoothProgress or 0 end
        function frame:GetNumPoints() return self.point and 1 or 0 end
        function frame:SetPoint(...)
            self.point={...}
            self.pointWrites=(self.pointWrites or 0)+1
        end
        function frame:GetPoint() return unpack(self.point or {}) end
        function frame:ClearAllPoints()
            self.point=nil
            self.pointWrites=(self.pointWrites or 0)+1
        end
        function frame:Show()
            self.showCalls=(self.showCalls or 0)+1
            return show(self)
        end
        function frame:SetFrameLevel(value) self.frameLevel=value end
        function frame:GetScale() return self.scale or 1 end
        function frame:SetScale(value) self.scale=value end
        function frame:Play()
            self.playing=true
            self.playCalls=(self.playCalls or 0)+1
            if self.Anim1 then self.Anim1.smoothProgress=0 end
        end
        function frame:Stop() self.playing=false end
        function frame:IsPlaying() return self.playing or false end
        function frame:GetDuration() return self.duration or 1 end
        function frame:SetDuration(value) self.duration=value end
        function frame:GetFont() return "test-font",12,"" end
        for _, state in ipairs({"Normal","Pushed","Highlight"}) do
            frame["Get" .. state .. "Texture"] = function(self)
                self["mock" .. state] = self["mock" .. state] or Adapt(CreateFrame("Frame"))
                return self["mock" .. state]
            end
        end
        for _, method in ipairs({"SetFixedFrameStrata","SetFixedFrameLevel","SetToplevel","SetClampRectInsets",
            "SetFlattensRenderLayers","SetJustifyV","SetVertexColor","SetTexelSnappingBias","SetSnapToPixelGrid",
            "SetDesaturated","SetGradient","SetBlendMode","SetTexture","SetTexCoord","SetColorTexture","SetFont",
            "SetJustifyH","SetAllPoints","SetPoint","SetParent","SetFormattedText","SetToFinalAlpha","SetChildKey",
            "SetOrder","SetFromAlpha","SetToAlpha","SetSmoothing","SetStartDelay","SetOffset","SetScript","EnableMouse"}) do
            if not frame[method] then frame[method]=Noop end
        end
        for _,method in ipairs({"SetMaxLines","SetWordWrap","SetNonSpaceWrap","SetShadowColor","SetShadowOffset",
            "SetAtlas","SetHorizTile","SetVertTile","EnableKeyboard","SetResizeBounds","SetTitle",
            "SetLabelText","SetCallback","UpdateLabelFont","SetMaxLetters","SetHideIfUnscrollable","SetClipsChildren",
            "SetHideTrackIfThumbExceedsTrack","SetPointsOffset","SetupMenu","SetDefaultText"}) do
            if not frame[method] then frame[method]=Noop end
        end
        mock.frames[#mock.frames+1]=frame
        return frame
    end
    local originalCreate=CreateFrame
    CreateFrame=function(kind,name,parent,template)
        local frame=Adapt(originalCreate(kind,name,parent,template))
        if template=="InputScrollFrameTemplate" then
            frame.EditBox=CreateFrame("EditBox",nil,frame)
            frame.EditBox.Instructions=CreateFrame("Frame",nil,frame.EditBox)
            frame.CharCount,frame.ScrollBar=CreateFrame("Frame",nil,frame),CreateFrame("Frame",nil,frame)
        elseif template=="DefaultPanelTemplate" then
            frame.Bg,frame.NineSlice=CreateFrame("Frame",nil,frame),CreateFrame("Frame",nil,frame)
            frame.NineSlice.RightEdge=CreateFrame("Frame",nil,frame.NineSlice)
        end
        return frame
    end
    UIParent,GameTooltip=Adapt(UIParent),Adapt(GameTooltip)
    ShoppingTooltip1,ShoppingTooltip2=CreateFrame("Frame"),CreateFrame("Frame")
    BattlePetTooltip,GarrisonFollowerTooltip,GarrisonShipyardFollowerTooltip=CreateFrame("Frame"),CreateFrame("Frame"),CreateFrame("Frame")
    SettingsPanel=CreateFrame("Frame")
    AlertFrame=CreateFrame("Frame")
    HideUIPanel=Noop
    SquareButton_SetIcon=Noop
    IsLoggedIn=function() return mock.loggedIn end
    GetBuildInfo=function()
        if TEST_FLAVOR=="titan" then return "3.80.2","70522","",38002 end
        return "1.60.1","70888","",16001
    end
    Enum = Enum or {}
    Enum.EditModePresetLayouts={Modern=1,Classic=2}
    Enum.CompressionMethod={Deflate=1}
    C_EditMode={GetEditModeDefaultLayout=function() return 1 end}
    GAMEMENU_OPTIONS,ADVANCED_OPTIONS,INFO,MAINMENU_BUTTON,HUD_EDIT_MODE_MENU="选项","高级选项","信息","菜单","编辑模式"
    FILTERS,NEW,DELETE,HUD_EDIT_MODE_IMPORT_LAYOUT,HUD_EDIT_MODE_EXPORT_LAYOUT="过滤","新建","删除","导入","导出"
    LOOTUPGRADEFRAME_TITLE="升级 %s"
    RUNEFORGE_LEGENDARY_POWER_TOOLTIP_SLOT_HEADER="部位 %s"
    RUNEFORGE_LEGENDARY_POWER_SOURCE_FORMAT="来源 %s"
    RUNEFORGE_LEGENDARY_POWER_REQUIRES_SPEC_FORMAT="专精 %s"
    AddonCompartmentFrame={RegisterAddon=Noop}
    EventRegistry={UnregisterFrameEvent=Noop,GetCallbackTables=function() return {} end}
    PanelTemplates_SetNumTabs,PanelTemplates_SetTab,PanelTemplates_TabResize=Noop,Noop,Noop
    C_CurrencyInfo={GetCurrencyListSize=function() return 0 end}
    PixelUtil={
        GetPixelToUIUnitFactor=function() return 1 end,
        SetPoint=function(frame,...) frame:SetPoint(...) end,
        SetSize=function(frame,...) frame:SetSize(...) end,
        SetWidth=function(frame,value) frame:SetWidth(value) end,
        SetHeight=function(frame,value) frame:SetHeight(value) end,
    }
    ColorMixin={
        SetRGBA=function(self,r,g,b,a) self.r,self.g,self.b,self.a=r,g,b,a or 1 end,
        GenerateHexColor=function() return "ffffffff" end,
        WrapTextInColorCode=function(_,text) return text end,
        GetRGB=function(self) return self.r,self.g,self.b end,
    }
    Mixin=function(target,...)
        for _,source in ipairs({...}) do for key,value in pairs(source) do target[key]=value end end
        return target
    end
    GetTime=function() return mock.now end
    GetMoney=function() return mock.money end
    GetMoneyString=function(value) return tostring(value) end
    IsShiftKeyDown=function() return false end
    IsModifiedClick=function() return false end
    IsControlKeyDown=function() return false end
    PlaySound,PlaySoundFile=Noop,Noop
    NUM_BAG_SLOTS=4
    local unitGUID=UnitGUID
    UnitGUID=function(unit) if unit=="player" then return "Player-test" end; return unitGUID and unitGUID(unit) end
    local lockdown=InCombatLockdown
    InCombatLockdown=function() return mock.combat or (lockdown and lockdown()) or false end
    C_Timer={After=function(delay,callback) mock.timers[#mock.timers+1]={due=mock.now+delay,callback=callback} end}
    C_Timer.NewTicker=function() return {Cancel=Noop} end
    C_EventUtils={IsEventValid=function(event) return event~="STORE_PRODUCT_DELIVERED" end}
    C_Container=C_Container or {}
    local originalSlots=C_Container.GetContainerNumSlots
    local originalItemInfo=C_Container.GetContainerItemInfo
    C_Container.GetContainerNumSlots=function(bag)
        mock.slotQueries=mock.slotQueries+1
        if mock.bags[bag] then return #mock.bags[bag] end
        return originalSlots and originalSlots(bag) or 0
    end
    C_Container.GetContainerItemInfo=function(bag,slot)
        if mock.bags[bag] then return mock.bags[bag][slot] end
        return originalItemInfo and originalItemInfo(bag,slot)
    end
    C_Container.GetContainerItemID=function(bag,slot) local item=(mock.bags[bag] or {})[slot];return item and item.itemID end
    C_Item=C_Item or {}
    local originalGetItemInfo=C_Item.GetItemInfo
    local originalGetItemInfoInstant=C_Item.GetItemInfoInstant
    C_Item.GetItemInfo=function(id)
        id=tonumber(id) or tonumber(type(id)=="string" and id:match("item:(%d+)"))
        local data=mock.itemInfo[id]
        if data then return data.name,"item:"..id,data.quality or 1,10,0,nil,nil,nil,"INVTYPE_HEAD",123,nil,data.classID or 0,data.subClassID or 0,data.bindType or 0 end
        return originalGetItemInfo and originalGetItemInfo(id)
    end
    C_Item.GetItemInfoInstant=function(id)
        if mock.itemInfo[id] then return id end
        if originalGetItemInfoInstant then return originalGetItemInfoInstant(id) end
    end
    C_Item.GetDetailedItemLevelInfo=function() return 10 end
    ITEM_QUALITY_COLORS={}
    for quality=0,7 do
        ITEM_QUALITY_COLORS[quality]={r=1,g=1,b=1,hex="|cffffffff"}
        _G["ITEM_QUALITY"..quality.."_DESC"]="品质"..quality
    end
    LOOT_ITEM_SELF="你获得了物品：%s。"
    LOOT_ITEM_SELF_MULTIPLE="你获得了物品：%sx%d。"
    LOOT_ITEM_PUSHED_SELF="你得到了物品：%s。"
    LOOT_ITEM_PUSHED_SELF_MULTIPLE="你得到了物品：%sx%d。"
    LOOT_ITEM_CREATED_SELF="你制造了物品：%s。"
    LOOT_ITEM_CREATED_SELF_MULTIPLE="你制造了物品：%sx%d。"
    local nativeXpcall=xpcall
    xpcall=function(callback,handler,...) local arguments={...};return nativeXpcall(function() return callback(unpack(arguments)) end,handler) end
    geterrorhandler=function() return function(message) error(message) end end
    string.split=function(separator,value)
        local result={}
        for part in (value..separator):gmatch("(.-)"..separator) do result[#result+1]=part end
        return unpack(result)
    end
    table.wipe=function(values) wipe(values);return values end
    string.trim=function(value) return value:match("^%s*(.-)%s*$") end
    local nativeFormat = string.format
    string.format = function(pattern, ...)
        local arguments = {...}
        if pattern:find("%%%d+%$") then
            return (pattern:gsub("%%(%d+)%$([sd])", function(index, kind)
                return nativeFormat("%"..kind, arguments[tonumber(index)])
            end))
        end
        return nativeFormat(pattern, ...)
    end
    local libraries=chatMock.libraries
    libraries["CallbackHandler-1.0"]={New=function() return {Fire=Noop} end}
    libraries["AceConfig-3.0"]={RegisterOptionsTable=function(_,name,options) chatMock.options[name]=options end}
    libraries["LibSharedMedia-3.0"]={
        HashTable=function() return {["默认字体"]="test-font"} end,
        GetDefault=function() return "默认字体" end,
        IsValid=function(_,kind,name) return name=="默认字体" end,
        Fetch=function() return "test-font" end,
        RegisterCallback=Noop,
    }
    mock.namespace = {LibEditMode={
        GetActiveLayoutName=function() return "Modern" end,
        RegisterCallback=Noop,AddFrame=Noop,AddFrameSettings=Noop,
        SettingType={Slider=1,Divider=2,Dropdown=3},
    }}
    function mock.LoadXML(path)
        local file=assert(io.open(path));local xml=file:read("*a");file:close()
        xml=xml:gsub("<!%-%-.-%-%->", "")
        local directory=path:match("^(.*[/\\])")
        for tag,relative in xml:gmatch("<(%w+)%s+file=['\"]([^'\"]+)['\"]") do
            local child=directory..relative:gsub("\\","/")
            if not child:find("/embeds/",1,true) then
                if tag=="Include" then mock.LoadXML(child)
                elseif tag=="Script" then assert(loadfile(child))("wow_tools", mock.namespace) end
            end
        end
    end
    function mock.Fire(event,...)
        local snapshot={unpack(mock.frames)}
        for _,frame in ipairs(snapshot) do
            if frame.events and frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame,event,...) end
        end
    end
    function mock.Advance(seconds)
        mock.now=mock.now+seconds
        local pending=mock.timers;mock.timers={}
        for _,timer in ipairs(pending) do
            if timer.due<=mock.now then timer.callback() else mock.timers[#mock.timers+1]=timer end
        end
    end
    function mock.FinishAnimation(group)
        group.playing=false
        if group.scripts.OnFinished then group.scripts.OnFinished(group) end
    end
    return mock
end
