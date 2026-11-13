local root = TEST_ROOT or "."
for _, flavor in ipairs({"titan", "forerver"}) do
    local frames, widgets, named, timers = {}, {}, {}, {}
    local combat, scans, callback, media = false, 0, nil, nil
    local writes = {texture=0, anchors=0, font=0}
    local physicalHeight = 768
    function GetPhysicalScreenSize() return 1024,physicalHeight end
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
            if event=="OnMouseDown" then self.buttonState="PUSHED" end
            if event=="OnMouseUp" then self.buttonState="NORMAL" end
            if event=="OnEnter" then self.mouseOver=true end
            if event=="OnLeave" then self.mouseOver=false end
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
        function object:CreateMaskTexture() return widget("MaskTexture",nil,self) end
        function object:AddMaskTexture(mask)
            if self.reject and combat then error("fixture protected mask") end
            self.masks=self.masks or {}
            for _,existing in ipairs(self.masks) do if existing==mask then return end end
            self.masks[#self.masks+1]=mask
        end
        function object:RemoveMaskTexture(mask)
            if self.reject and combat then error("fixture protected mask restoration") end
            for index=#(self.masks or {}),1,-1 do
                if self.masks[index]==mask then table.remove(self.masks,index) end
            end
        end
        function object:SetTextureSliceMargins(...) self.sliceMargins={...} end
        function object:GetTextureSliceMargins() return unpack(self.sliceMargins or {}) end
        function object:ClearTextureSlice() self.sliceMargins=nil end
        function object:SetAllPoints(target) self.allPoints=target end
        function object:CreateFontString() return widget("FontString",nil,self) end
        function object:IsObjectType(value) return self.kind==value end
        function object:IsForbidden() return self.forbidden==true end
        function object:SetSize(w,h) self.width,self.height=w,h end
        function object:GetWidth() return self.width or 144 end
        function object:GetHeight() return self.height or 20 end
        function object:GetEffectiveScale() return (self.scale or 1)*(self.parent and self.parent:GetEffectiveScale() or 1) end
        function object:GetRect()
            if self.pendingRect then return nil end
            if self.rect then return unpack(self.rect) end
            local scale=self:GetEffectiveScale()
            if self.kind=="Texture" or self.kind=="MaskTexture" then
                local x,y,w,h=self.parent:GetRect()
                if not x then return nil end
                local ratio=self.parent:GetEffectiveScale()/scale
                return x*ratio,y*ratio,w*ratio,h*ratio
            end
            return 100,200,self:GetWidth(),self:GetHeight()
        end
        function object:GetTexCoord()
            local coord=self.texcoord or {0,1,0,1}
            return coord[1],coord[3],coord[1],coord[4],coord[2],coord[3],coord[2],coord[4]
        end
        function object:SetTexCoord(...) self.texcoord={...} end
        function object:GetChildren()
            local children = {}
            for _, frame in ipairs(frames) do
                if frame.parent == self then children[#children+1] = frame end
            end
            return unpack(children)
        end
        function object:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel()+1 or 0) end
        function object:SetFrameLevel(level) self.level=level end
        function object:SetScale(scale) self.scale=scale end
        function object:ClearAllPoints()
            writes.anchors=writes.anchors+1
            self.points={};self.allPoints=nil
        end
        function object:GetButtonState() return self.buttonState or "NORMAL" end
        function object:SetButtonState(state) self.buttonState=state end
        function object:IsMouseOver() return self.mouseOver end
        function object:LockHighlight() self.highlightLocked=true end
        function object:UnlockHighlight() self.highlightLocked=false end
        function object:GetStringHeight() return 20 end
        function object:GetFont() return "mock-font",12,"" end
        function object:SetFont(path,size,flags)
            writes.font=writes.font+1
            self.font={path,size,flags}
        end
        function object:SetTextColor(...) self.textColor={...} end
        function object:SetHeight(h) self.height=h end
        function object:SetPoint(...)
            self.point={...}
            self.points=self.points or {}
            self.points[self.point[1]]=self.point
        end
        function object:SetColorTexture(...) self.color={...} end
        function object:SetVertexColor(...) self.vertex={...} end
        function object:SetBlendMode(value) self.blend=value end
        function object:GetBlendMode() return self.blend or "BLEND" end
        function object:GetTexture() return self.path end
        function object:GetAtlas() return self.atlas end
        function object:SetTexture(path,horizontal,vertical,filter)
            writes.texture=writes.texture+1
            self.path=path;self.atlas=nil;self.wrap={horizontal,vertical};self.filter=filter
        end
        function object:SetAtlas(atlas) self.atlas=atlas;self.path=9000 end
        function object:SetAlpha(alpha)
            if self.reject and combat then error("fixture protected alpha") end
            self.alpha=alpha
        end
        function object:GetAlpha() return self.alpha end
        function object:SetText(text)
            self.text=text
            if self.scripts.OnTextChanged then self:Run("OnTextChanged") end
        end
        function object:GetText() return self.text end
        function object:SetChecked(value) self.checked=value end
        function object:GetChecked() return self.checked end
        function object:EnableMouse(value) self.mouseEnabled=value end
        function object:Show()
            local changed=not self.shown;self.shown=true
            if changed then self:Run("OnShow") end
        end
        function object:Hide()
            local changed=self.shown;self.shown=false
            if changed then self:Run("OnHide") end
        end
        function object:IsShown() return self.shown end
        function object:Disable() self.enabled=false;self.buttonState="DISABLED";self:Run("OnDisable") end
        function object:Enable() self.enabled=true;self.buttonState="NORMAL";self:Run("OnEnable") end
        function object:SetEnabled(value) if value then self:Enable() else self:Disable() end end
        function object:IsEnabled() return self.enabled end
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
        if name then named[name]=object;_G[name]=object end
        return object
    end
    function CreateFrame(kind,name,parent,template)
        if type(parent)=="string" then parent=_G[parent] end
        local frame=widget(kind,name,parent)
        frames[#frames+1]=frame
        if template=="UIPanelButtonTemplate" then
            for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
                local texture=frame:CreateTexture()
                texture:SetTexture(state=="Normal" and 4200 or "native-"..state)
                texture:SetTexCoord(0,.625,0,.6875)
                frame[state.."Texture"]=texture
            end
        end
        if template and template:find("UIPanelCloseButton",1,true) then
            local size=flavor=="forerver" and 24 or 32
            frame:SetSize(size,size)
            local atlases={Normal="RedButton-Exit",Pushed="RedButton-exit-pressed",
                Highlight="RedButton-Highlight",Disabled="RedButton-Exit-Disabled"}
            for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
                local texture=frame:CreateTexture()
                if flavor=="forerver" then texture:SetAtlas(atlases[state])
                else texture:SetTexture(state=="Normal" and 4300 or "close-native-"..state) end
                frame[state.."Texture"]=texture
            end
            if template~="UIPanelCloseButtonNoScripts" then
                frame:SetScript("OnClick",function(self) self.parent:Hide() end)
            end
        end
        if template=="MinimalTabTemplate" then frame.Text=widget("FontString",nil,frame) end
        if template=="BasicFrameTemplateWithInset" then frame.TitleText=widget("FontString",nil,frame) end
        if template=="PortraitFrameTemplate" then
            -- XML children are instantiated by the engine, bypassing the Lua CreateFrame hook.
            local close=widget("Button",nil,frame)
            frames[#frames+1]=close
            local texture=close:CreateTexture()
            if flavor=="forerver" then texture:SetAtlas("RedButton-Exit") else texture:SetTexture(4300) end
            close:SetNormalTexture(texture)
            close:SetScript("OnClick",function(self) self.parent:Hide() end)
            frame.CloseButton=close
        end
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
    function CreateRadioButtonGroup()
        return {buttons={},AddButton=function(self,button) self.buttons[#self.buttons+1]=button end,
            SelectAtIndex=function(self,index) self.selected=index end}
    end
    local addon=root.."/addon/"..flavor.."/wow_tools/"
    local function ReadShape(name)
        local file=assert(io.open(addon.."Media/"..name..".tga","rb"))
        local data=file:read("*a");file:close()
        assert(#data==4114 and data:byte(3)==2 and data:byte(17)==32 and data:byte(18)==40,"Invalid RGBA TGA")
        assert(data:byte(13)==32 and data:byte(14)==0 and data:byte(15)==32 and data:byte(16)==0,"Invalid mask dimensions")
        return function(x,y) return data:byte(18+(y*32+x)*4+4) end
    end
    local cutout=ReadShape("ButtonNativeCutout")
    for y=0,31 do
        for x=0,31 do assert(cutout(x,y)==0,"Native interior cutout contains opaque pixels") end
    end
    local rounded,thin=ReadShape("ButtonRoundMask"),ReadShape("ButtonRoundBorder")
    assert(rounded(0,0)<32 and rounded(16,16)==255 and thin(16,16)==0 and thin(16,0)==255)
    for y=0,31 do
        for x=0,31 do
            assert(rounded(x,y)+2>=thin(x,y),"Material mask leaves an uncovered border edge")
            if x>=4 and x<28 or y>=4 and y<28 then
                assert(rounded(x,y)==255,"Material contains a gap at the border's inner edge")
            end
        end
    end
    local function SliceCoordinate(position,extent)
        if position<4 then return position end
        if position>=extent-4 then return 32-extent+position end
        return 4+(position-4)*24/(extent-8)
    end
    for _,size in ipairs({{78,18},{240,28},{420,40},{20,20}}) do
        for y=4,size[2]-5 do
            for x=4,size[1]-5 do
                assert(rounded(math.floor(SliceCoordinate(x+.5,size[1])),math.floor(SliceCoordinate(y+.5,size[2])))==255,
                    "Nine-slice stretching creates a material/border seam")
            end
        end
    end
    dofile(addon.."ButtonStyle.lua")
    dofile(addon.."ButtonStyle.Settings.lua")
    local style=WoWTools.buttonStyle
    local function event(name,addonName)
        for _,frame in ipairs(frames) do if frame.events[name] then frame:Run("OnEvent",name,addonName) end end
    end
    local function flush()
        local pending=timers;timers={}
        for _,fn in ipairs(pending) do fn() end
    end
    local function Fill(button)
        for index=#frames,1,-1 do
            local frame=frames[index]
            if frame.kind=="Button" and frame.parent==button and frame.mouseEnabled==false then return frame end
        end
    end
    local function Glyph(button)
        for index=#widgets,1,-1 do
            local object=widgets[index]
            if object.kind=="FontString" and object.text=="×" and object.parent.parent==button then return object end
        end
    end
    local function Border(button)
        local fill=Fill(button)
        for index=#fill.textures,1,-1 do
            local texture=fill.textures[index]
            if type(texture.path)=="string" and texture.path:find("ButtonRoundBorder",1,true) then return texture end
        end
    end
    local function CheckSkin(button,mode)
        local fill=assert(Fill(button),"Missing material child")
        assert(fill.shown and fill.level<button:GetFrameLevel(),"Material hides native text")
        assert(not fill.scripts.OnClick and fill.mouseEnabled==false,"Material child intercepts native input")
        local mask=fill:GetNormalTexture().masks[1]
        local border=Border(button)
        for _,state in ipairs(style.states) do
            local texture=fill[state.getter](fill)
            assert(#texture.masks==1 and texture.masks[1]==mask and not texture.sliceMargins,"A material state bypasses the mask")
        end
        if mode=="native" then
            assert(not border.shown and mask.path=="Interface\\Buttons\\WHITE8X8" and not mask.sliceMargins,"Native material still depends on sliced mask geometry")
            local normal=button:GetNormalTexture() or button.Left
            assert(normal.alpha>0 and #(normal.masks or {})==1,"Original border artwork was hidden or lacked its inner cutout")
            local nativeMask=normal.masks[1]
            assert(nativeMask.path:find("ButtonNativeCutout",1,true) and nativeMask.wrap[1]=="CLAMPTOWHITE" and nativeMask.wrap[2]=="CLAMPTOWHITE" and nativeMask.filter=="NEAREST","Original artwork received the wrong cutout sampler")
            assert(mask.allPoints==fill and nativeMask.allPoints==fill,"Native border hole and material bounds no longer align")
            assert(not fill.allPoints and fill.points.TOPLEFT[4]<fill.points.BOTTOMRIGHT[4],"Native material has inverted horizontal bounds")
            assert(fill.points.TOPLEFT[5]>fill.points.BOTTOMRIGHT[5],"Native material has inverted vertical bounds")
        else
            assert(mask.allPoints==fill and border.allPoints==fill,"Material and border do not share the outer rectangle")
            assert(border.shown==(mode=="thin"),"Wrong custom border visibility")
            local normal=button:GetNormalTexture() or button.Left
            assert(normal.alpha==0,"Native border leaked into a custom border mode")
            assert(fill.points.TOPLEFT[4]<fill.points.BOTTOMRIGHT[4] and fill.scale>0,"Invalid custom surface geometry")
            if mode=="thin" then
                assert(border.parent==fill and mask.parent==fill,"Border and material use different scale spaces")
            end
        end
        return fill,mask,border
    end
    local menu=CreateFrame("Button","GameMenuButtonOptions",UIParent,"UIPanelButtonTemplate")
    menu:SetSize(144,22)
    local original,originalHighlight=menu:GetNormalTexture(),menu:GetHighlightTexture()
    local clicked=0
    menu:SetScript("OnClick",function() clicked=clicked+1 end)
    local click=menu.scripts.OnClick
    local map=CreateFrame("Frame","WorldMapFrame",UIParent)
    local close=CreateFrame("Button","WorldMapFrameCloseButton",map,"UIPanelCloseButton")
    local closeOriginal,closeClick=close:GetNormalTexture(),close.scripts.OnClick
    close.UpdateButton=function(self)
        self:GetNormalTexture():SetAtlas("RedButton-Exit")
        self:GetNormalTexture():SetTextureSliceMargins(8,8,8,8)
    end
    local sliced=CreateFrame("Button",nil,UIParent)
    sliced.atlasName="128-RedButton"
    for _,key in ipairs({"Left","Center","Right"}) do
        sliced[key]=sliced:CreateTexture();sliced[key]:SetAtlas("128-RedButton-"..key)
    end
    sliced.Left:SetAlpha(.7)
    sliced.UpdateButton=function(self) self.Left:SetAtlas("128-RedButton-Left-Pressed");self.Left:SetAlpha(1) end
    local legacy=CreateFrame("Button",nil,UIParent)
    for _,key in ipairs({"Left","Middle","Right"}) do legacy[key]=legacy:CreateTexture();legacy[key]:SetTexture(4200) end
    legacy.Left:SetTexCoord(0,.09375,0,.6875);legacy.Left.rect={100,200,12,20}
    legacy.Middle:SetTexCoord(.09375,.53125,0,.6875);legacy.Middle.rect={112,200,120,20}
    legacy.Right:SetTexCoord(.53125,.625,0,.6875);legacy.Right.rect={232,200,12,20}
    local variants={}
    for _,path in ipairs({"Interface\\Buttons\\UI-Panel-MinimizeButton-Up","128-RedButton-Exit","common-button-close"}) do
        local button=CreateFrame("Button",nil,UIParent)
        local texture=button:CreateTexture()
        if path:find("Interface",1,true) then texture:SetTexture(path) else texture:SetAtlas(path) end
        button:SetNormalTexture(texture);variants[#variants+1]=button
    end
    local icon=CreateFrame("Button",nil,UIParent)
    icon:SetNormalTexture(icon:CreateTexture());icon:GetNormalTexture():SetTexture(7777)
    local refresh=CreateFrame("Button",nil,UIParent)
    refresh.buttonArtKit="128-RedButton-Refresh"
    refresh:SetNormalTexture(refresh:CreateTexture());refresh:GetNormalTexture():SetAtlas("128-RedButton-Refresh")
    local forbidden=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate");forbidden.forbidden=true
    local restricted=CreateFrame("Button",nil,UIParent)
    restricted:SetNormalTexture(restricted:CreateTexture());restricted:GetNormalTexture():SetTexture(secret)
    local masked=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    local foreignMask=masked:CreateMaskTexture()
    masked:GetNormalTexture():AddMaskTexture(foreignMask)
    local function SetArtwork(button,rect)
        for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
            button[state.."Texture"].rect=rect
        end
    end
    local asymmetric=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    asymmetric:SetSize(144,30)
    SetArtwork(asymmetric,{104,207,132,22})
    local scaled=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    scaled:SetSize(144,30)
    for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
        scaled[state.."Texture"]:SetScale(2)
    end
    SetArtwork(scaled,{52,103.5,66,11})
    local overflow=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    SetArtwork(overflow,{90,192,164,36})
    local deferred=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    deferred.pendingRect=true
    local unreadable=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    SetArtwork(unreadable,{secret,200,144,22})
    local atlasClose=CreateFrame("Button",nil,UIParent,"UIPanelCloseButtonNoScripts")
    atlasClose:SetSize(32,32)
    SetArtwork(atlasClose,{104,204,24,24})
    for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
        atlasClose[state.."Texture"]:SetAtlas("common-button-close-test")
        atlasClose[state.."Texture"]:SetTexCoord(.25,.5,.125,.375)
    end
    local atlasLocal=CreateFrame("Button",nil,UIParent,"UIPanelCloseButtonNoScripts")
    atlasLocal:SetSize(32,32)
    SetArtwork(atlasLocal,{104,204,24,24})
    for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
        atlasLocal[state.."Texture"]:SetAtlas("common-button-close-test")
        atlasLocal[state.."Texture"]:SetTexCoord(0,1,0,1)
    end
    local atlasSliced=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    atlasSliced:SetSize(300,32)
    for _,state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
        atlasSliced[state.."Texture"]:SetAtlas("common-button-close-sliced-test")
        atlasSliced[state.."Texture"]:SetTexCoord(0,1,0,1)
        atlasSliced[state.."Texture"]:SetTextureSliceMargins(8,8,8,8)
    end
    C_Texture={GetAtlasInfo=function(name)
        if name=="common-button-close-test" then
            return {width=24,height=24,leftTexCoord=.25,rightTexCoord=.5,topTexCoord=.125,bottomTexCoord=.375}
        elseif name=="common-button-close-sliced-test" then
            return {width=32,height=32,leftTexCoord=0,rightTexCoord=1,topTexCoord=0,bottomTexCoord=1}
        end
    end}
    local nine=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    nine.NineSlice=widget("Frame",nil,nine)
    local edges={}
    for _,rect in ipairs({{98,198,148,4},{98,218,148,4},{98,202,4,16},{242,202,4,16},{102,202,140,16}}) do
        local texture=nine.NineSlice:CreateTexture();texture.rect=rect;edges[#edges+1]=texture
    end
    nine.NineSlice.Center=edges[5]
    function nine.NineSlice:GetRegions() return unpack(edges) end
    local old=style.GetConfig();old.border=nil;wowDetectorDB.buttonStyle=old
    event("ADDON_LOADED","wow_tools")
    assert(style.GetConfig().border.style=="native" and wowDetectorDB.buttonStyle.border==nil,"Old settings were rewritten during migration")
    assert(menu:GetNormalTexture()==original and original.alpha==1 and not original.masks and scans==0)
    local parent=CreateFrame("Frame",nil,UIParent)
    style.BuildSettings(parent)
    local editor=style.editors[1]
    assert(parent.height==600 and editor.borderGroup.selected==1 and not editor.borderColor.enabled)
    assert(Glyph(editor.closePreview).shown and not Fill(menu),"Default-off preview modified real buttons")
    editor.closePreview:Run("OnClick");assert(parent.shown,"Close preview hides settings")
    local value=style.GetConfig();value.enabled=true;value.colors.normal={.2,.4,.7,.6};value.colors.highlight={.6,.2,.8,1}
    assert(style.Save(value))
    local fill=CheckSkin(menu,"native")
    CheckSkin(close,"native");CheckSkin(sliced,"native");CheckSkin(legacy,"native")
    assert(fill.points.TOPLEFT[4]==7,"Legacy menu material did not follow its cropped texture geometry")
    local closeInset=flavor=="titan" and 8 or 3
    assert(Fill(close).points.TOPLEFT[4]==closeInset,"Close-button material did not shrink inside its native face")
    local af=CheckSkin(asymmetric,"native")
    assert(af.points.TOPLEFT[4]==11 and af.points.TOPLEFT[5]==25
        and af.points.BOTTOMRIGHT[4]==129 and af.points.BOTTOMRIGHT[5]==11,
        "Texture position/size differences were replaced with symmetric button insets")
    local sf=CheckSkin(scaled,"native")
    for _,point in ipairs({"TOPLEFT","BOTTOMRIGHT"}) do
        assert(sf.points[point][4]==af.points[point][4] and sf.points[point][5]==af.points[point][5],
            "Texture coordinates were compared across different effective scales")
    end
    local nf=CheckSkin(nine,"native")
    assert(nf.points.TOPLEFT[4]==2 and nf.points.TOPLEFT[5]==18
        and nf.points.BOTTOMRIGHT[4]==142 and nf.points.BOTTOMRIGHT[5]==2,"NineSlice center did not define the native interior")
    assert(not Fill(deferred).shown and deferred:GetNormalTexture().alpha==1,"Unresolved layout hid native artwork")
    assert(not Fill(unreadable).shown and unreadable:GetNormalTexture().alpha==1,"Restricted coordinates changed native appearance")
    deferred.pendingRect=false;deferred:Run("OnShow");CheckSkin(deferred,"native")
    local atlasFill=CheckSkin(atlasClose,"native")
    assert(atlasFill.points.TOPLEFT[4]==7 and atlasFill.points.TOPLEFT[5]==25
        and atlasFill.points.BOTTOMRIGHT[4]==25 and atlasFill.points.BOTTOMRIGHT[5]==7,
        "Atlas-sheet UV coordinates were treated as local image coordinates")
    local localFill=CheckSkin(atlasLocal,"native")
    for _,point in ipairs({"TOPLEFT","BOTTOMRIGHT"}) do
        assert(localFill.points[point][4]==atlasFill.points[point][4]
            and localFill.points[point][5]==atlasFill.points[point][5],"Native atlas-local coordinates were transformed as sheet coordinates")
    end
    atlasLocal:GetNormalTexture():SetTexCoord(0,.5,0,1)
    atlasLocal:Run("OnShow")
    assert(localFill.points.TOPLEFT[4]==10 and localFill.points.BOTTOMRIGHT[4]==28,
        "Native atlas-local partial cropping was lost")
    atlasLocal:GetNormalTexture():SetTexCoord(0,1,0,1)
    atlasLocal:Run("OnShow")
    local slicedFill=CheckSkin(atlasSliced,"native")
    assert(slicedFill.points.TOPLEFT[4]==4 and slicedFill.points.BOTTOMRIGHT[4]==296,
        "Texture nine-slice margins were stretched across the button width")
    assert(menu:GetNormalTexture()==original and close:GetNormalTexture()==closeOriginal and menu.width==144 and menu.height==22,"Styling replaced native bindings or resized the button")
    assert(fill:GetNormalTexture().path=="Interface\\Buttons\\WHITE8X8" and fill:GetNormalTexture().vertex[4]==.6)
    assert(original.alpha==1 and sliced.Left.alpha==.7 and not sliced:GetNormalTexture(),"Native edge textures were replaced")
    assert(masked:GetNormalTexture().masks[1]==foreignMask and #masked:GetNormalTexture().masks==2,"An existing mask was overwritten")
    editor.preview:Run("OnEnter");assert(Fill(editor.preview).highlightLocked)
    editor.preview:Run("OnMouseDown");assert(Fill(editor.preview).buttonState=="PUSHED")
    editor.preview:Run("OnMouseUp");editor.preview:Run("OnLeave")
    for _,button in ipairs(variants) do CheckSkin(button,"native");assert(Glyph(button).shown) end
    for _,state in ipairs(style.states) do
        local texture=Fill(close)[state.getter](Fill(close))
        for index=1,4 do assert(texture.vertex[index]==value.colors[state.key][index],"Material RGBA changed") end
    end
    menu:Run("OnEnter");assert(fill.highlightLocked,"Hover material did not follow native button")
    menu:Run("OnMouseDown");assert(fill.buttonState=="PUSHED")
    menu:Run("OnMouseUp");menu:Run("OnLeave");assert(fill.buttonState=="NORMAL" and not fill.highlightLocked)
    menu:LockHighlight();assert(fill.highlightLocked);menu:UnlockHighlight();assert(not fill.highlightLocked)
    menu:SetButtonState("PUSHED");assert(fill.buttonState=="PUSHED");menu:SetButtonState("NORMAL")
    close:Disable();assert(not Fill(close).enabled and Glyph(close).alpha==.4)
    close:Enable();assert(Fill(close).enabled and Glyph(close).alpha==1)
    local visibleHeight=flavor=="titan" and 16 or 18
    assert(math.abs(Glyph(close).font[2]-visibleHeight*.7)<.001,"Close glyph did not grow to the adjusted size")
    for _,size in ipairs({{78,22},{240,28},{420,40}}) do
        menu:SetSize(unpack(size));menu:Run("OnSizeChanged");CheckSkin(menu,"native")
        assert(fill.points.TOPLEFT[4]==math.floor(size[1]*4/80+.5),"Native fill bounds did not follow the texture's horizontal stretch")
        assert(menu.width==size[1] and menu.height==size[2],"Appearance resized the native button")
    end
    menu:SetSize(4,6);menu:Run("OnSizeChanged");CheckSkin(menu,"native")
    assert(fill.points.TOPLEFT[4]<fill.points.BOTTOMRIGHT[4] and fill.points.TOPLEFT[5]>fill.points.BOTTOMRIGHT[5],"Small native fill has inverted bounds")
    menu:SetSize(144,22);menu:Run("OnSizeChanged")
    close:UpdateButton();sliced:UpdateButton()
    assert(close:GetNormalTexture()==closeOriginal and closeOriginal.sliceMargins[1]==8 and sliced.Left.alpha==.7,"Native state artwork or slice metadata was overwritten")
    local nativePushed=menu:CreateTexture();nativePushed:SetTexture("native-new-pushed")
    nativePushed:SetTexCoord(0,.625,0,.6875)
    menu:SetPushedTexture(nativePushed);style.Apply(false)
    assert(menu:GetPushedTexture()==nativePushed and #nativePushed.masks==1,"A new native state texture was missed")
    menu:Run("OnClick");close:Run("OnClick")
    assert(clicked==1 and menu.scripts.OnClick==click and not map.shown and close.scripts.OnClick==closeClick)
    map:Show()
    assert(not Fill(icon) and not Fill(refresh) and not Fill(forbidden) and not Fill(restricted),"Unrelated or restricted icons were styled")
    local late=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    local lateClose=CreateFrame("Button",nil,UIParent,"UIPanelCloseButtonDefaultAnchors")
    local before=scans;assert(#timers==1);flush()
    assert(scans==before,"Parented controls triggered a global scan");CheckSkin(late,"native");CheckSkin(lateClose,"native")
    local latePanel=CreateFrame("Frame",nil,UIParent,"PortraitFrameTemplate")
    flush();CheckSkin(latePanel.CloseButton,"native")
    local otherParent=CreateFrame("Frame","ButtonStyleOtherParent",UIParent)
    local reparented=CreateFrame("Frame",nil,"ButtonStyleOtherParent","PortraitFrameTemplate")
    reparented.parent=map
    flush();CheckSkin(reparented.CloseButton,"native")
    before=scans
    local textureWrites,anchorWrites,fontWrites=writes.texture,writes.anchors,writes.font
    for i=1,100 do
        menu:Run("OnEnter");menu:Run("OnMouseDown");menu:Run("OnMouseUp");menu:Run("OnLeave")
        close:Hide();close:Show();close:UpdateButton()
    end
    assert(writes.texture==textureWrites and writes.anchors==anchorWrites and writes.font==fontWrites,
        "Repeated button events rewrote materials, geometry or fonts")
    local pushed=style.GetConfig()
    menu:SetButtonState("PUSHED");style.Save(pushed)
    assert(fill.buttonState=="PUSHED","Saving appearance lost the current pressed state")
    menu:SetButtonState("NORMAL")
    local namedPanel=CreateFrame("Frame","ButtonStyleLatePanel",nil,"PortraitFrameTemplate")
    flush();CheckSkin(namedPanel.CloseButton,"native")
    local anonymousPanel=CreateFrame("Frame",nil,nil,"PortraitFrameTemplate")
    flush();CheckSkin(anonymousPanel.CloseButton,"native")
    assert(scans==before+1,"Anonymous top-level template fallback was lost")
    local otherFill=Fill(close)
    textureWrites,anchorWrites,fontWrites=writes.texture,writes.anchors,writes.font
    local unrelated=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    flush()
    assert(scans==before+1 and not Fill(unrelated) and Fill(close)==otherFill)
    assert(writes.texture==textureWrites and writes.anchors==anchorWrites and writes.font==fontWrites,
        "An unrelated popup repainted existing buttons or settings previews")
    before=scans
    event("PLAYER_ENTERING_WORLD");flush()
    event("PLAYER_ENTERING_WORLD");flush()
    assert(scans==before+1,"World entry discovery remained registered after loading")
    textureWrites,anchorWrites,fontWrites=writes.texture,writes.anchors,writes.font
    event("ADDON_LOADED","UnrelatedAddon");event("ADDON_LOADED","AnotherAddon");flush()
    assert(scans==before+2 and writes.texture==textureWrites and writes.anchors==anchorWrites
        and writes.font==fontWrites,"Addon loading repainted existing buttons or bypassed scan coalescing")
    value=style.GetConfig();value.material="lsm:Smooth";assert(style.Save(value))
    assert(fill:GetNormalTexture().path=="Interface\\Buttons\\WHITE8X8" and style.lastStatus:find("暂用纯色",1,true))
    media={Smooth="mock-smooth",Zeta="mock-zeta",Alpha="mock-alpha"}
    local library={HashTable=function() return media end,RegisterCallback=function(_,_,fn) callback=fn end}
    LibStub={GetLibrary=function() return library end}
    event("ADDON_LOADED","Plater")
    assert(fill:GetNormalTexture().path=="mock-smooth" and callback)
    media.Smooth="mock-new-smooth";callback("LibSharedMedia_Registered","statusbar","Smooth")
    assert(fill:GetNormalTexture().path=="mock-new-smooth");CheckSkin(close,"native")
    local materials=style.GetMaterials();assert(materials[3].label=="Alpha" and materials[5].label=="Zeta")
    local saved=wowDetectorDB.buttonStyle
    value=style.GetConfig();value.colors.normal[1]=2;assert(not style.Save(value) and wowDetectorDB.buttonStyle==saved)
    value=style.GetConfig();value.border.style="bad";assert(not style.Save(value))
    value=style.GetConfig();value.border.color[4]=-1;assert(not style.Save(value))
    value=style.GetConfig();value.material="Interface\\arbitrary";assert(not style.Save(value))
    editor.material:Run("OnClick")
    local popup=named.WoWToolsButtonMaterialMenu
    assert(popup.shown and popup.rows[3].entry.label=="Alpha")
    popup.search:SetText("Zeta");assert(popup.rows[1].entry.label=="Zeta" and not popup.rows[2].shown)
    popup.rows[1]:Run("OnClick");assert(wowDetectorDB.buttonStyle.material=="lsm:Zeta" and not popup.shown)
    editor.borderOptions.thin:Run("OnClick")
    assert(style.GetConfig().border.style=="thin" and editor.borderGroup.selected==2 and editor.borderColor.enabled)
    CheckSkin(menu,"thin");CheckSkin(close,"thin");CheckSkin(legacy,"thin")
    local of=CheckSkin(overflow,"thin")
    assert(of.points.TOPLEFT[4]*of.scale<0 and of.points.BOTTOMRIGHT[4]*of.scale>overflow:GetWidth(),
        "Texture artwork extending outside the hit rectangle was clipped")
    CheckSkin(asymmetric,"thin");CheckSkin(scaled,"thin");CheckSkin(nine,"thin")
    assert(Fill(nine).points.TOPLEFT[4]*Fill(nine).scale==-2,"NineSlice outer union did not include its edges")
    local oldThickness=fill.scale
    menu:SetSize(288,44);menu:Run("OnSizeChanged")
    assert(fill.scale==2*oldThickness,"Border thickness did not follow the rendered artwork height")
    menu:SetSize(500,44);menu:Run("OnSizeChanged")
    assert(fill.scale==2*oldThickness,"Horizontal texture stretching changed border thickness")
    menu:SetSize(144,22);menu:Run("OnSizeChanged")
    physicalHeight=1080;menu:SetScale(.7)
    local pixel=768/1080/.7
    assert(math.abs(fill.scale/pixel-math.floor(fill.scale/pixel+.5))<.00001,"Border thickness was not aligned to physical pixels")
    for _,point in ipairs({"TOPLEFT","BOTTOMRIGHT"}) do
        for index=4,5 do
            local origin=index==4 and 100 or 200
            local screen=(origin+fill.points[point][index]*fill.scale)/pixel
            assert(math.abs(screen-math.floor(screen+.5))<.00001,"Shared outer edge was not snapped in screen space")
        end
    end
    physicalHeight=768;menu:SetScale(1)
    local beforeWidth=fill.points.BOTTOMRIGHT[4]*fill.scale-fill.points.TOPLEFT[4]*fill.scale
    nativePushed.rect={96,198,152,26}
    menu:Run("OnShow")
    local afterWidth=fill.points.BOTTOMRIGHT[4]*fill.scale-fill.points.TOPLEFT[4]*fill.scale
    assert(afterWidth>beforeWidth,"Native state texture geometry changes did not refresh the shared surface")
    nativePushed.rect=nil;menu:Run("OnShow")
    local width,height=menu.width,menu.height
    for _,size in ipairs({{78,22},{240,28},{420,40}}) do
        menu:SetSize(unpack(size));menu:Run("OnSizeChanged");CheckSkin(menu,"thin")
        assert(menu.width==size[1] and menu.height==size[2],"Appearance changed the native hit rectangle")
    end
    menu:SetSize(width,height);menu:Run("OnSizeChanged")
    editor.borderOptions.none:Run("OnClick");CheckSkin(menu,"none");CheckSkin(close,"none")
    assert(not editor.borderColor.enabled)
    editor.borderOptions.native:Run("OnClick");CheckSkin(menu,"native");CheckSkin(close,"native")
    assert(original.alpha==1 and menu:GetNormalTexture()==original)

    ColorPickerFrame=widget("Frame")
    function ColorPickerFrame:SetupColorPickerAndShow(info) self.info=info;self.rgb={info.r,info.g,info.b};self.opacity=info.opacity;self:Show() end
    function ColorPickerFrame:GetColorRGB() return unpack(self.rgb) end
    function ColorPickerFrame:GetColorAlpha() return self.opacity end
    editor.borderOptions.thin:Run("OnClick")
    editor.borderColor:Run("OnClick")
    ColorPickerFrame.rgb={.9,.7,.2};ColorPickerFrame.opacity=.5;ColorPickerFrame.info.swatchFunc()
    assert(style.GetConfig().border.color[1]==.9 and Border(menu).vertex[4]==.5,"Border RGBA did not apply or persist")
    ColorPickerFrame:Hide();ColorPickerFrame.info.cancelFunc()
    assert(style.GetConfig().border.color[1]==.65 and Border(menu).vertex[4]==.8,"Border picker cancel failed")
    editor.borderColor:Run("OnClick")
    ColorPickerFrame.rgb={.8,.6,.3};ColorPickerFrame.opacity=.7;ColorPickerFrame.info.opacityFunc();ColorPickerFrame:Hide()
    close:Disable();assert(math.abs(Border(close).vertex[4]-.7*.4375)<.001);close:Enable()
    editor.swatches.normal:Run("OnClick")
    assert(ColorPickerFrame.info.opacity==.6,"Modern opacity was inverted")
    ColorPickerFrame.rgb={.7,.2,.3};ColorPickerFrame.opacity=.4;ColorPickerFrame.info.swatchFunc()
    assert(wowDetectorDB.buttonStyle.colors.normal[1]==.7 and wowDetectorDB.buttonStyle.colors.normal[4]==.4)
    ColorPickerFrame:Hide();ColorPickerFrame.info.cancelFunc()
    assert(wowDetectorDB.buttonStyle.colors.normal[1]==.2 and wowDetectorDB.buttonStyle.colors.normal[4]==.6,"Cancel did not revert persisted RGBA")
    editor.swatches.normal:Run("OnClick")
    ColorPickerFrame.rgb={.3,.6,.8};ColorPickerFrame.opacity=.9;ColorPickerFrame.info.opacityFunc()
    ColorPickerFrame:Hide()
    editor.swatches.pushed:Run("OnClick")
    assert(wowDetectorDB.buttonStyle.colors.normal[1]==.3,"Opening a new picker reverted an accepted color")
    ColorPickerFrame.rgb={.4,.5,.6};ColorPickerFrame.info.swatchFunc()
    editor.swatches.highlight:Run("OnClick")
    assert(wowDetectorDB.buttonStyle.colors.pushed[1]==.4,"Switching swatches discarded a live saved color")
    local staleCancel=ColorPickerFrame.info.cancelFunc
    style.Reset();staleCancel()
    assert(wowDetectorDB.buttonStyle==nil and wowDetectorDB.untouched=="keep")
    assert(menu:GetNormalTexture()==original and original.alpha==1 and #(original.masks or {})==0 and not fill.shown and not Border(menu).shown,"Reset failed to restore native artwork")
    assert(#masked:GetNormalTexture().masks==1 and masked:GetNormalTexture().masks[1]==foreignMask,"Reset removed another addon's mask")
    assert(menu:GetPushedTexture()==nativePushed and #nativePushed.masks==0,"Reset replaced a new native texture binding")
    assert(sliced.Left.alpha==.7 and not sliced:GetNormalTexture() and originalHighlight:GetBlendMode()=="BLEND")
    assert(not Glyph(close).shown and Glyph(editor.closePreview).shown)
    close:Run("OnClick");assert(not map.shown and close.scripts.OnClick==closeClick);map:Show()
    ColorPickerFrame.SetupColorPickerAndShow=nil
    function ColorPickerFrame:SetColorRGB(r,g,b) self.rgb={r,g,b} end
    OpacitySliderFrame={GetValue=function() return .8 end}
    editor.swatches.normal:Run("OnClick")
    ColorPickerFrame.rgb={.1,.2,.3};ColorPickerFrame.func()
    assert(math.abs(wowDetectorDB.buttonStyle.colors.normal[4]-.2)<.001,"Legacy transparency was not inverted")
    ColorPickerFrame.cancelFunc();ColorPickerFrame:Hide()
    assert(wowDetectorDB.buttonStyle.colors.normal[4]==1)

    local protected=CreateFrame("Button",nil,UIParent,"UIPanelButtonTemplate")
    local protectedOriginal=protected:GetNormalTexture()
    protected:GetPushedTexture().reject=true;combat=true
    value=style.GetConfig();value.enabled=true
    local ok,message=style.Save(value)
    assert(ok and message:find("待重试",1,true),"Partial native masking reported success")
    combat=false;event("PLAYER_REGEN_ENABLED");CheckSkin(protected,"native")
    combat=true;style.Reset();assert(style.lastStatus:find("待恢复",1,true),"Partial unmasking reported success")
    combat=false;event("PLAYER_REGEN_ENABLED")
    assert(protected:GetNormalTexture()==protectedOriginal and #(protectedOriginal.masks or {})==0 and not Fill(protected).shown)
    value=style.GetConfig();value.enabled=true;value.border.style="thin";value.border.color={.2,.5,.8,.6};style.Save(value)
    local persisted=wowDetectorDB.buttonStyle
    local replacementNative=protected:CreateTexture();replacementNative:SetTexture("native-new-pushed")
    protected:SetPushedTexture(replacementNative)
    style.Apply(false);style.Reset()
    assert(protected:GetPushedTexture()==replacementNative,"Reset overwrote a native binding changed by the client")
    wowDetectorDB.buttonStyle=persisted
    for _,frame in ipairs(frames) do frame.events={} end
    dofile(addon.."ButtonStyle.lua");dofile(addon.."ButtonStyle.Settings.lua")
    event("ADDON_LOADED","wow_tools");flush()
    style=WoWTools.buttonStyle
    assert(style.GetConfig().border.style=="thin" and style.GetConfig().border.color[4]==.6,"Reload lost border selection or color")
    CheckSkin(menu,"thin");CheckSkin(close,"thin")
    for _,frame in ipairs(frames) do assert(not frame.scripts.OnUpdate,"Appearance added polling") end
    WoWTools.modules={};SlashCmdList={}
    dofile(addon.."ExperienceText.lua")
    dofile(addon.."DisplayFonts.lua")
    dofile(addon.."LuaGC.lua")
    dofile(addon.."inner_graphic_config/Core.lua")
    do
        local host=CreateFrame("Frame",nil,UIParent)
        host:Hide()
        WoWTools.modules.inner_graphic_config.BuildSettings(host)
        WoWTools.settings={Open=function(group)
            assert(group=="inner_graphic_config", "Graphics shortcut lost its unified settings group")
            host:Show()
        end}
    end
    WoWTools.modules.inner_graphic_config.Show()
    local tabs=0
    for _,object in ipairs(widgets) do if object.kind=="FontString" and object.text=="按钮" then tabs=tabs+1 end end
    local expected=1
    assert(tabs==expected and #style.editors==expected and style.editors[1].preview.parent.height==600,"Settings entry or scrolling height is wrong")
    print("PASS: "..flavor.." measured texture/UV/atlas bounds, asymmetric offsets, mixed scales, overflow/NineSlice, pixel-aligned proportional borders, continuous rounded masks, deferred/restricted layout, cached updates, discovery, LSM, persistence and restoration. Mock UI only.")
end
