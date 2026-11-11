-- Titan 38002 button materials, colors and native appearance restoration.
local module = { editors = {}, states = {
    {key="normal", label="正常", getter="GetNormalTexture", setter="SetNormalTexture"},
    {key="pushed", label="按下", getter="GetPushedTexture", setter="SetPushedTexture"},
    {key="highlight", label="悬停", getter="GetHighlightTexture", setter="SetHighlightTexture"},
    {key="disabled", label="禁用", getter="GetDisabledTexture", setter="SetDisabledTexture"},
} }
WoWTools.buttonStyle = module
module.borderStyles = {
    {key="native", label="原版"}, {key="thin", label="细边框"}, {key="none", label="无边框"},
}
local white = "Interface\\Buttons\\WHITE8X8"
local mediaPath = "Interface\\AddOns\\wow_tools\\Media\\"
local defaults = {
    enabled=false, material="builtin:flat",
    colors={normal={.16,.16,.16,1}, pushed={.08,.08,.08,1},
        highlight={1,1,1,.18}, disabled={.3,.3,.3,.5}},
    border={style="native", color={.65,.65,.65,.8}},
}
local function Copy(value)
    local border = value.border or defaults.border
    local result = {enabled=value.enabled, material=value.material, colors={},
        border={style=border.style, color={unpack(border.color)}}}
    for _, state in ipairs(module.states) do result.colors[state.key] = {unpack(value.colors[state.key])} end
    return result
end
local current = Copy(defaults)
local records, excluded = {}, setmetatable({}, {__mode="k"})
local initialized, queued, hookedCreate, mediaLibrary = false, false, false, nil
local events = CreateFrame("Frame")
local reference = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
local closeReference = CreateFrame("Button", nil, UIParent, "UIPanelCloseButtonNoScripts")
reference:Hide()
closeReference:Hide()
excluded[reference] = true
excluded[closeReference] = true
function module.Exclude(button) excluded[button] = true end
function module.GetConfig() return Copy(current) end
local function Read(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end
local function Media()
    if not LibStub or type(LibStub.GetLibrary) ~= "function" then return nil end
    local ok, library = pcall(LibStub.GetLibrary, LibStub, "LibSharedMedia-3.0", true)
    if ok then return library end
end
function module.GetMaterials()
    local list = {
        {key="builtin:flat", label="纯色", path=white},
        {key="builtin:blizzard", label="Blizzard", path="Interface\\TargetingFrame\\UI-StatusBar"},
    }
    local library = Media()
    local textures = library and Read(library, "HashTable", "statusbar")
    if type(textures) == "table" then
        local shared = {}
        for name, path in pairs(textures) do
            if type(name) == "string" and (type(path) == "string" and path ~= "" or type(path) == "number") then
                shared[#shared+1] = {key="lsm:"..name, label=name, path=path}
            end
        end
        table.sort(shared, function(a,b) return a.label < b.label end)
        for _, entry in ipairs(shared) do list[#list+1] = entry end
    end
    return list
end
function module.ResolveMaterial(key)
    if key == "builtin:flat" then return white, "纯色", false end
    if key == "builtin:blizzard" then return "Interface\\TargetingFrame\\UI-StatusBar", "Blizzard", false end
    local name = key:gsub("^lsm:", "")
    local library = Media()
    local textures = library and Read(library,"HashTable","statusbar")
    local path = type(textures) == "table" and textures[name]
    if type(path) == "string" and path ~= "" or type(path) == "number" then return path,name,false end
    return white,name,true
end
local function ValidColor(color)
    if type(color) ~= "table" then return false end
    for index=1,4 do
        local channel = color[index]
        if type(channel) ~= "number" or not (channel >= 0 and channel <= 1) then return false end
    end
    return true
end
local function Valid(value)
    if type(value) ~= "table" or type(value.enabled) ~= "boolean" or type(value.material) ~= "string"
        or type(value.colors) ~= "table" then return false end
    if value.material ~= "builtin:flat" and value.material ~= "builtin:blizzard"
        and not value.material:match("^lsm:.+") then return false end
    if #value.material > 256 or value.material:find("[%c]") then return false end
    for _, state in ipairs(module.states) do
        if not ValidColor(value.colors[state.key]) then return false end
    end
    local border = value.border
    return border == nil or type(border) == "table" and ValidColor(border.color)
        and (border.style == "native" or border.style == "thin" or border.style == "none")
end
local function Family(name)
    if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then return false end
    name = name:lower()
    return name:find("redbutton",1,true) or name:find("uipanelbutton",1,true)
        or name:find("common-button",1,true) or name:find("ui-panel-button",1,true)
end
local nativeFiles, nativeAtlases = {}, {}
local closeFiles, closeAtlases = {}, {}
local function Sources(button)
    return {Read(button,"GetNormalTexture") or false, button.Left or false, button.Middle or false,
        button.Center or false, button.Right or false}
end
local function ReadReference(button, files, atlases)
    for _,texture in ipairs(Sources(button)) do
        local atlas,path = Read(texture,"GetAtlas"),Read(texture,"GetTexture")
        if type(atlas) == "string" then atlases[atlas]=true
        elseif type(path) == "number" then files[path]=true end
    end
end
ReadReference(reference,nativeFiles,nativeAtlases)
ReadReference(closeReference,closeFiles,closeAtlases)
local function CloseFamily(name)
    if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then return false end
    name = name:lower()
    return name:find("ui-panel-minimizebutton-",1,true)
        or name:match("^%d*%-?redbutton%-exit") or name:match("^common%-button%-close")
end
local function IsClose(button)
    local normal = Read(button,"GetNormalTexture")
    local atlas,path = Read(normal,"GetAtlas"),Read(normal,"GetTexture")
    return CloseFamily(button.atlasName) or CloseFamily(button.buttonArtKit)
        or CloseFamily(atlas) or CloseFamily(path) or closeAtlases[atlas]
        or type(path) == "number" and not atlas and closeFiles[path]
end
local function Suitable(button)
    if excluded[button] or Read(button,"IsForbidden") == true
        or Read(button,"IsObjectType","Button") ~= true then return false end
    if IsClose(button) then return true end
    local sliced = button.Left and button.Right
    if sliced and (Family(button.atlasName) or Family(button.buttonArtKit)) then return true end
    for _,texture in ipairs(Sources(button)) do
        local atlas,path = Read(texture,"GetAtlas"),Read(texture,"GetTexture")
        local panelFile = type(path) == "string" and path:lower():find("ui-panel-button",1,true)
        local nativeFile = type(path) == "number" and not atlas and nativeFiles[path]
        if sliced and Family(atlas) or panelFile or nativeAtlases[atlas] or nativeFile then return true end
    end
    return false
end
local function Capture(button)
    local record = {button=button, alpha={}, masked={}, textures={}, active=false}
    record.close = IsClose(button)
    record.legacy = not (Read(Read(button,"GetNormalTexture"),"GetAtlas") or Read(button.Left,"GetAtlas"))
    record.fill = CreateFrame("Button",nil,button)
    excluded[record.fill] = true
    record.fill:SetAllPoints(button)
    record.fill:EnableMouse(false)
    record.mask = record.fill:CreateMaskTexture(nil,"BACKGROUND")
    record.nativeMask = button:CreateMaskTexture(nil,"BACKGROUND")
    record.nativeMask:SetAllPoints(record.fill)
    -- Clear the interior rectangle while keeping the original artwork outside it.
    record.nativeMask:SetTexture(mediaPath.."ButtonNativeCutout.tga","CLAMPTOWHITE","CLAMPTOWHITE","NEAREST")
    record.border = button:CreateTexture(nil,"OVERLAY")
    record.border:SetTexture(mediaPath.."ButtonRoundBorder.tga")
    record.border:SetTextureSliceMargins(4,4,4,4)
    record.border:SetBlendMode("BLEND")
    record.border:Hide()
    for _, state in ipairs(module.states) do
        local texture = record.fill:CreateTexture(nil, state.key == "highlight" and "HIGHLIGHT" or "BACKGROUND")
        texture:SetAllPoints(record.fill)
        texture:AddMaskTexture(record.mask)
        record.fill[state.setter](record.fill,texture)
        texture:SetBlendMode("BLEND")
        record.textures[state.key] = texture
    end
    record.fill:Hide()
    if record.close then
        local overlay = CreateFrame("Frame",nil,button)
        overlay:SetAllPoints(button)
        overlay:EnableMouse(false)
        record.glyph = overlay:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
        record.glyph:SetPoint("CENTER",button,"CENTER",0,0)
        record.glyph:SetText("×")
        record.glyph:SetTextColor(1,1,1,1)
        record.glyph:Hide()
    end
    return record
end
local function Remember(record, texture, native)
    if not texture or type(texture.SetAlpha) ~= "function" then return end
    if record.alpha[texture] == nil then record.alpha[texture] = Read(texture,"GetAlpha") or 1 end
    if native and not record.masked[texture] then
        texture:AddMaskTexture(record.nativeMask)
        record.masked[texture] = true
    end
end
local function Paint(record, value, preview)
    local button = record.button
    if Read(button,"IsForbidden") == true then return false end
    if not value.enabled and not preview then
        if not record.active then return true end
        record.fill:Hide()
        record.border:Hide()
        if record.glyph then record.glyph:Hide() end
        for texture in pairs(record.masked) do
            texture:RemoveMaskTexture(record.nativeMask)
            record.masked[texture] = nil
        end
        for texture, alpha in pairs(record.alpha) do texture:SetAlpha(alpha) end
        record.active = false
        return true
    end
    record.active = true -- Restore partial mask or appearance changes after a failed apply.
    local native = value.border.style == "native"
    -- Native artwork includes transparent padding inside the unchanged button hit rectangle.
    local height = Read(button,"GetHeight") or 22
    local padding,inset
    if record.close and record.legacy then padding,inset=height*6/32,height*8/32
    elseif record.legacy then padding,inset=height*2/22,height*4/22
    elseif record.close then padding,inset=height/24,height/8
    else padding,inset=height/16,height/8 end
    record.fill:ClearAllPoints()
    record.mask:ClearAllPoints()
    if native then
        local fillInset = inset+1
        local xInset = math.min(fillInset,math.max(0,((Read(button,"GetWidth") or height)-1)/2))
        local yInset = math.min(fillInset,math.max(0,(height-1)/2))
        record.fill:SetPoint("TOPLEFT",button,"TOPLEFT",xInset,-yInset)
        record.fill:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-xInset,yInset)
        record.mask:SetAllPoints(record.fill)
        record.mask:SetTexture(white,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE","NEAREST")
        record.mask:ClearTextureSlice()
    else
        local fillInset = padding + (value.border.style == "thin" and 1 or 0)
        record.fill:SetAllPoints(button)
        record.mask:SetPoint("TOPLEFT",button,"TOPLEFT",fillInset,-fillInset)
        record.mask:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-fillInset,fillInset)
        record.mask:SetTexture(mediaPath.."ButtonRoundMask.tga","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
        record.mask:SetTextureSliceMargins(4,4,4,4)
    end
    for _, state in ipairs(module.states) do Remember(record,Read(button,state.getter),native) end
    for _, key in ipairs({"Left","Middle","Center","Right"}) do Remember(record,button[key],native) end
    local slice = button.NineSlice
    if slice and type(slice.GetRegions) == "function" then
        for _, region in ipairs({slice:GetRegions()}) do
            if type(region.SetTexture) == "function" then Remember(record,region,native) end
        end
    end
    for texture, alpha in pairs(record.alpha) do texture:SetAlpha(native and alpha or 0) end
    local path = module.ResolveMaterial(value.material)
    for _, state in ipairs(module.states) do
        local texture = record.textures[state.key]
        texture:SetTexture(path)
        texture:ClearTextureSlice()
        texture:SetTexCoord(0,1,0,1)
        texture:SetVertexColor(unpack(value.colors[state.key]))
        texture:SetBlendMode("BLEND")
    end
    -- The lower-level, mouse-disabled child lets Blizzard retain native border states and text.
    record.fill:SetFrameLevel(math.max(0,(Read(button,"GetFrameLevel") or 1)-1))
    local enabled = Read(button,"IsEnabled") ~= false
    record.fill:SetEnabled(enabled)
    record.fill:SetButtonState(Read(button,"GetButtonState") or "NORMAL",true)
    if enabled and (record.hover or record.locked or Read(button,"IsMouseOver") == true) then
        record.fill:LockHighlight()
    else record.fill:UnlockHighlight() end
    record.fill:Show()
    if value.border.style == "thin" then
        local color = value.border.color
        record.border:ClearAllPoints()
        record.border:SetPoint("TOPLEFT",button,"TOPLEFT",padding,-padding)
        record.border:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-padding,padding)
        record.border:SetVertexColor(color[1],color[2],color[3],color[4]*(enabled and 1 or .4375))
        record.border:Show()
    else record.border:Hide() end
    if record.glyph then
        local font = Read(record.glyph,"GetFont")
        local size = math.max(8,math.min(20,(height-2*padding)*.7))
        if font then record.glyph:SetFont(font,size,"OUTLINE") end
        record.glyph:SetAlpha(enabled and 1 or .4)
        record.glyph:Show()
    end
    return true
end
local function Watch(record, preview)
    local button = record.button
    local function Update()
        if not initialized then return end
        local ok,result = pcall(Paint,record,current,preview)
        if not ok or not result then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end
    if type(button.HookScript) == "function" then
        for _, event in ipairs({"OnShow","OnSizeChanged","OnEnable","OnDisable","OnMouseDown","OnMouseUp"}) do
            button:HookScript(event,Update)
        end
        button:HookScript("OnEnter",function() record.hover=true;Update() end)
        button:HookScript("OnLeave",function() record.hover=false;Update() end)
    end
    if hooksecurefunc then
        for _, method in ipairs({"UpdateButton","SetButtonState","SetFrameLevel"}) do
            if type(button[method]) == "function" then pcall(hooksecurefunc,button,method,Update) end
        end
        if type(button.LockHighlight) == "function" then
            pcall(hooksecurefunc,button,"LockHighlight",function() record.locked=true;Update() end)
            pcall(hooksecurefunc,button,"UnlockHighlight",function() record.locked=false;Update() end)
        end
    end
end
local function Track(button)
    if records[button] or not Suitable(button) then return end
    local ok, record = pcall(Capture,button)
    if not ok then return end
    records[button] = record
    Watch(record,false)
end
function module.ApplyPreview(button)
    excluded[button] = true
    local record = module.previews[button]
    if not record then
        record=Capture(button)
        module.previews[button]=record
        Watch(record,true)
    end
    return Paint(record,current,true)
end
module.previews = {}
function module.Apply(discover)
    local applied, failed = 0, 0
    if current.enabled and discover and type(EnumerateFrames) == "function" then
        ReadReference(reference,nativeFiles,nativeAtlases)
        ReadReference(closeReference,closeFiles,closeAtlases)
        local button = EnumerateFrames()
        while button do
            Track(button)
            button = EnumerateFrames(button)
        end
    end
    for _, record in pairs(records) do
        local ok, result = pcall(Paint,record,current)
        if ok and result then applied=applied+1 else failed=failed+1 end
    end
    if failed > 0 then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    module.lastStatus = current.enabled and ("已保存，已应用 "..applied.." 个按钮"..(failed>0 and ("，"..failed.." 个待重试") or "。"))
        or ("自定义按钮样式已关闭"..(failed>0 and ("，"..failed.." 个按钮待恢复。") or "。"))
    local _, _, missing = module.ResolveMaterial(current.material)
    if missing then module.lastStatus=module.lastStatus.." 材质尚未加载，暂用纯色。" end
    if module.RefreshSettings then module.RefreshSettings() end
    return applied,failed
end
function module.Save(value)
    if not Valid(value) then return false,"按钮材质、颜色或边框无效。" end
    local discover = value.enabled and not current.enabled
    current = Copy(value)
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    wowDetectorDB.buttonStyle = Copy(current)
    module.Apply(discover)
    return true,module.lastStatus
end
function module.Reset()
    if module.CloseColorPicker then module.CloseColorPicker() end
    current = Copy(defaults)
    if type(wowDetectorDB) == "table" then wowDetectorDB.buttonStyle = nil end
    module.Apply(false)
end
local function QueueScan()
    if queued or not initialized or not current.enabled then return end
    queued = true
    local function Run()
        queued = false
        if current.enabled then module.Apply(true) end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0,Run) else Run() end
end
local function WatchMedia()
    local library = Media()
    if library and library ~= mediaLibrary and type(library.RegisterCallback) == "function" then
        mediaLibrary = library
        pcall(library.RegisterCallback,module,"LibSharedMedia_Registered",function(_,kind,name)
            if kind == "statusbar" and current.material == "lsm:"..tostring(name) then module.Apply(false) end
        end)
    end
end
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent",function(_,event,name)
    if event == "ADDON_LOADED" and name == "wow_tools" then
        local saved = type(wowDetectorDB) == "table" and wowDetectorDB.buttonStyle
        current = Valid(saved) and Copy(saved) or Copy(defaults)
        initialized = true
    end
    if not initialized then return end
    if not hookedCreate and type(hooksecurefunc) == "function" then
        hookedCreate = true
        hooksecurefunc("CreateFrame",function(_,_,_,templates)
            -- XML frame templates can create close buttons without a separate Lua CreateFrame call.
            if type(templates) == "string" then QueueScan() end
        end)
    end
    WatchMedia()
    if event == "PLAYER_REGEN_ENABLED" then events:UnregisterEvent(event) end
    module.Apply(true)
end)
