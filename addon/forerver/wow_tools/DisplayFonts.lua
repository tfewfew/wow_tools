-- Forever 16001: native Experience StatusBar.Text, backpack FreeSlots and ammo Count.
local module = { controls = {} }
WoWTools.displayFonts = module
local specs = {{key="experience", label="经验值"}, {key="bags", label="背包剩余"}, {key="ammo", label="弹药剩余"}}
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
        for _,bar in pairs(StatusTrackingBarManager and StatusTrackingBarManager.bars or {}) do
            if bar.isExpBar then Add(list, bar.StatusBar and bar.StatusBar.Text); Add(list, bar.Text) end
        end
        Add(list, MainMenuExpBar and MainMenuExpBar.TextString); Add(list, MainMenuExpBarText)
    elseif key=="bags" then
        Add(list, MainMenuBarBackpackButton and MainMenuBarBackpackButton.FreeSlots)
    else
        Add(list, CharacterAmmoSlot and CharacterAmmoSlot.Count)
        Add(list, CharacterAmmoSlotCount)
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
        and value.size==math.floor(value.size) and type(value.path)=="string" and #value.path<=256
        and not value.path:find("[%c]") and (value.flags=="" or value.flags=="OUTLINE" or value.flags=="THICKOUTLINE")
end
local function ApplyRegion(region, value)
    local original=originals[region]
    if not original then
        local ok,path,size,flags=pcall(region.GetFont,region)
        if not ok or type(path)~="string" then return false end
        original={path=path,size=size,flags=flags or ""}; originals[region]=original
    end
    local path=value.path~="" and value.path or original.path
    local ok,result=pcall(region.SetFont,region,path,value.size,value.flags)
    return ok and result~=false
end
local function ApplyKey(key)
    local config=Config()
    local regions=Regions(key)
    if config and Valid(config[key]) then
        for _,region in ipairs(regions) do ApplyRegion(region,config[key]) end
    end
    if startup then startupApplied[key]=#regions>0 end
    return #regions
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
function module.Save(key,path,size,flags)
    local known=false;for _,spec in ipairs(specs) do if spec.key==key then known=true end end
    local value={path=path,size=tonumber(size),flags=flags}
    if not known or not Valid(value) then return false,"字号须为8–48整数，字体路径不能包含控制字符。" end
    local regions=Regions(key)
    -- Validate the requested font on a private preview before persisting it.
    local preview=module.preview
    if preview then
        local default=regions[1] and select(1,regions[1]:GetFont()) or STANDARD_TEXT_FONT
        local ok,result=pcall(preview.SetFont,preview,path~="" and path or default,value.size,value.flags)
        if not ok or result==false then return false,"字体路径无效，设置未保存。" end
    end
    local config=Config();if not config then return false,"插件尚未初始化。" end
    config[key]=value;ApplyKey(key);UpdateLoadEvents()
    return true,#regions>0 and "已应用并自动保存。" or "已保存；对应原生文字加载后应用。"
end
function module.Reset(key)
    local config=Config();if config then config[key]=nil end
    startupApplied[key]=true
    for _,region in ipairs(Regions(key)) do
        local original=originals[region]
        if original then ApplyRegion(region,original) end
    end
    UpdateLoadEvents()
end
function module.BuildSettings(parent)
    local hint=parent:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT",8,-8);hint:SetWidth(398);hint:SetJustifyH("LEFT")
    hint:SetText("设置自动保存到账号，每次登录或重载插件后应用一次。字体路径留空沿用原字体；恢复默认可撤销。弹药文字加载后应用。")
    module.preview=parent:CreateFontString(nil,"ARTWORK","GameFontNormal")
    module.preview:SetPoint("TOPLEFT",8,-430);module.preview:SetText("字体预览 经验 12345 / 67890")
    local flags={"","OUTLINE","THICKOUTLINE"};local labels={"无描边","描边","粗描边"}
    for index,spec in ipairs(specs) do
        local row=CreateFrame("Frame",nil,parent);row:SetSize(410,118);row:SetPoint("TOPLEFT",8,-54-(index-1)*122)
        local title=row:CreateFontString(nil,"ARTWORK","GameFontNormal");title:SetPoint("TOPLEFT");title:SetText(spec.label.."：字号 / 字体路径")
        local size=CreateFrame("EditBox",nil,row,"InputBoxTemplate");size:SetSize(45,24);size:SetPoint("TOPLEFT",6,-24);size:SetAutoFocus(false);size:SetNumeric(true)
        local path=CreateFrame("EditBox",nil,row,"InputBoxTemplate");path:SetSize(240,24);path:SetPoint("LEFT",size,"RIGHT",16,0);path:SetAutoFocus(false);path:SetMaxLetters(256)
        local outline=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");outline:SetSize(82,24);outline:SetPoint("LEFT",path,"RIGHT",10,0)
        local apply=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");apply:SetSize(80,24);apply:SetPoint("TOPLEFT",0,-56);apply:SetText("应用")
        local reset=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");reset:SetSize(90,24);reset:SetPoint("LEFT",apply,"RIGHT",12,0);reset:SetText("恢复默认")
        local status=row:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall");status:SetPoint("TOPLEFT",0,-88);status:SetWidth(398);status:SetJustifyH("LEFT")
        local control={key=spec.key,size=size,path=path,outline=outline,status=status,apply=apply,reset=reset,flagIndex=1}
        module.controls[#module.controls+1]=control
        local function Load()
            local config=Config();local value=config and config[spec.key];local regions=Regions(spec.key)
            local nativeSize
            if regions[1] then local _,size=regions[1]:GetFont();nativeSize=size end
            size:SetText(tostring(Valid(value) and value.size or nativeSize or 12));path:SetText(Valid(value) and value.path or "")
            control.flagIndex=1;for i,f in ipairs(flags) do if Valid(value) and value.flags==f then control.flagIndex=i end end
            outline:SetText(labels[control.flagIndex]);status:SetText(#regions>0 and "原生文字已找到。" or "对应原生文字尚未加载。")
        end
        outline:SetScript("OnClick",function() control.flagIndex=control.flagIndex%3+1;outline:SetText(labels[control.flagIndex]) end)
        apply:SetScript("OnClick",function() local _,message=module.Save(spec.key,path:GetText(),size:GetText(),flags[control.flagIndex]);status:SetText(message);size:ClearFocus();path:ClearFocus() end)
        reset:SetScript("OnClick",function() module.Reset(spec.key);Load() end)
        row:SetScript("OnShow",Load);Load()
    end
    parent:SetHeight(490)
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
