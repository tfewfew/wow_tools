local root = TEST_ROOT or "."
for _, flavor in ipairs({"titan", "forerver"}) do
    local frames, widgets, named, timers = {}, {}, {}, {}
    local combat, scans, callback, media = false, 0, nil, nil
    local secret = setmetatable({}, {__tostring=function() error("restricted string") end})
    local function widget(kind, name, parent)
        local object = {kind=kind, name=name, parent=parent, scripts={}, hooks={}, events={},
            textures={}, shown=true, enabled=true, text="", alpha=1}
        function object:SetScript(event, fn) self.scripts[event]=fn end
        function object:HookScript(event, fn)
            self.hooks[event]=self.hooks[event] or {}
            self.hooks[event][#self.hooks[event]+1]=fn
        end
        function object:Run(event, ...)
            if self.scripts[event] then self.scripts[event](self, ...) end
            for _,fn in ipairs(self.hooks[event] or {}) do fn(self, ...) end
        end
        function object:RegisterEvent(event) self.events[event]=true end
        function object:UnregisterEvent(event) self.events[event]=nil end
        function object:CreateTexture()
            local texture=widget("Texture",nil,self)
            self.textures[#self.textures+1]=texture
            return texture
        end
        function object:CreateFontString() return widget("FontString",nil,self) end
        function object:IsObjectType(value) return self.kind==value end
        function object:IsForbidden() return self.forbidden==true end
        function object:SetSize(w,h) self.width,self.height=w,h end
        function object:GetHeight() return self.height or 20 end
        function object:GetStringHeight() return 20 end
        function object:GetFont() return "mock-font",12,"" end
        function object:SetHeight(h) self.height=h end
        function object:SetPoint(...) self.point={...} end
        function object:SetColorTexture(...) self.color={...} end
        function object:SetVertexColor(...) self.vertex={...} end
        function object:SetBlendMode(value) self.blend=value end
        function object:GetBlendMode() return self.blend or "BLEND" end
        function object:GetTexture() return self.path end
        function object:GetAtlas() return self.atlas end
        function object:SetTexture(path) self.path=path; self.atlas=nil end
        function object:SetAtlas(atlas) self.atlas=atlas;self.path=9000 end
        function object:SetAlpha(alpha) self.alpha=alpha end
        function object:GetAlpha() return self.alpha end
        function object:SetText(text)
            self.text=text
            if self.scripts.OnTextChanged then self:Run("OnTextChanged") end
        end
        function object:GetText() return self.text end
        function object:SetChecked(value) self.checked=value end
        function object:GetChecked() return self.checked end
        function object:Show()
            local changed=not self.shown;self.shown=true
            if changed then self:Run("OnShow") end
        end
        function object:Hide()
            local changed=self.shown;self.shown=false
            if changed then self:Run("OnHide") end
        end
        function object:IsShown() return self.shown end
        function object:Disable() self.enabled=false;self:Run("OnDisable") end
        function object:Enable() self.enabled=true;self:Run("OnEnable") end
        function object:SetEnabled(value) if value then self:Enable() else self:Disable() end end
        for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
            object["Get"..state.."Texture"]=function(self) return self[state.."Texture"] end
            object["Set"..state.."Texture"]=function(self, texture)
                if self.reject and combat and state=="Pushed" then error("fixture protected texture") end
                if type(texture)=="string" then
                    local region=self:CreateTexture();region:SetTexture(texture);texture=region
                end
                self[state.."Texture"]=texture
                if state=="Highlight" and texture then texture:SetBlendMode("ADD") end
            end
        end
        for _,method in ipairs({"SetFrameStrata","SetClampedToScreen","EnableMouse","EnableMouseWheel",
            "SetAllPoints","SetBlendMode","SetTexCoord","SetWidth","SetJustifyH","SetAutoFocus",
            "ClearAllPoints","SetHighlightTexture","SetFont","SetScrollChild","SetNumeric","SetMaxLetters",
            "ClearFocus","SetMovable","RegisterForDrag","StartMoving","StopMovingOrSizing"}) do
            if not object[method] then object[method]=function() end end
        end
        widgets[#widgets+1]=object
        if name then named[name]=object end
        return object
    end
    function CreateFrame(kind,name,parent,template)
        local frame=widget(kind,name,parent)
        frames[#frames+1]=frame
        if template=="UIPanelButtonTemplate" then
            for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
                local texture=frame:CreateTexture()
                texture:SetTexture(state=="Normal" and 4200 or "native-"..state)
                frame[state.."Texture"]=texture
            end
        end
        if template=="MinimalTabTemplate" then frame.Text=widget("FontString",nil,frame) end
        if template=="BasicFrameTemplateWithInset" then frame.TitleText=widget("FontString",nil,frame) end
        return frame
    end
    function EnumerateFrames(previous)
        if not previous then scans=scans+1;return frames[1] end
        for index,frame in ipairs(frames) do if frame==previous then return frames[index+1] end end
    end
    function hooksecurefunc(target, method, fn)
        if type(target)=="string" then fn=method;method=target;target=_G end
        local original=target[method]
        target[method]=function(...)
            local result={original(...)}
            fn(...)
            return unpack(result)
        end
    end
    function issecretvalue(value) return rawequal(value,secret) end
    function InCombatLockdown() return combat end
    C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
    UIParent=widget("Frame")
    WoWTools={};wowDetectorDB={untouched="keep"};UISpecialFrames={};LibStub=nil
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    dofile(addon.."ButtonStyle.lua")
    dofile(addon.."ButtonStyle.Settings.lua")
    local style=WoWTools.buttonStyle
    local function event(name, addonName)
        for _,frame in ipairs(frames) do if frame.events[name] then frame:Run("OnEvent",name,addonName) end end
    end
    local function flush()
        local pending=timers;timers={}
        for _,fn in ipairs(pending) do fn() end
    end
    local menu=CreateFrame("Button","GameMenuButtonOptions",UIParent,"UIPanelButtonTemplate")
    local original=menu:GetNormalTexture()
    local originalHighlight=menu:GetHighlightTexture()
    local clicked=0
    menu:SetScript("OnClick",function() clicked=clicked+1 end)
    local click=menu.scripts.OnClick
    local modern=CreateFrame("Button",nil,UIParent)
    modern.atlasName="128-RedButton"
    modern.Left=modern:CreateTexture();modern.Center=modern:CreateTexture();modern.Right=modern:CreateTexture()
    modern.Left:SetAtlas("128-RedButton-Left")
    modern.Left:SetAlpha(.7)
    modern.UpdateButton=function(self)
        self.Left:SetAtlas("128-RedButton-Left-Pressed")
        self.Left:SetAlpha(1)
    end
    local legacySlices=CreateFrame("Button",nil,UIParent)
    for _,key in ipairs({"Left","Middle","Right"}) do
        legacySlices[key]=legacySlices:CreateTexture()
        legacySlices[key]:SetTexture(4200)
    end
    local icon=CreateFrame("Button",nil,UIParent)
    icon:SetNormalTexture(icon:CreateTexture());icon:GetNormalTexture():SetTexture(7777)
    local refreshIcon=CreateFrame("Button",nil,UIParent)
    refreshIcon.buttonArtKit="128-RedButton-Refresh"
    refreshIcon:SetNormalTexture(refreshIcon:CreateTexture());refreshIcon:GetNormalTexture():SetAtlas("128-RedButton-Refresh")
    local refreshTexture=refreshIcon:GetNormalTexture()
    local forbidden=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate");forbidden.forbidden=true
    local blocked=forbidden:GetNormalTexture()
    local restricted=CreateFrame("Button",nil,UIParent)
    restricted:SetNormalTexture(restricted:CreateTexture());restricted:GetNormalTexture():SetTexture(secret)
    event("ADDON_LOADED","wow_tools")
    assert(menu:GetNormalTexture()==original and original.alpha==1 and scans==0,"Default off modified native buttons")
    local value=style.GetConfig();value.enabled=true;value.colors.normal={.2,.4,.7,.6}
    assert(style.Save(value))
    assert(menu:GetNormalTexture()~=original and original.alpha==0,"Legacy file-ID button not styled")
    assert(menu:GetNormalTexture().path=="Interface\\Buttons\\WHITE8X8" and menu:GetNormalTexture().vertex[4]==.6)
    assert(modern.Left.alpha==0 and modern:GetNormalTexture(),"Three-slice button not styled")
    assert(legacySlices.Left.alpha==0 and legacySlices:GetNormalTexture(),"Legacy sliced file-ID button not styled")
    modern:UpdateButton()
    assert(modern.Left.alpha==0,"Native state update restored original artwork")
    assert(icon:GetNormalTexture().path==7777 and forbidden:GetNormalTexture()==blocked,"Unrelated/forbidden button styled")
    assert(refreshIcon:GetNormalTexture()==refreshTexture and refreshTexture.alpha==1,"Icon glyph was replaced by panel styling")
    menu:Run("OnClick")
    assert(clicked==1 and menu.scripts.OnClick==click,"Styling replaced native click handling")
    local late=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    local lateOriginal=late:GetNormalTexture()
    CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    local before=scans
    assert(#timers==1,"Button creation did not batch discovery")
    flush()
    assert(scans==before+1 and late:GetNormalTexture()~=lateOriginal,"Anonymous late buttons were missed")
    value=style.GetConfig();value.material="lsm:Smooth";assert(style.Save(value))
    assert(menu:GetNormalTexture().path=="Interface\\Buttons\\WHITE8X8" and style.lastStatus:find("暂用纯色",1,true))
    media={Smooth="mock-smooth",Zeta="mock-zeta",Alpha="mock-alpha"}
    local library={HashTable=function() return media end, RegisterCallback=function(_,_,fn) callback=fn end}
    LibStub={GetLibrary=function() return library end}
    event("ADDON_LOADED","Plater")
    assert(menu:GetNormalTexture().path=="mock-smooth" and callback,"Late shared media was not resolved")
    media.Smooth="mock-new-smooth";callback("LibSharedMedia_Registered","statusbar","Smooth")
    assert(menu:GetNormalTexture().path=="mock-new-smooth")
    local materials=style.GetMaterials()
    assert(materials[3].label=="Alpha" and materials[4].label=="Smooth" and materials[5].label=="Zeta","Shared media list is not sorted")
    local saved=wowDetectorDB.buttonStyle
    value=style.GetConfig();value.colors.normal[1]=2
    assert(not style.Save(value) and wowDetectorDB.buttonStyle==saved,"Invalid draft partly saved")
    value=style.GetConfig();value.material="Interface\\arbitrary"
    assert(not style.Save(value),"Unsupported material key accepted")

    local parent=CreateFrame("Frame",nil,UIParent)
    style.BuildSettings(parent)
    local editor=style.editors[1]
    assert(parent.height==style.settingsHeight and editor.disabled.enabled==false)
    editor.material:Run("OnClick")
    local popup=named.WoWToolsButtonMaterialMenu
    assert(popup.shown and popup.rows[3].entry.label=="Alpha" and popup.rows[3].sample.path=="mock-alpha")
    popup.search:SetText("Zeta")
    assert(popup.rows[1].entry.label=="Zeta" and not popup.rows[2].shown)
    popup.rows[1]:Run("OnClick")
    assert(wowDetectorDB.buttonStyle.material=="lsm:Zeta" and not popup.shown)

    ColorPickerFrame=widget("Frame")
    function ColorPickerFrame:SetupColorPickerAndShow(info) self.info=info;self.rgb={info.r,info.g,info.b};self.opacity=info.opacity;self:Show() end
    function ColorPickerFrame:GetColorRGB() return unpack(self.rgb) end
    function ColorPickerFrame:GetColorAlpha() return self.opacity end
    editor.swatches.normal:Run("OnClick")
    assert(ColorPickerFrame.info.opacity==.6,"Modern opacity was inverted")
    ColorPickerFrame.rgb={.7,.2,.3};ColorPickerFrame.opacity=.4;ColorPickerFrame.info.swatchFunc()
    assert(wowDetectorDB.buttonStyle.colors.normal[1]==.7 and wowDetectorDB.buttonStyle.colors.normal[4]==.4)
    ColorPickerFrame:Hide();ColorPickerFrame.info.cancelFunc()
    assert(wowDetectorDB.buttonStyle.colors.normal[1]==.2 and wowDetectorDB.buttonStyle.colors.normal[4]==.6,"Cancel did not revert persisted RGBA")
    editor.swatches.normal:Run("OnClick")
    ColorPickerFrame.rgb={.3,.6,.8};ColorPickerFrame.opacity=.9;ColorPickerFrame.info.opacityFunc()
    ColorPickerFrame:Hide() -- Accept, then open another swatch.
    editor.swatches.pushed:Run("OnClick")
    assert(wowDetectorDB.buttonStyle.colors.normal[1]==.3,"Opening a new picker reverted an accepted color")
    ColorPickerFrame.rgb={.4,.5,.6};ColorPickerFrame.info.swatchFunc()
    editor.swatches.highlight:Run("OnClick")
    assert(wowDetectorDB.buttonStyle.colors.pushed[1]==.4,"Switching swatches discarded a live saved color")
    local staleCancel=ColorPickerFrame.info.cancelFunc
    style.Reset();staleCancel()
    assert(wowDetectorDB.buttonStyle==nil and wowDetectorDB.untouched=="keep","Reset was undone by a stale color callback")
    assert(menu:GetNormalTexture()==original and original.alpha==1 and modern.Left.alpha==.7 and not modern:GetNormalTexture(),"Reset did not restore original bindings and alpha")
    assert(originalHighlight:GetBlendMode()=="BLEND","Reset changed original highlight blending")

    ColorPickerFrame.SetupColorPickerAndShow=nil
    function ColorPickerFrame:SetColorRGB(r,g,b) self.rgb={r,g,b} end
    OpacitySliderFrame={GetValue=function() return .8 end}
    editor.swatches.normal:Run("OnClick")
    ColorPickerFrame.rgb={.1,.2,.3};ColorPickerFrame.func()
    assert(math.abs(wowDetectorDB.buttonStyle.colors.normal[4]-.2)<.001,"Legacy transparency was not inverted")
    ColorPickerFrame.cancelFunc()
    ColorPickerFrame:Hide()
    assert(wowDetectorDB.buttonStyle.colors.normal[4]==1,"Legacy cancel did not restore alpha")

    local protected=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    local protectedOriginal=protected:GetNormalTexture()
    protected.reject=true;combat=true
    value=style.GetConfig();value.enabled=true
    local ok,message=style.Save(value)
    assert(ok and message:find("待重试",1,true),"A partial texture failure reported full success")
    combat=false;event("PLAYER_REGEN_ENABLED")
    assert(protected:GetNormalTexture()~=protectedOriginal,"Deferred button did not retry")
    protected:SetPushedTexture(protected:CreateTexture())
    combat=true;style.Apply(false);style.Reset()
    assert(style.lastStatus:find("待恢复",1,true),"Deferred restoration was reported as finished")
    combat=false;event("PLAYER_REGEN_ENABLED")
    assert(protected:GetNormalTexture()==protectedOriginal,"Deferred restoration did not finish")
    value=style.GetConfig();value.enabled=true;style.Save(value)
    local persisted=wowDetectorDB.buttonStyle
    style.Reset()
    assert(protected:GetNormalTexture()==protectedOriginal,"Partially styled button could not restore")
    wowDetectorDB.buttonStyle=persisted
    for _,frame in ipairs(frames) do frame.events={} end -- A reload disposes old event handlers.
    dofile(addon.."ButtonStyle.lua")
    dofile(addon.."ButtonStyle.Settings.lua")
    event("ADDON_LOADED","wow_tools")
    assert(WoWTools.buttonStyle.GetConfig().enabled and menu:GetNormalTexture()~=original,"Reload did not apply saved appearance")
    for _,frame in ipairs(frames) do assert(not frame.scripts.OnUpdate,"Appearance added permanent polling") end
    WoWTools.modules={};SlashCmdList={}
    function CreateRadioButtonGroup() return {AddButton=function() end,SelectAtIndex=function() end} end
    if flavor=="forerver" then dofile(addon.."DisplayFonts.lua") end
    dofile(addon.."inner_graphic_config/Core.lua")
    WoWTools.modules.inner_graphic_config.Show()
    local tabs=0
    for _,object in ipairs(widgets) do if object.kind=="FontString" and object.text=="按钮" then tabs=tabs+1 end end
    local editors=WoWTools.buttonStyle.editors
    assert(tabs==2 and #editors==2,"Button tab missing from standalone or addon settings")
    assert(editors[1].preview.parent.height==WoWTools.buttonStyle.settingsHeight,"Core layout collapsed the button settings page")
    print("PASS: "..flavor.." button materials/RGBA, shared media, legacy/three-slice/late buttons, original click behavior, preview, picker accept/cancel, persistence, restoration and protected retry. Mock UI only.")
end
