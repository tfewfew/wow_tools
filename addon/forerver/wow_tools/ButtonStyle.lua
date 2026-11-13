-- Forever 16001 button materials, colors and native appearance restoration.
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
local materialPath = white
local records, excluded = {}, setmetatable({}, {__mode="k"})
local seen = setmetatable({}, {__mode="k"})
local scanRoots, scanAll = {}, false
local initialized, queued, hookedCreate, mediaLibrary = false, false, false, nil
local events = CreateFrame("Frame")
local reference = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
local closeReference = CreateFrame("Button", nil, UIParent, "UIPanelCloseButtonNoScripts")
local dialogReference = CreateFrame("Button", nil, UIParent, "StaticPopupButtonTemplate")
reference:Hide()
closeReference:Hide()
dialogReference:Hide()
excluded[reference] = true
excluded[closeReference] = true
excluded[dialogReference] = true
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
        if sliced and Family(atlas) or panelFile or IsDialog(texture) or nativeAtlases[atlas] or nativeFile then return true end
    end
    return false
end
local function Finite(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end
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
local function Rectangle(object)
    local rect = Numbers(object,"GetRect",4)
    local scale = Read(object,"GetEffectiveScale")
    if not rect or rect[3] <= 0 or rect[4] <= 0 or not Finite(scale) or scale <= 0 then return nil end
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
local function ArtworkRect(texture, rect, close, role, interior)
    local atlas = Read(texture,"GetAtlas")
    local coordinates = Numbers(texture,"GetTexCoord",8)
    if not coordinates then return false end
    local margins = Numbers(texture,"GetTextureSliceMargins",4)
    local width,height,padding
    if not atlas then
        -- Panel and dialog artwork occupy 80x22 and 128x23 inside 128x32 files.
        local dialog = not close and IsDialog(texture)
        width,height = close and 32 or 128,32
        local artworkWidth = close and 32 or dialog and 128 or 80
        local artworkHeight = close and 32 or dialog and 23 or 22
        padding = close and (interior and 8 or 6) or (interior and 4 or 2)
        -- Both fills end at row 20, with distinct bottom insets in their content areas.
        local bottomPadding = padding
        if interior and not close then bottomPadding = dialog and 3 or 2 end
        return Crop(rect,coordinates,padding/width,padding/height,
            (artworkWidth-padding)/width,(artworkHeight-bottomPadding)/height,margins,width,height)
    end
    local info
    if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        local ok,value = pcall(C_Texture.GetAtlasInfo,atlas)
        if ok and type(value) == "table" then info=value end
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
    width,height = rect.right-rect.left,rect.top-rect.bottom
    if info and Finite(info.width) and Finite(info.height)
        and info.width > 0 and info.height > 0 then width,height=info.width,info.height end
    padding = height*(close and (interior and 3/24 or 1/24) or (interior and 1/8 or 1/16))
    local left = (role == "Right" or role == "Center" or role == "Middle") and 0 or padding/width
    local right = (role == "Left" or role == "Center" or role == "Middle") and 1 or 1-padding/width
    return Crop(rect,coordinates,left,padding/height,right,1-padding/height,margins,width,height)
end
local function Geometry(record, native)
    local button = record.button
    local buttonRect = Rectangle(button)
    if not buttonRect then return nil end
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
    local baseline = record.close and (atlas and 22 or 20) or (atlas and 28 or 18)
    if IsDialog(source) then baseline=21*19/23 end
    local outer,inner
    for texture in pairs(textures) do
        local rect = Rectangle(texture)
        if not rect then return nil end
        local close = record.close
        local artwork = roles[texture] == "NineSlice" and rect or ArtworkRect(texture,rect,close,roles[texture],false)
        if artwork == false then return nil end
        if artwork then outer=Union(outer,artwork) end
        if texture == activeTexture or roles[texture] then
            local interior = roles[texture] == "NineSlice" and rect or ArtworkRect(texture,rect,close,roles[texture],true)
            if interior == false then return nil end
            if interior then inner=Union(inner,interior) end
        end
    end
    if slice and slice.Center then inner=Rectangle(slice.Center) or inner end
    local bounds = native and inner or outer
    if not bounds then return nil end
    local scale = buttonRect.scale
    local pixel = 1/scale
    if type(GetPhysicalScreenSize) == "function" then
        local ok,_,height = pcall(GetPhysicalScreenSize)
        if ok and Finite(height) and height > 0 then pixel=768/height/scale end
    end
    -- Snap the shared rectangle in screen space, then return button-local offsets.
    local function Snap(value, origin) return math.floor(value/scale/pixel+.5)*pixel-origin/scale end
    local left,right = Snap(bounds.left,buttonRect.left),Snap(bounds.right,buttonRect.left)
    local bottom,top = Snap(bounds.bottom,buttonRect.bottom),Snap(bounds.top,buttonRect.bottom)
    if right <= left or top <= bottom then return nil end
    local thickness = math.max(pixel,math.floor((outer.top-outer.bottom)/scale/(baseline or 18)/pixel+.5)*pixel)
    thickness = math.min(thickness,(right-left)/8,(top-bottom)/8)
    return {left=left, right=right, bottom=bottom, top=top, thickness=thickness, pixel=pixel, textures=textures}
end
local function Capture(button)
    local record = {button=button, alpha={}, masked={}, textures={}, active=false}
    record.close = IsClose(button)
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
    if record.enabled ~= enabled or record.appearance ~= value then
        record.fill:SetEnabled(enabled)
        record.state, record.highlight = nil,nil
        if value.border.style == "thin" then
            local color = value.border.color
            record.border:SetVertexColor(color[1],color[2],color[3],color[4]*(enabled and 1 or .4375))
        end
        if record.glyph then record.glyph:SetAlpha(enabled and 1 or .4) end
        record.enabled = enabled
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
        record.active = false
        record.appearance, record.enabled, record.state, record.highlight, record.level = nil,nil,nil,nil,nil
        return true
    end
    record.active = true -- Restore partial mask or appearance changes after a failed apply.
    local native = value.border.style == "native"
    local geometry = Geometry(record,native)
    if not geometry then return false end -- Layout and restricted coordinates are retried on the next show/update.
    local previous = record.geometry or {}
    local changed = previous.left ~= geometry.left or previous.right ~= geometry.right
        or previous.bottom ~= geometry.bottom or previous.top ~= geometry.top
        or previous.thickness ~= geometry.thickness or previous.pixel ~= geometry.pixel
    if record.appearance ~= value or record.material ~= materialPath or changed then
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
        for _, state in ipairs(module.states) do
            local texture = record.textures[state.key]
            texture:SetTexture(materialPath)
            texture:ClearTextureSlice()
            texture:SetTexCoord(0,1,0,1)
            texture:SetVertexColor(unpack(value.colors[state.key]))
            texture:SetBlendMode("BLEND")
        end
        record.fill:Show()
        if value.border.style == "thin" then
            record.border:Show()
        else record.border:Hide() end
        if record.glyph then
            local font = Read(record.glyph,"GetFont")
            local size = math.max(8,math.min(20,(geometry.top-geometry.bottom)*.7))
            if font then record.glyph:SetFont(font,size,"OUTLINE") end
            record.glyph:ClearAllPoints()
            record.glyph:SetPoint("CENTER",record.fill,"CENTER",0,0)
            record.glyph:Show()
        end
    end
    -- Native clients may replace state textures when showing or updating a button.
    for texture in pairs(geometry.textures) do Remember(record,texture,native) end
    for texture, alpha in pairs(record.alpha) do texture:SetAlpha(native and alpha or 0) end
    if not SyncState(record,value,preview) then return false end
    record.appearance, record.material, record.geometry = value,materialPath,geometry
    return true
end
local function Watch(record, preview)
    local button = record.button
    local function Update(stateOnly)
        if not initialized then return end
        local action = stateOnly == true and SyncState or Paint
        local ok,result = pcall(action,record,current,preview)
        if not ok or not result then
            record.appearance = nil
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
    local handlers = {
        OnEnter=function() record.hover=true;Update(true) end,
        OnLeave=function() record.hover=false;Update(true) end,
        OnHide=function() record.hover=false;Update(true) end,
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
        for _, method in ipairs({"SetButtonState","SetScale","SetFrameLevel"}) do
            if type(button[method]) == "function" then pcall(hooksecurefunc,button,method,function() Update(false) end) end
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
    return Paint(record,current,true)
end
module.previews = {}
local function DiscoverAll(found)
    if type(EnumerateFrames) ~= "function" then return end
    ReadReference(reference,nativeFiles,nativeAtlases)
    ReadReference(closeReference,closeFiles,closeAtlases)
    ReadReference(dialogReference,nativeFiles,nativeAtlases,"dialog")
    local frame = EnumerateFrames()
    while frame do
        seen[frame] = true
        local record = Track(frame)
        if record then found[#found+1] = record end
        frame = EnumerateFrames(frame)
    end
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
    local applied, failed = 0, 0
    materialPath = module.ResolveMaterial(current.material)
    if current.enabled and discover then DiscoverAll({}) end
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
local function QueueScan(name, parent)
    if not initialized or not current.enabled then return end
    local root = type(name) == "string" and _G[name]
    if type(parent) == "string" then parent = _G[parent] end
    if root then scanRoots[root] = true
    elseif parent and type(parent.GetChildren) == "function" then
        -- Keep the new roots before callers can reparent their anonymous frames.
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if ok then
            for _, child in ipairs(children) do
                if not seen[child] then scanRoots[child] = true end
            end
        else scanAll = true end
    else scanAll = true end
    if queued then return end
    queued = true
    local function Run()
        queued = false
        local roots, all = scanRoots,scanAll
        scanRoots,scanAll = {},false
        if not current.enabled then return end
        local found = {}
        if all then DiscoverAll(found)
        else
            for frame in pairs(roots) do DiscoverTree(frame,found,true) end
        end
        for _, record in ipairs(found) do
            local ok, result = pcall(Paint,record,current)
            if not ok or not result then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
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
        module.Apply(false)
        return
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        module.Apply(false)
        return
    end
    local path = module.ResolveMaterial(current.material)
    if path ~= materialPath then module.Apply(false) end
    if event == "PLAYER_ENTERING_WORLD" then events:UnregisterEvent(event) end
    QueueScan()
end)
