-- Forever 16001: use the user's verified native text regions; never change shared fonts.
local module = { controls = {} }
WoWTools.displayFonts = module
local specs = {{key="experience", label="经验值"}, {key="bags", label="背包剩余"}, {key="ammo", label="弹药剩余"}, {key="clock", label="时钟"}}
module.settingsHeight=154+#specs*122
local originals, startupApplied = {}, {}
local events, startup = nil, false
local function Add(list, region)
    if region and type(region.GetFont)=="function" and type(region.SetFont)=="function" then
        for _,existing in ipairs(list) do if existing==region then return end end
        list[#list+1]=region
    end
end
local function Regions(key)
    local list = {}
    if key=="experience" then
        local experience=StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum and StatusTrackingBarInfo.BarsEnum.Experience
        if experience then
            for _,container in pairs(StatusTrackingBarManager and StatusTrackingBarManager.barContainers or {}) do
                local bar=container.bars and container.bars[experience]
                Add(list,bar and bar.OverlayFrame and bar.OverlayFrame.Text)
            end
        end
    elseif key=="bags" then
        Add(list, MainMenuBarBackpackButton and MainMenuBarBackpackButton.FreeSlots)
    elseif key=="ammo" then
        for index=0,3 do
            local button=_G["CharacterBag"..index.."Slot"]
            Add(list,button and button.Count)
        end
    elseif key=="clock" then
        Add(list,TimeManagerClockTicker)
    end
    return list
end
local function Config()
    if type(wowDetectorDB)~="table" then return nil end
    if type(wowDetectorDB.displayFonts)~="table" then wowDetectorDB.displayFonts={} end
    return wowDetectorDB.displayFonts
end
local function Valid(value)
    return type(value)=="table" and type(value.size)=="number" and value.size>=8 and value.size<=48
        and value.size==math.floor(value.size) and (value.flags=="" or value.flags=="OUTLINE" or value.flags=="THICKOUTLINE")
end
local function ApplyRegion(region, value, restore)
    local ok,path,size,flags=pcall(region.GetFont,region)
    if not ok or type(path)~="string" then return false end
    local original=originals[region]
    if not original then
        original={path=path,size=size,flags=flags or ""}; originals[region]=original
    end
    local applied,result=pcall(region.SetFont,region,restore and original.path or path,value.size,value.flags)
    return applied and result~=false
end
local function ApplyKey(key)
    local config=Config()
    local regions=Regions(key)
    local applied=0
    if config and Valid(config[key]) then
        for _,region in ipairs(regions) do if ApplyRegion(region,config[key]) then applied=applied+1 end end
    end
    if startup then startupApplied[key]=#regions>0 end
    return #regions,applied
end
local function UpdateLoadEvents()
    if not startup then return end
    local config=Config()
    for _,spec in ipairs(specs) do
        if config and Valid(config[spec.key]) and not startupApplied[spec.key] then
            events:RegisterEvent("ADDON_LOADED")
            return
        end
    end
    events:UnregisterEvent("ADDON_LOADED")
end
local function ApplyPending()
    local config=Config()
    for _,spec in ipairs(specs) do
        if config and Valid(config[spec.key]) and not startupApplied[spec.key] then ApplyKey(spec.key) end
    end
    UpdateLoadEvents()
end
function module.Save(key,size,flags)
    local known=false;for _,spec in ipairs(specs) do if spec.key==key then known=true end end
    local value={size=tonumber(size),flags=flags}
    if not known or not Valid(value) then return false,"字号须为8–48整数，请选择有效描边。" end
    local regions=Regions(key)
    -- Validate the requested font on a private preview before persisting it.
    local preview=module.preview
    if preview then
        local default=regions[1] and select(1,regions[1]:GetFont()) or STANDARD_TEXT_FONT
        local ok,result=pcall(preview.SetFont,preview,default,value.size,value.flags)
        if not ok or result==false then return false,"字体预览失败，设置未保存。" end
    end
    local config=Config();if not config then return false,"插件尚未初始化。" end
    config[key]=value;local count,applied=ApplyKey(key);UpdateLoadEvents()
    if count>applied then return true,"已保存，但部分原生文字应用失败，请重载后检查。" end
    return true,count>0 and ("已应用并自动保存（"..applied.."处文字）。") or "已保存；对应原生文字加载后应用。"
end
function module.Reset(key)
    local config=Config();if config then config[key]=nil end
    startupApplied[key]=true
    for _,region in ipairs(Regions(key)) do
        local original=originals[region]
        if original then ApplyRegion(region,original,true) end
    end
    UpdateLoadEvents()
end
function module.BuildSettings(parent)
    local hint=parent:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT",8,-8);hint:SetWidth(398);hint:SetJustifyH("LEFT")
    hint:SetText("只调整字号和描边，沿用游戏原来的字体。设置自动保存，每次登录或重载插件后应用一次。")
    local preview=parent:CreateFontString(nil,"ARTWORK","GameFontNormal")
    module.preview=preview
    preview:SetPoint("TOPLEFT",8,-72-#specs*122);preview:SetWidth(398);preview:SetJustifyH("LEFT");preview:SetText("预览 12345")
    local flags={"","OUTLINE","THICKOUTLINE"};local labels={"无描边","描边","粗描边"}
    for index,spec in ipairs(specs) do
        local row=CreateFrame("Frame",nil,parent);row:SetSize(410,118);row:SetPoint("TOPLEFT",8,-56-(index-1)*122)
        local title=row:CreateFontString(nil,"ARTWORK","GameFontNormal");title:SetPoint("TOPLEFT");title:SetText(spec.label)
        local sizeLabel=row:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall");sizeLabel:SetPoint("TOPLEFT",0,-26);sizeLabel:SetText("字号（8–48）")
        local size=CreateFrame("EditBox",nil,row,"InputBoxTemplate");size:SetSize(48,24);size:SetPoint("TOPLEFT",108,-20);size:SetAutoFocus(false);size:SetNumeric(true)
        local outline=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");outline:SetSize(82,24);outline:SetPoint("TOPLEFT",180,-20)
        local apply=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");apply:SetSize(80,24);apply:SetPoint("TOPLEFT",0,-56);apply:SetText("应用")
        local reset=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");reset:SetSize(90,24);reset:SetPoint("LEFT",apply,"RIGHT",12,0);reset:SetText("恢复默认")
        local status=row:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall");status:SetPoint("TOPLEFT",0,-88);status:SetWidth(398);status:SetJustifyH("LEFT")
        local control={key=spec.key,size=size,sizeLabel=sizeLabel,outline=outline,status=status,apply=apply,reset=reset,flagIndex=1}
        module.controls[#module.controls+1]=control
        local function Load()
            local config=Config();local value=config and config[spec.key];local regions=Regions(spec.key)
            local nativeSize,nativeFlags
            if regions[1] then local _,size,flags=regions[1]:GetFont();nativeSize=size;nativeFlags=flags end
            size:SetText(tostring(Valid(value) and value.size or nativeSize or 12))
            local selectedFlags=Valid(value) and value.flags or nativeFlags or ""
            control.flagIndex=1;for i,f in ipairs(flags) do if selectedFlags==f then control.flagIndex=i end end
            outline:SetText(labels[control.flagIndex]);status:SetText(#regions>0 and "原生文字已找到。" or "对应原生文字尚未加载。")
        end
        outline:SetScript("OnClick",function() control.flagIndex=control.flagIndex%3+1;outline:SetText(labels[control.flagIndex]) end)
        apply:SetScript("OnClick",function() module.preview=preview;local _,message=module.Save(spec.key,size:GetText(),flags[control.flagIndex]);status:SetText(message);size:ClearFocus() end)
        reset:SetScript("OnClick",function() module.Reset(spec.key);Load() end)
        row:SetScript("OnShow",Load);Load()
    end
    parent:SetHeight(module.settingsHeight)
end
events=CreateFrame("Frame")
-- Wait for native startup layout, then apply saved settings once for this addon load.
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_ENTERING_WORLD" then
        if startup then return end
        startup=true
        events:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
    -- Only unresolved native widgets (e.g. load-on-demand ammo) may be applied later.
    if startup then ApplyPending() end
end)
