local root=TEST_ROOT or "."
local flavor = TEST_FLAVOR or "forerver"
dofile(root.."/addon/tests/BigFootLibraries.Tests.lua")
bit={band=function(left,right)
    local result,place=0,1
    while left>0 and right>0 do
        if left%2==1 and right%2==1 then result=result+place end
        left,right,place=math.floor(left/2),math.floor(right/2),place*2
    end
    return result
end}
local namespace = {}
Enum={EditModeSettingDisplayType={Checkbox=1,Slider=2,Dropdown=3,Divider=4}}
EDIT_MODE_MODERN_SYSTEM_MAP,EDIT_MODE_CLASSIC_SYSTEM_MAP={},{}
local function Copy(values)
    local result={}
    for key,value in pairs(values) do result[key]=type(value)=="table" and Copy(value) or value end
    return result
end
CopyTable=Copy
EventRegistry={RegisterCallback=function() end,RegisterFrameEventAndCallback=function() end}
EditModeManagerFrame=CreateFrame("Frame")
EditModeManagerFrame.HookScript=function() end
EditModeSystemSettingsDialog=CreateFrame("Frame")
EditModeSystemSettingsDialog.HookScript=function() end
CreateUnsecuredObjectPool=function(create)
    return {Acquire=function() return create(),true end,ReleaseAll=function() end}
end
local function LoadXML(path)
    local file=assert(io.open(path));local xml=file:read("*a");file:close()
    xml=xml:gsub("<!%-%-.-%-%->", "")
    local directory=path:match("^(.*[/\\])")
    for tag,relative in xml:gmatch("<(%w+)%s+file=['\"]([^'\"]+)['\"]") do
        local child=directory..relative:gsub("\\","/")
        if tag=="Include" then LoadXML(child) elseif tag=="Script" then assert(loadfile(child))("wow_tools",namespace) end
    end
end
LoadXML(root.."/addon/"..flavor.."/wow_tools/ls_toasts/embeds/_embeds.xml")
local media=LibStub("LibSharedMedia-3.0")
local gui=LibStub("AceGUI-3.0")
assert(media:Fetch("font",media:GetDefault("font")))
assert(gui.WidgetRegistry.LSPreviewBoxItem,"Toast item-filter preview widget missing")
assert(gui.WidgetRegistry.LSM30_Font,"Toast font widget missing")
assert(gui.WidgetRegistry.LSM30_Sound,"Toast sound widget missing")
assert(namespace.LibEditMode.AddFrame and namespace.LibEditMode.SettingType.ColorPicker,
    "Real edit-mode dependency did not initialize")
print("PASS: " .. flavor .. " embedded SharedMedia, font/sound/item widgets and LibEditMode interfaces.")
if flavor == "forerver" then
    local directory = root .. "/addon/forerver/wow_tools/forever_faces/Libs/"
    Minimap = CreateFrame("Frame")
    dofile(directory .. "LibDataBroker-1.1/LibDataBroker-1.1.lua")
    dofile(directory .. "LibDBIcon-1.0/LibDBIcon-1.0.lua")
    assert(type(LibStub("LibDataBroker-1.1").NewDataObject) == "function")
    assert(type(LibStub("LibDBIcon-1.0").Register) == "function")
    print("PASS: Forever portrait broker and minimap dependency interfaces.")
end
