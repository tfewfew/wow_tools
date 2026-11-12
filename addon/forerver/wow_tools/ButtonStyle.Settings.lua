-- Forever 16001 material list, RGBA swatches and live button preview.
local module = WoWTools.buttonStyle
module.settingsHeight = 600
local popup, pickerSession
local pickerGeneration=0
local hookedPickers=setmetatable({}, {__mode="k"})
local function Button(parent,text,width,height)
    local button=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    button:SetSize(width,height)
    button:SetText(text)
    return button
end
local function Label(parent,text,x,y)
    local label=parent:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    label:SetPoint("TOPLEFT",x,y)
    label:SetText(text)
    return label
end
local function ColorTarget(value,key)
    if key=="border" then return value.border,"color" end
    return value.colors,key
end
function module.RefreshSettings()
    local value=module.GetConfig()
    local path,name,missing=module.ResolveMaterial(value.material)
    for _,editor in ipairs(module.editors) do
        editor.enabled:SetChecked(value.enabled)
        editor.material:SetText(name..(missing and "（未加载）" or "").."  ▾")
        editor.sample:SetTexture(path)
        for _,state in ipairs(module.states) do
            editor.swatches[state.key].color:SetColorTexture(unpack(value.colors[state.key]))
        end
        for index,style in ipairs(module.borderStyles) do
            if style.key==value.border.style then editor.borderGroup:SelectAtIndex(index) end
        end
        editor.borderColor.color:SetColorTexture(unpack(value.border.color))
        editor.borderColor:SetEnabled(value.border.style=="thin")
        module.ApplyPreview(editor.preview)
        module.ApplyPreview(editor.disabled)
        module.ApplyPreview(editor.closePreview)
        editor.status:SetText(module.lastStatus or "勾选启用后立即应用并保存。")
    end
end
function module.CloseColorPicker()
    pickerGeneration=pickerGeneration+1
    local session=pickerSession
    pickerSession=nil
    if session and ColorPickerFrame then ColorPickerFrame:Hide() end
end
local function OpenPicker(editor,key)
    module.CloseColorPicker()
    if not ColorPickerFrame then
        local load=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        if load then pcall(load,"Blizzard_ColorPicker") end
    end
    local picker=ColorPickerFrame
    if not picker then editor.status:SetText("颜色选择器尚未加载。");return end
    picker:Hide()
    local colors,field=ColorTarget(module.GetConfig(),key)
    local session={editor=editor,key=key,before=colors[field],generation=pickerGeneration}
    pickerSession=session
    if not hookedPickers[picker] and type(picker.HookScript)=="function" then
        hookedPickers[picker]=true
        picker:HookScript("OnHide",function() pickerSession=nil end)
    end
    local modern=type(picker.SetupColorPickerAndShow)=="function"
    local function Changed()
        if pickerSession~=session then return end
        local r,g,b=picker:GetColorRGB()
        local alpha
        if modern then alpha=picker:GetColorAlpha()
        elseif OpacitySliderFrame then alpha=1-OpacitySliderFrame:GetValue()
        else alpha=session.before[4] end
        local value=module.GetConfig()
        local colors,field=ColorTarget(value,key)
        colors[field]={r,g,b,alpha}
        local ok,message=module.Save(value)
        if not ok then editor.status:SetText(message) end
    end
    local function Cancel()
        if pickerGeneration~=session.generation then return end
        pickerGeneration=pickerGeneration+1
        pickerSession=nil
        local value=module.GetConfig()
        local colors,field=ColorTarget(value,key)
        colors[field]={unpack(session.before)}
        module.Save(value)
    end
    local color=session.before
    if modern then
        picker:SetupColorPickerAndShow({r=color[1],g=color[2],b=color[3],opacity=color[4],
            hasOpacity=true,swatchFunc=Changed,opacityFunc=Changed,cancelFunc=Cancel})
    else
        picker.hasOpacity=true
        picker.opacity=1-color[4]
        picker.func=Changed
        picker.opacityFunc=Changed
        picker.cancelFunc=Cancel
        picker.previousValues={unpack(color)}
        picker:SetColorRGB(color[1],color[2],color[3])
        picker:Show()
    end
end
local function Swatch(parent,editor,key,y)
    local swatch=Button(parent,"选择颜色",144,28)
    swatch:SetPoint("TOPLEFT",82,y)
    for tile=0,7 do
        local texture=swatch:CreateTexture(nil,"BORDER")
        local tone=tile%2==math.floor(tile/4)%2 and .25 or .75
        texture:SetColorTexture(tone,tone,tone,1)
        texture:SetPoint("TOPLEFT",6+(tile%4)*6,-6-math.floor(tile/4)*8)
        texture:SetSize(6,8)
    end
    swatch.color=swatch:CreateTexture(nil,"OVERLAY")
    swatch.color:SetPoint("TOPLEFT",6,-6)
    swatch.color:SetSize(24,16)
    swatch:SetScript("OnClick",function() OpenPicker(editor,key) end)
    return swatch
end
local function BuildPopup()
    local frame=CreateFrame("Frame","WoWToolsButtonMaterialMenu",UIParent)
    frame:SetSize(390,292)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    local background=frame:CreateTexture(nil,"BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.04,.04,.04,1)
    frame.search=CreateFrame("EditBox",nil,frame,"InputBoxTemplate")
    Label(frame,"搜索",12,-16)
    frame.search:SetSize(260,24)
    frame.search:SetPoint("TOPLEFT",52,-10)
    frame.search:SetAutoFocus(false)
    frame.search:SetScript("OnEscapePressed",function() frame:Hide() end)
    local close=Button(frame,"×",28,24)
    close:SetPoint("TOPRIGHT",-10,-10)
    close:SetScript("OnClick",function() frame:Hide() end)
    frame.rows={}
    frame.offset=0
    function frame:Refresh()
        local query=self.search:GetText():lower()
        local all=module.GetMaterials()
        local filtered={}
        for _,entry in ipairs(all) do
            if query=="" or entry.label:lower():find(query,1,true) then filtered[#filtered+1]=entry end
        end
        self.offset=math.max(0,math.min(self.offset,math.max(0,#filtered-8)))
        for index,row in ipairs(self.rows) do
            local entry=filtered[self.offset+index]
            row.entry=entry
            if entry then
                row.label:SetText(entry.label)
                row.sample:SetTexture(entry.path)
                row:Show()
            else row:Hide() end
        end
        self.footer:SetText(#filtered.." 项材质 · 滚轮浏览")
    end
    for index=1,8 do
        local row=CreateFrame("Button",nil,frame)
        module.Exclude(row)
        row:SetSize(366,26)
        row:SetPoint("TOPLEFT",12,-40-(index-1)*27)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
        row.label=Label(row,"",4,-5)
        row.label:SetWidth(190)
        row.label:SetJustifyH("LEFT")
        if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        row.sample=row:CreateTexture(nil,"ARTWORK")
        row.sample:SetPoint("TOPRIGHT",-4,-5)
        row.sample:SetSize(154,16)
        row:SetScript("OnClick",function(self)
            local value=module.GetConfig()
            value.material=self.entry.key
            local ok,message=module.Save(value)
            if not ok then frame.editor.status:SetText(message) end
            frame:Hide()
        end)
        frame.rows[index]=row
    end
    frame.footer=Label(frame,"",12,-267)
    frame.search:SetScript("OnTextChanged",function() frame.offset=0;frame:Refresh() end)
    frame:SetScript("OnMouseWheel",function(self,delta) self.offset=self.offset-delta;self:Refresh() end)
    frame:Hide()
    UISpecialFrames[#UISpecialFrames+1]="WoWToolsButtonMaterialMenu"
    return frame
end
function module.BuildSettings(parent)
    local hint=Label(parent,"游戏菜单及同类按钮，包含地图和窗口的关闭按钮。修改立即应用并保存。",8,-8)
    hint:SetWidth(398);hint:SetJustifyH("LEFT")
    local editor={swatches={}}
    module.editors[#module.editors+1]=editor
    local enabled=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
    module.Exclude(enabled)
    enabled:SetSize(28,28)
    enabled:SetPoint("TOPLEFT",8,-44)
    Label(parent,"启用自定义按钮样式",42,-51)
    editor.enabled=enabled
    enabled:SetScript("OnClick",function(self)
        local value=module.GetConfig()
        value.enabled=self:GetChecked()==true
        module.Save(value)
    end)
    Label(parent,"材质",8,-94)
    editor.material=Button(parent,"",278,26)
    editor.material:SetPoint("TOPLEFT",82,-86)
    editor.sample=parent:CreateTexture(nil,"ARTWORK")
    editor.sample:SetPoint("TOPLEFT",82,-118)
    editor.sample:SetSize(278,18)
    editor.material:SetScript("OnClick",function()
        if not popup then popup=BuildPopup() end
        if popup:IsShown() and popup.editor==editor then popup:Hide();return end
        popup.editor=editor
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT",editor.material,"BOTTOMLEFT",0,-4)
        popup.offset=0
        popup.search:SetText("")
        popup:Refresh()
        popup:Show()
    end)
    Label(parent,"颜色与透明度",8,-162)
    for index,state in ipairs(module.states) do
        local rowY=-190-(index-1)*38
        Label(parent,state.label,8,rowY-6)
        editor.swatches[state.key]=Swatch(parent,editor,state.key,rowY)
    end
    Label(parent,"边框",8,-356)
    editor.borderGroup=CreateRadioButtonGroup()
    editor.borderOptions={}
    for index,style in ipairs(module.borderStyles) do
        local key=style.key
        local tab=CreateFrame("Button",nil,parent,"MinimalTabTemplate")
        module.Exclude(tab)
        tab:SetSize(90,30)
        tab:SetPoint("TOPLEFT",82+(index-1)*96,-346)
        tab.Text:SetText(style.label)
        editor.borderGroup:AddButton(tab)
        tab:SetScript("OnClick",function()
            module.CloseColorPicker()
            local value=module.GetConfig()
            value.border.style=key
            module.Save(value)
        end)
        editor.borderOptions[style.key]=tab
    end
    Label(parent,"边框颜色",8,-396)
    editor.borderColor=Swatch(parent,editor,"border",-390)
    Label(parent,"预览",8,-446)
    editor.preview=Button(parent,"按钮预览",210,28)
    module.Exclude(editor.preview)
    editor.preview:SetPoint("TOPLEFT",8,-470)
    editor.disabled=Button(parent,"禁用预览",140,28)
    module.Exclude(editor.disabled)
    editor.disabled:SetPoint("LEFT",editor.preview,"RIGHT",12,0)
    editor.disabled:Disable()
    editor.closePreview=CreateFrame("Button",nil,parent,"UIPanelCloseButton")
    module.Exclude(editor.closePreview)
    editor.closePreview:SetSize(28,28)
    editor.closePreview:SetPoint("LEFT",editor.disabled,"RIGHT",8,0)
    editor.closePreview:SetScript("OnClick",nil)
    local reset=Button(parent,"恢复默认",112,26)
    reset:SetPoint("TOPLEFT",8,-520)
    reset:SetScript("OnClick",function() module.Reset() end)
    editor.status=Label(parent,"",8,-560)
    editor.status:SetWidth(398);editor.status:SetJustifyH("LEFT")
    editor.status:SetHeight(32)
    parent:SetScript("OnShow",module.RefreshSettings)
    parent:SetScript("OnHide",function()
        if popup and popup.editor==editor then popup:Hide() end
        if pickerSession and pickerSession.editor==editor then module.CloseColorPicker() end
    end)
    local function Layout()
        local width=math.max(420,parent:GetWidth())
        hint:SetWidth(width-16)
        editor.status:SetWidth(width-16)
        editor.material:SetWidth(width-100)
        editor.sample:SetWidth(width-100)
        for _,swatch in pairs(editor.swatches) do swatch:SetWidth(width-100) end
        editor.borderColor:SetWidth(width-100)
        local tabWidth=math.floor((width-100)/3)
        for index,style in ipairs(module.borderStyles) do
            local tab=editor.borderOptions[style.key]
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT",82+(index-1)*tabWidth,-346)
            tab:SetWidth(tabWidth-6)
        end
        editor.preview:SetWidth(math.floor((width-56)*0.6))
        editor.disabled:SetWidth(math.floor((width-56)*0.4)-12)
    end
    parent:SetScript("OnSizeChanged",Layout)
    Layout()
    parent:SetHeight(module.settingsHeight)
    module.RefreshSettings()
end
