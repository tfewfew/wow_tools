-- Titan 38002 button materials, colors and native appearance restoration.
local module = { editors = {}, states = {
    {key="normal", label="正常", getter="GetNormalTexture", setter="SetNormalTexture"},
    {key="pushed", label="按下", getter="GetPushedTexture", setter="SetPushedTexture"},
    {key="highlight", label="悬停", getter="GetHighlightTexture", setter="SetHighlightTexture"},
    {key="disabled", label="禁用", getter="GetDisabledTexture", setter="SetDisabledTexture"},
} }
WoWTools.buttonStyle = module
local white = "Interface\\Buttons\\WHITE8X8"
local mediaPath = "Interface\\AddOns\\wow_tools\\Media\\"
local defaults = {
    enabled=false, material="builtin:flat",
    colors={normal={.16,.16,.16,1}, pushed={.08,.08,.08,1},
        highlight={1,1,1,.18}, disabled={.3,.3,.3,.5}},
}
local function Copy(value)
    local result = {enabled=value.enabled, material=value.material, colors={}}
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
local function Valid(value)
    if type(value) ~= "table" or type(value.enabled) ~= "boolean" or type(value.material) ~= "string"
        or type(value.colors) ~= "table" then return false end
    if value.material ~= "builtin:flat" and value.material ~= "builtin:blizzard"
        and not value.material:match("^lsm:.+") then return false end
    if #value.material > 256 or value.material:find("[%c]") then return false end
    for _, state in ipairs(module.states) do
        local color = value.colors[state.key]
        if type(color) ~= "table" then return false end
        for index=1,4 do
            local channel = color[index]
            if type(channel) ~= "number" or not (channel >= 0 and channel <= 1) then return false end
        end
    end
    return true
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
    local record = {button=button, original={}, alpha={}, blend={}, textures={}, active=false}
    record.mask = button:CreateMaskTexture(nil,"BACKGROUND")
    record.mask:SetPoint("TOPLEFT",button,"TOPLEFT",1,-1)
    record.mask:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-1,1)
    record.mask:SetTexture(mediaPath.."ButtonRoundMask.tga","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
    -- Shader nineslice preserves the corner radius as the button changes width or height.
    record.mask:SetTextureSliceMargins(4,4,4,4)
    record.border = button:CreateTexture(nil,"OVERLAY")
    record.border:SetAllPoints(button)
    record.border:SetTexture(mediaPath.."ButtonRoundBorder.tga")
    record.border:SetTextureSliceMargins(4,4,4,4)
    record.border:SetBlendMode("BLEND")
    record.border:Hide()
    local function Remember(texture)
        if texture and type(texture.SetAlpha) == "function" and record.alpha[texture] == nil then
            record.alpha[texture] = Read(texture,"GetAlpha") or 1
            record.blend[texture] = Read(texture,"GetBlendMode")
        end
    end
    for _, state in ipairs(module.states) do
        local original = Read(button,state.getter)
        record.original[state.key] = original or false
        Remember(original)
        local texture = button:CreateTexture(nil, state.key == "highlight" and "HIGHLIGHT" or "BACKGROUND")
        texture:SetAllPoints(record.mask)
        texture:AddMaskTexture(record.mask)
        texture:SetBlendMode("BLEND")
        texture:Hide()
        record.textures[state.key] = texture
    end
    for _, key in ipairs({"Left","Middle","Center","Right"}) do Remember(button[key]) end
    local slice = button.NineSlice
    if slice and type(slice.GetRegions) == "function" then
        for _, region in ipairs({slice:GetRegions()}) do
            if type(region.SetTexture) == "function" then Remember(region) end
        end
    end
    if IsClose(button) then
        -- A child frame keeps the X above even an opaque native highlight layer.
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
local function Paint(record, value, preview)
    local button = record.button
    if Read(button,"IsForbidden") == true then return false end
    if not value.enabled and not preview then
        if not record.active then return true end
        if record.glyph then record.glyph:Hide() end
        record.border:Hide()
        for _, state in ipairs(module.states) do
            button[state.setter](button, record.original[state.key] or nil)
            record.textures[state.key]:Hide()
        end
        for texture, alpha in pairs(record.alpha) do
            texture:SetAlpha(alpha)
            if record.blend[texture] then texture:SetBlendMode(record.blend[texture]) end
        end
        record.active = false
        return true
    end
    local path = module.ResolveMaterial(value.material)
    record.active = true -- A failed partial apply must still be restorable.
    if record.glyph then
        local font = Read(record.glyph,"GetFont")
        local size = math.max(10,math.min(20,(Read(button,"GetHeight") or 24)*.6))
        if font then record.glyph:SetFont(font,size,"OUTLINE") end
        record.glyph:SetAlpha(Read(button,"IsEnabled") == false and .4 or 1)
        record.glyph:Show()
    end
    for texture in pairs(record.alpha) do texture:SetAlpha(0) end
    for _, state in ipairs(module.states) do
        local texture = record.textures[state.key]
        texture:SetTexture(path)
        texture:ClearTextureSlice()
        texture:SetTexCoord(0,1,0,1)
        texture:SetVertexColor(unpack(value.colors[state.key]))
        texture:Show()
        if Read(button,state.getter) ~= texture then button[state.setter](button,texture) end
        texture:SetBlendMode("BLEND")
    end
    local borderAlpha = Read(button,"IsEnabled") == false and .35 or .8
    record.border:SetVertexColor(.65,.65,.65,borderAlpha)
    record.border:Show()
    return true
end
local function Track(button)
    if records[button] or not Suitable(button) then return end
    local ok, record = pcall(Capture, button)
    if not ok then return end
    records[button] = record
    local function Update()
        if not initialized then return end
        local ok,result = pcall(Paint,record,current)
        if not ok or not result then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end
    if type(button.HookScript) == "function" then
        for _, event in ipairs({"OnShow","OnEnable","OnDisable","OnMouseDown","OnMouseUp","OnEnter","OnLeave"}) do
            button:HookScript(event,Update)
        end
    end
    if hooksecurefunc and type(button.UpdateButton) == "function" then
        pcall(hooksecurefunc,button,"UpdateButton",Update)
    end
end
function module.ApplyPreview(button)
    excluded[button] = true
    local record = module.previews[button]
    if not record then record=Capture(button); module.previews[button]=record end
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
    if not Valid(value) then return false,"按钮材质或颜色无效。" end
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
