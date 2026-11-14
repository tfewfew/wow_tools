-- Titan 38002 button materials, colors and native appearance restoration.
local module = { editors = {}, configVersion = 0, states = {
    {key="normal", label="正常", getter="GetNormalTexture", setter="SetNormalTexture"},
    {key="pushed", label="按下", getter="GetPushedTexture", setter="SetPushedTexture"},
    {key="highlight", label="悬停", getter="GetHighlightTexture", setter="SetHighlightTexture"},
    {key="disabled", label="禁用", getter="GetDisabledTexture", setter="SetDisabledTexture"},
} }
WoWTools.buttonStyle = module
WoWTools.modules.button_style = module
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
local materialPath = white
local records, excluded = {}, setmetatable({}, {__mode="k"})
local seen = setmetatable({}, {__mode="k"})
local scanRoots, scanAll = {}, false
local knownFrameCount, scanCost = 0, 0
local pendingRecords, retryRecords = {}, {}
local flushQueued, applyRequested, discoverRequested = false, false, false
local ScheduleFlush
local initialized, queued, hookedCreate, mediaLibrary = false, false, false, nil
local events = CreateFrame("Frame")
local reference = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
local closeReference = CreateFrame("Button", nil, UIParent, "UIPanelCloseButtonNoScripts")
local dialogReference = CreateFrame("Button", nil, UIParent, "StaticPopupButtonTemplate")
local windowReference = CreateFrame("Frame", nil, UIParent, "MaximizeMinimizeButtonFrameTemplate")
reference:Hide()
closeReference:Hide()
dialogReference:Hide()
windowReference:Hide()
excluded[reference] = true
excluded[closeReference] = true
excluded[dialogReference] = true
excluded[windowReference.MaximizeButton] = true
excluded[windowReference.MinimizeButton] = true
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
local windowFiles, windowAtlases = {}, {}
local function Sources(button)
    return {Read(button,"GetNormalTexture") or false, button.Left or false, button.Middle or false,
        button.Center or false, button.Right or false}
end
local function ReadReference(button, files, atlases, family)
    local sources = Sources(button)
    for _,state in ipairs(module.states) do sources[#sources+1] = Read(button,state.getter) or false end
    for _,texture in ipairs(sources) do
        local atlas,path = Read(texture,"GetAtlas"),Read(texture,"GetTexture")
        if type(atlas) == "string" then atlases[atlas]=family or true
        elseif type(path) == "number" then files[path]=family or true end
    end
end
ReadReference(reference,nativeFiles,nativeAtlases)
ReadReference(closeReference,closeFiles,closeAtlases)
ReadReference(dialogReference,nativeFiles,nativeAtlases,"dialog")
ReadReference(windowReference.MaximizeButton,windowFiles,windowAtlases,"↗")
ReadReference(windowReference.MinimizeButton,windowFiles,windowAtlases,"↙")
local function IsDialog(texture)
    local atlas,path = Read(texture,"GetAtlas"),Read(texture,"GetTexture")
    return not atlas and (type(path) == "number" and nativeFiles[path] == "dialog"
        or type(path) == "string" and path:lower():find("ui-dialogbox-button-",1,true))
end
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
local function WindowFamily(name)
    if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then return nil end
    name = name:lower()
    if name:match("^%d*%-?redbutton%-expand") or name:find("ui-panel-biggerbutton-",1,true) then return "↗" end
    if name:match("^%d*%-?redbutton%-condense") or name:find("ui-panel-smallerbutton-",1,true) then return "↙" end
end
local function WindowGlyph(button)
    local normal = Read(button,"GetNormalTexture")
    local atlas,path = Read(normal,"GetAtlas"),Read(normal,"GetTexture")
    local glyph = windowAtlases[atlas]
    if type(path) == "number" and not atlas then glyph=windowFiles[path] end
    return glyph or WindowFamily(atlas) or WindowFamily(path)
end
local function Suitable(button)
    if excluded[button] or Read(button,"IsForbidden") == true
        or Read(button,"IsObjectType","Button") ~= true then return false end
    if IsClose(button) or WindowGlyph(button) then return true end
    local sliced = button.Left and button.Right
    if sliced and (Family(button.atlasName) or Family(button.buttonArtKit)) then return true end
    for _,texture in ipairs(Sources(button)) do
        local atlas,path = Read(texture,"GetAtlas"),Read(texture,"GetTexture")
        local panelFile = type(path) == "string" and path:lower():find("ui-panel-button",1,true)
        local nativeFile = type(path) == "number" and not atlas and nativeFiles[path]
        if sliced and Family(atlas) or panelFile or IsDialog(texture) or nativeAtlases[atlas] or nativeFile then return true end
    end
    return false
end
local function Finite(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end
local atlasCache, screenPixel = {}, 1
local function RefreshMetrics()
    screenPixel = 1
    if type(GetPhysicalScreenSize) == "function" then
        local ok,_,height = pcall(GetPhysicalScreenSize)
        if ok and Finite(height) and height > 0 then screenPixel=768/height end
    end
end
RefreshMetrics()
local function Numbers(object, method, count)
    if not object or type(object[method]) ~= "function" then return nil end
    local result = {pcall(object[method],object)}
    if not result[1] then return nil end
    table.remove(result,1)
    for index=1,count do
        if not Finite(result[index]) then return nil end
    end
    return result
end
local function Rectangle(object, allowCollapsed)
    local rect = Numbers(object,"GetRect",4)
    local scale = Read(object,"GetEffectiveScale")
    if not rect or rect[3] <= 0 and not allowCollapsed or rect[4] <= 0
        or not Finite(scale) or scale <= 0 then return nil end
    return {left=rect[1]*scale, bottom=rect[2]*scale,
        right=(rect[1]+rect[3])*scale, top=(rect[2]+rect[4])*scale, scale=scale}
end
local function Union(bounds, rect)
    if not bounds then return rect end
    bounds.left, bounds.bottom = math.min(bounds.left,rect.left),math.min(bounds.bottom,rect.bottom)
    bounds.right, bounds.top = math.max(bounds.right,rect.right),math.max(bounds.top,rect.top)
    return bounds
end
local function SlicePosition(fraction, extent, sourceExtent, leading, trailing, scale)
    local factor = math.min(1,extent/math.max(.001,(leading+trailing)*scale))
    local start,finish = leading*scale*factor,extent-trailing*scale*factor
    local sourceStart,sourceFinish = leading/sourceExtent,1-trailing/sourceExtent
    if fraction <= sourceStart then return fraction*sourceExtent*scale*factor end
    if fraction >= sourceFinish then return extent-(1-fraction)*sourceExtent*scale*factor end
    return start+(fraction-sourceStart)*(finish-start)/(sourceFinish-sourceStart)
end
local function Crop(rect, coordinates, left, top, right, bottom, margins, sourceWidth, sourceHeight)
    local u0,v0,u1,v1 = coordinates[1],coordinates[2],coordinates[5],coordinates[4]
    if u0 == u1 or v0 == v1 then return nil end
    local x0,x1 = (left-u0)/(u1-u0),(right-u0)/(u1-u0)
    local y0,y1 = (top-v0)/(v1-v0),(bottom-v0)/(v1-v0)
    x0,x1 = math.max(0,math.min(x0,x1)),math.min(1,math.max(x0,x1))
    y0,y1 = math.max(0,math.min(y0,y1)),math.min(1,math.max(y0,y1))
    if x0 >= x1 or y0 >= y1 then return nil end
    local width,height = rect.right-rect.left,rect.top-rect.bottom
    local leftOffset,rightOffset,topOffset,bottomOffset = x0*width,x1*width,y0*height,y1*height
    if margins then
        local sampledWidth,sampledHeight = sourceWidth*math.abs(u1-u0),sourceHeight*math.abs(v1-v0)
        leftOffset=SlicePosition(x0,width,sampledWidth,margins[1],margins[3],rect.scale)
        rightOffset=SlicePosition(x1,width,sampledWidth,margins[1],margins[3],rect.scale)
        topOffset=SlicePosition(y0,height,sampledHeight,margins[2],margins[4],rect.scale)
        bottomOffset=SlicePosition(y1,height,sampledHeight,margins[2],margins[4],rect.scale)
    end
    return {left=rect.left+leftOffset, right=rect.left+rightOffset,
        bottom=rect.top-bottomOffset, top=rect.top-topOffset}
end
local function ArtworkData(texture)
    local atlas = Read(texture,"GetAtlas")
    local coordinates = Numbers(texture,"GetTexCoord",8)
    if not coordinates then return nil end
    local margins = Numbers(texture,"GetTextureSliceMargins",4)
    local info = atlas and atlasCache[atlas]
    if atlas and not info and C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        local ok,value = pcall(C_Texture.GetAtlasInfo,atlas)
        if ok and type(value) == "table" then
            info = value
            atlasCache[atlas] = value
        end
    end
    -- Native ThreeSliceButtonMixin uses atlas-local coordinates for cropping.
    -- A complete sheet-coordinate rectangle is identified by its exact atlas bounds.
    if info and Finite(info.leftTexCoord) and Finite(info.rightTexCoord)
        and Finite(info.topTexCoord) and Finite(info.bottomTexCoord)
        and info.rightTexCoord > info.leftTexCoord and info.bottomTexCoord > info.topTexCoord
        and math.abs(math.min(coordinates[1],coordinates[5])-info.leftTexCoord) < .000001
        and math.abs(math.max(coordinates[1],coordinates[5])-info.rightTexCoord) < .000001
        and math.abs(math.min(coordinates[2],coordinates[4])-info.topTexCoord) < .000001
        and math.abs(math.max(coordinates[2],coordinates[4])-info.bottomTexCoord) < .000001 then
        for index=1,8,2 do
            coordinates[index] = (coordinates[index]-info.leftTexCoord)/(info.rightTexCoord-info.leftTexCoord)
            coordinates[index+1] = (coordinates[index+1]-info.topTexCoord)/(info.bottomTexCoord-info.topTexCoord)
        end
    end
    return {atlas=atlas, coordinates=coordinates, margins=margins, info=info, dialog=not atlas and IsDialog(texture)}
end
local function ArtworkRect(data, rect, square, role, interior)
    local coordinates,margins,info = data.coordinates,data.margins,data.info
    local width,height,padding
    if not data.atlas then
        -- Panel and dialog artwork occupy 80x22 and 128x23 inside 128x32 files.
        local dialog = not square and data.dialog
        width,height = square and 32 or 128,32
        local artworkWidth = square and 32 or dialog and 128 or 80
        local artworkHeight = square and 32 or dialog and 23 or 22
        padding = square and (interior and 8 or 6) or (interior and 4 or 2)
        local bottomPadding = padding
        if interior and not square then bottomPadding = dialog and 3 or 2 end
        return Crop(rect,coordinates,padding/width,padding/height,
            (artworkWidth-padding)/width,(artworkHeight-bottomPadding)/height,margins,width,height)
    end
    width,height = rect.right-rect.left,rect.top-rect.bottom
    if info and Finite(info.width) and Finite(info.height)
        and info.width > 0 and info.height > 0 then width,height=info.width,info.height end
    padding = height*(square and (interior and 3/24 or 1/24) or (interior and 1/8 or 1/16))
    local left = (role == "Right" or role == "Center" or role == "Middle") and 0 or padding/width
    local right = (role == "Left" or role == "Center" or role == "Middle") and 1 or 1-padding/width
    return Crop(rect,coordinates,left,padding/height,right,1-padding/height,margins,width,height)
end
local function Geometry(record, native, buttonRect)
    local button = record.button
    local active = Read(button,"GetButtonState") == "PUSHED" and "GetPushedTexture" or "GetNormalTexture"
    if Read(button,"IsEnabled") == false then active="GetDisabledTexture" end
    local activeTexture = Read(button,active) or Read(button,"GetNormalTexture")
    local textures, roles = {},{}
    for _,state in ipairs(module.states) do
        local texture = Read(button,state.getter)
        if texture then textures[texture]=true end
    end
    for _,key in ipairs({"Left","Middle","Center","Right"}) do
        local texture = button[key]
        if texture then textures[texture],roles[texture]=true,key end
    end
    local slice = button.NineSlice
    if slice and type(slice.GetRegions) == "function" then
        for _,texture in ipairs({slice:GetRegions()}) do
            if type(texture.SetTexture) == "function" then textures[texture],roles[texture]=true,"NineSlice" end
        end
    end
    local source = Read(button,"GetNormalTexture") or button.Left or activeTexture
    local atlas = Read(source,"GetAtlas")
    local square = record.symbol ~= nil
    local baseline = square and (atlas and 22 or 20) or (atlas and 28 or 18)
    if IsDialog(source) then baseline=21*19/23 end
    local outer,inner
    for texture in pairs(textures) do
        local stretch = roles[texture] == "Center" or roles[texture] == "Middle"
        local rect = Rectangle(texture,stretch)
        if not rect then return nil end
        -- Native three-slice buttons collapse their center when both end caps fill the width.
        if rect.right > rect.left then
            local nineSlice = roles[texture] == "NineSlice"
            local data = not nineSlice and ArtworkData(texture)
            if not nineSlice and not data then return nil end
            local artwork = nineSlice and rect or ArtworkRect(data,rect,square,roles[texture],false)
            if artwork then outer=Union(outer,artwork) end
            if texture == activeTexture or roles[texture] then
                local interior = nineSlice and rect or ArtworkRect(data,rect,square,roles[texture],true)
                if interior then inner=Union(inner,interior) end
            end
        end
    end
    if slice and slice.Center then inner=Rectangle(slice.Center) or inner end
    local bounds = native and inner or outer
    if not bounds then return nil end
    local scale = buttonRect.scale
    local pixel = screenPixel/scale
    -- Snap the shared rectangle in screen space, then return button-local offsets.
    local function Snap(value, origin) return math.floor(value/scale/pixel+.5)*pixel-origin/scale end
    local left,right = Snap(bounds.left,buttonRect.left),Snap(bounds.right,buttonRect.left)
    local bottom,top = Snap(bounds.bottom,buttonRect.bottom),Snap(bounds.top,buttonRect.bottom)
    if right <= left or top <= bottom then return nil end
    local thickness = math.max(pixel,math.floor((outer.top-outer.bottom)/scale/(baseline or 18)/pixel+.5)*pixel)
    thickness = math.min(thickness,(right-left)/8,(top-bottom)/8)
    return {left=left, right=right, bottom=bottom, top=top, thickness=thickness,
        pixel=pixel, textures=textures, buttonRect=buttonRect, native=native}
end
local function Capture(button)
    local record = {button=button, alpha={}, appliedAlpha={}, masked={}, textures={},
        colors={}, active=false, layoutDirty=true}
    record.symbol = IsClose(button) and "×" or WindowGlyph(button)
    record.fill = CreateFrame("Button",nil,button)
    excluded[record.fill] = true
    record.fill:SetAllPoints(button)
    record.fill:EnableMouse(false)
    record.mask = record.fill:CreateMaskTexture(nil,"BACKGROUND")
    record.nativeMask = button:CreateMaskTexture(nil,"BACKGROUND")
    record.nativeMask:SetAllPoints(record.fill)
    -- Clear the interior rectangle while keeping the original artwork outside it.
    record.nativeMask:SetTexture(mediaPath.."ButtonNativeCutout.tga","CLAMPTOWHITE","CLAMPTOWHITE","NEAREST")
    record.border = record.fill:CreateTexture(nil,"OVERLAY")
    record.border:SetAllPoints(record.fill)
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
    if record.symbol then
        local overlay = CreateFrame("Frame",nil,button)
        overlay:SetAllPoints(button)
        overlay:EnableMouse(false)
        record.glyph = overlay:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
        record.glyph:SetPoint("CENTER",record.fill,"CENTER",0,0)
        record.glyph:SetText(record.symbol)
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
local function SameColor(first, second)
    return first and second and first[1] == second[1] and first[2] == second[2]
        and first[3] == second[3] and first[4] == second[4]
end
local function SyncState(record, value, preview)
    if not record.active or not value.enabled and not preview then return true end
    local button = record.button
    if Read(button,"IsForbidden") == true then return false end
    local level = math.max(0,(Read(button,"GetFrameLevel") or 1)-1)
    if record.level ~= level then
        record.fill:SetFrameLevel(level)
        record.level = level
    end
    local enabled = Read(button,"IsEnabled") ~= false
    if record.enabled ~= enabled then
        record.fill:SetEnabled(enabled)
        record.state, record.highlight = nil,nil
        if record.glyph then record.glyph:SetAlpha(enabled and 1 or .4) end
        record.enabled = enabled
    end
    if value.border.style == "thin" and (record.borderEnabled ~= enabled or not SameColor(record.borderColor,value.border.color)) then
        local color = value.border.color
        record.border:SetVertexColor(color[1],color[2],color[3],color[4]*(enabled and 1 or .4375))
        record.borderColor,record.borderEnabled = color,enabled
    end
    local state = Read(button,"GetButtonState") or "NORMAL"
    if record.state ~= state then
        record.fill:SetButtonState(state,true)
        record.state = state
    end
    local highlight = enabled and (record.hover or record.locked or Read(button,"IsMouseOver") == true) or false
    if record.highlight ~= highlight then
        if highlight then record.fill:LockHighlight() else record.fill:UnlockHighlight() end
        record.highlight = highlight
    end
    return true
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
        record.appliedAlpha = {}
        record.active = false
        record.fillShown,record.borderStyle = false,nil
        record.enabled,record.state,record.highlight,record.level = nil,nil,nil,nil
        record.layoutDirty = true
        return true
    end
    local native = value.border.style == "native"
    local path = preview and module.ResolveMaterial(value.material) or materialPath
    local buttonRect = Rectangle(button)
    if not buttonRect then return false end
    local previous = record.geometry or {}
    local previousRect = previous.buttonRect or {}
    local geometry = record.geometry
    if record.layoutDirty or not geometry or previous.native ~= native
        or previousRect.left ~= buttonRect.left or previousRect.right ~= buttonRect.right
        or previousRect.bottom ~= buttonRect.bottom or previousRect.top ~= buttonRect.top
        or previousRect.scale ~= buttonRect.scale then
        geometry = Geometry(record,native,buttonRect)
    end
    if not geometry then return false end
    record.active = true -- Restore partial mask or appearance changes after a failed apply.
    local changed = previous.left ~= geometry.left or previous.right ~= geometry.right
        or previous.bottom ~= geometry.bottom or previous.top ~= geometry.top
        or previous.thickness ~= geometry.thickness or previous.pixel ~= geometry.pixel or previous.native ~= native
    if changed then
        local surfaceScale = native and 1 or geometry.thickness
        record.fill:SetScale(surfaceScale)
        record.fill:ClearAllPoints()
        record.mask:ClearAllPoints()
        record.fill:SetPoint("TOPLEFT",button,"BOTTOMLEFT",geometry.left/surfaceScale,geometry.top/surfaceScale)
        record.fill:SetPoint("BOTTOMRIGHT",button,"BOTTOMLEFT",geometry.right/surfaceScale,geometry.bottom/surfaceScale)
        record.mask:SetAllPoints(record.fill)
        if native then
            record.mask:SetTexture(white,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE","NEAREST")
            record.mask:ClearTextureSlice()
        else
            record.mask:SetTexture(mediaPath.."ButtonRoundMask.tga","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
            record.mask:SetTextureSliceMargins(4,4,4,4)
        end
        if record.glyph then
            local size = math.max(8,math.min(20,(geometry.top-geometry.bottom)*.7))
            if record.glyphSize ~= size then
                local font = Read(record.glyph,"GetFont")
                if font then
                    record.glyph:SetFont(font,size,"OUTLINE")
                    record.glyphSize = size
                end
            end
        end
    end
    for _, state in ipairs(module.states) do
        local texture = record.textures[state.key]
        if record.material ~= path then
            texture:SetTexture(path)
            texture:ClearTextureSlice()
            texture:SetTexCoord(0,1,0,1)
        end
        if not SameColor(record.colors[state.key],value.colors[state.key]) then
            texture:SetVertexColor(unpack(value.colors[state.key]))
            record.colors[state.key] = value.colors[state.key]
        end
    end
    if not record.fillShown then
        record.fill:Show()
        if record.glyph then record.glyph:Show() end
        record.fillShown = true
    end
    if record.borderStyle ~= value.border.style then
        if value.border.style == "thin" then
            record.border:Show()
        else record.border:Hide() end
        record.borderStyle = value.border.style
    end
    -- Native clients may replace state textures when showing or updating a button.
    for texture in pairs(geometry.textures) do
        Remember(record,texture,native)
        local alpha = native and record.alpha[texture] or 0
        if record.appliedAlpha[texture] ~= alpha or record.refreshNative and Read(texture,"GetAlpha") ~= alpha then
            texture:SetAlpha(alpha)
            record.appliedAlpha[texture] = alpha
        end
    end
    if not SyncState(record,value,preview) then return false end
    record.material,record.geometry = path,geometry
    record.layoutDirty,record.refreshNative,record.deferred = false,false,false
    return true
end
local function Retry(record)
    record.layoutDirty,record.refreshNative = true,true
    retryRecords[record] = true
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
end
local function TryPaint(record)
    pendingRecords[record] = nil
    if Read(record.button,"IsVisible") == false then
        record.deferred = true
        retryRecords[record] = nil
        return true
    end
    local ok,result = pcall(Paint,record,current,record.preview)
    if ok and result then
        retryRecords[record] = nil
        record.deferred = false
        return true
    end
    Retry(record)
    return false
end
local function QueueRecord(record)
    if not initialized or not current.enabled and not record.preview and not record.active then return end
    record.layoutDirty,record.refreshNative = true,true
    pendingRecords[record] = true
    ScheduleFlush()
end
ScheduleFlush = function()
    if flushQueued then return end
    flushQueued = true
    local function Run()
        flushQueued = false
        if applyRequested then
            local discover = discoverRequested
            applyRequested,discoverRequested = false,false
            module.Apply(discover)
        end
        local work = pendingRecords
        pendingRecords = {}
        for record in pairs(work) do TryPaint(record) end
        if not next(retryRecords) then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0,Run) else Run() end
end
local function Watch(record, preview)
    local button = record.button
    record.preview = preview
    local function Update(stateOnly)
        if not initialized then return end
        local ok,result = pcall(SyncState,record,current,preview)
        if not ok or not result then
            Retry(record)
        end
        if not stateOnly then QueueRecord(record) end
    end
    local handlers = {
        OnEnter=function() record.hover=true;Update(true) end,
        OnLeave=function() record.hover=false;Update(true) end,
        OnHide=function()
            record.hover,record.layoutDirty = false,true
            pendingRecords[record],retryRecords[record] = nil,nil
            Update(true)
        end,
    }
    if type(button.HookScript) == "function" then
        for _, event in ipairs({"OnShow","OnSizeChanged","OnEnable","OnDisable","OnMouseDown","OnMouseUp"}) do
            handlers[event] = function() Update(false) end
        end
        for event,callback in pairs(handlers) do button:HookScript(event,callback) end
    end
    if hooksecurefunc then
        if type(button.SetScript) == "function" and type(button.HookScript) == "function" then
            -- Pooled menu buttons replace scripts on reuse, clearing their script hooks.
            pcall(hooksecurefunc,button,"SetScript",function(_,event)
                local callback = handlers[event]
                if callback then button:HookScript(event,callback) end
            end)
        end
        for _,state in ipairs(module.states) do
            if type(button[state.setter]) == "function" then
                pcall(hooksecurefunc,button,state.setter,function() Update(false) end)
            end
        end
        if type(button.UpdateButton) == "function" then
            pcall(hooksecurefunc,button,"UpdateButton",function() Update(false) end)
        end
        for _, method in ipairs({"SetButtonState","SetScale"}) do
            if type(button[method]) == "function" then pcall(hooksecurefunc,button,method,function() Update(false) end) end
        end
        if type(button.SetFrameLevel) == "function" then
            pcall(hooksecurefunc,button,"SetFrameLevel",function() Update(true) end)
        end
        if type(button.LockHighlight) == "function" then
            pcall(hooksecurefunc,button,"LockHighlight",function() record.locked=true;Update(true) end)
            pcall(hooksecurefunc,button,"UnlockHighlight",function() record.locked=false;Update(true) end)
        end
    end
end
local function Track(button)
    if records[button] or not Suitable(button) then return end
    local ok, record = pcall(Capture,button)
    if not ok then return end
    records[button] = record
    Watch(record,false)
    return record
end
function module.ApplyPreview(button)
    excluded[button] = true
    local record = module.previews[button]
    if not record then
        record=Capture(button)
        module.previews[button]=record
        Watch(record,true)
    end
    return TryPaint(record)
end
module.previews = {}
local function DiscoverAll(found)
    if type(EnumerateFrames) ~= "function" then return end
    ReadReference(reference,nativeFiles,nativeAtlases)
    ReadReference(closeReference,closeFiles,closeAtlases)
    ReadReference(dialogReference,nativeFiles,nativeAtlases,"dialog")
    ReadReference(windowReference.MaximizeButton,windowFiles,windowAtlases,"↗")
    ReadReference(windowReference.MinimizeButton,windowFiles,windowAtlases,"↙")
    local frame,count = EnumerateFrames(),0
    while frame do
        count = count+1
        seen[frame] = true
        local record = Track(frame)
        if record then found[#found+1] = record end
        frame = EnumerateFrames(frame)
    end
    knownFrameCount = count
end
local function DiscoverTree(frame, found, force)
    if not frame or seen[frame] and not force or Read(frame,"IsForbidden") == true then return end
    seen[frame] = true
    local record = Track(frame)
    if record then found[#found+1] = record end
    if type(frame.GetChildren) ~= "function" then return end
    local ok, children = pcall(function() return {frame:GetChildren()} end)
    if ok then
        for _, child in ipairs(children) do DiscoverTree(child,found,false) end
    end
end
function module.Apply(discover)
    local applied, failed, deferred = 0, 0, 0
    local path,_,missing = module.ResolveMaterial(current.material)
    materialPath = path
    if current.enabled and discover then DiscoverAll({}) end
    for _, record in pairs(records) do
        local result = TryPaint(record)
        if not result then failed=failed+1
        elseif record.deferred then deferred=deferred+1
        else applied=applied+1 end
    end
    if not next(retryRecords) then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    module.lastStatus = current.enabled and ("已保存，已应用 "..applied.." 个按钮"..(failed>0 and ("，"..failed.." 个待重试") or "。"))
        or ("自定义按钮样式已关闭"..(failed>0 and ("，"..failed.." 个按钮待恢复。") or "。"))
    if deferred > 0 then module.lastStatus=module.lastStatus.." "..deferred.." 个隐藏按钮将在显示时更新。" end
    if missing then module.lastStatus=module.lastStatus.." 材质尚未加载，暂用纯色。" end
    if module.RefreshSettings then module.RefreshSettings() end
    return applied,failed
end
local function RequestApply(discover)
    applyRequested = true
    discoverRequested = discoverRequested or discover
    module.lastStatus = "已保存，正在更新按钮。"
    ScheduleFlush()
    return module.lastStatus
end
function module.Save(value)
    if not Valid(value) then return false,"按钮材质、颜色或边框无效。" end
    local desired = Copy(value)
    local same = desired.enabled == current.enabled and desired.material == current.material
        and desired.border.style == current.border.style and SameColor(desired.border.color,current.border.color)
    for _,state in ipairs(module.states) do
        same = same and SameColor(desired.colors[state.key],current.colors[state.key])
    end
    if same then return true,module.lastStatus end
    local discover = value.enabled and not current.enabled
    current = desired
    module.configVersion = module.configVersion+1
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    wowDetectorDB.buttonStyle = Copy(current)
    return true,RequestApply(discover)
end
function module.Reset()
    if module.CloseColorPicker then module.CloseColorPicker() end
    current = Copy(defaults)
    module.configVersion = module.configVersion+1
    if type(wowDetectorDB) == "table" then wowDetectorDB.buttonStyle = nil end
    RequestApply(false)
end
local function QueueScan(name, parent)
    if not initialized or not current.enabled then return end
    if scanAll and queued then return end
    local root = type(name) == "string" and _G[name]
    if type(parent) == "string" then parent = _G[parent] end
    if root then scanRoots[root] = true
    elseif parent and type(parent.GetChildren) == "function" then
        local count = Read(parent,"GetNumChildren")
        if Finite(count) then scanCost=scanCost+count end
        if knownFrameCount > 0 and scanCost > knownFrameCount then
            -- Bound repeated sibling snapshots by one complete discovery pass.
            scanAll = true
        else
            -- Pin anonymous roots before immediate reparenting by their callers.
            local ok, children = pcall(function() return {parent:GetChildren()} end)
            if ok then
                for _, child in ipairs(children) do
                    if not seen[child] then scanRoots[child] = true end
                end
            else scanAll = true end
        end
    else scanAll = true end
    if queued then return end
    queued = true
    local function Run()
        queued = false
        local roots, all = scanRoots,scanAll
        scanRoots,scanAll = {},false
        scanCost = 0
        if not current.enabled then return end
        local found = {}
        if all then DiscoverAll(found)
        else
            for frame in pairs(roots) do DiscoverTree(frame,found,true) end
        end
        for _, record in ipairs(found) do
            record.refreshNative = true
            TryPaint(record)
        end
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
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent",function(_,event,name)
    if event == "ADDON_LOADED" and name == "wow_tools" then
        local saved = type(wowDetectorDB) == "table" and wowDetectorDB.buttonStyle
        current = Valid(saved) and Copy(saved) or Copy(defaults)
        module.configVersion = module.configVersion+1
        initialized = true
    end
    if not initialized then return end
    if not hookedCreate and type(hooksecurefunc) == "function" then
        hookedCreate = true
        hooksecurefunc("CreateFrame",function(_,name,parent,templates)
            -- XML frame templates can create close buttons without a separate Lua CreateFrame call.
            if type(templates) == "string" then QueueScan(name,parent) end
        end)
    end
    WatchMedia()
    if event == "ADDON_LOADED" and name == "wow_tools" then
        module.Apply(true)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        events:UnregisterEvent(event)
        local work = retryRecords
        retryRecords = {}
        for record in pairs(work) do TryPaint(record) end
        if next(work) then
            module.lastStatus = next(retryRecords) and "部分按钮仍待重试。"
                or current.enabled and "待重试按钮已更新。" or "按钮原生外观已恢复。"
            if module.RefreshSettings then module.RefreshSettings() end
        end
        return
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        RefreshMetrics()
        for _,record in pairs(records) do record.layoutDirty=true end
        for _,record in pairs(module.previews) do QueueRecord(record) end
        module.Apply(false)
        return
    end
    local path = module.ResolveMaterial(current.material)
    if path ~= materialPath then module.Apply(false) end
    if event == "PLAYER_ENTERING_WORLD" then events:UnregisterEvent(event) end
    QueueScan()
end)
