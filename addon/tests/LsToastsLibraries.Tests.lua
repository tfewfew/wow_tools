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
local function LoadXML(path)
    local file=assert(io.open(path));local xml=file:read("*a");file:close()
    xml=xml:gsub("<!%-%-.-%-%->", "")
    local directory=path:match("^(.*[/\\])")
    for tag,relative in xml:gmatch('<(%w+)%s+file="([^"]+)"') do
        local child=directory..relative:gsub("\\","/")
        if tag=="Include" then LoadXML(child) elseif tag=="Script" then dofile(child) end
    end
end
LoadXML(root.."/addon/"..flavor.."/wow_tools/ls_toasts/embeds/_embeds.xml")
local media=LibStub("LibSharedMedia-3.0")
local gui=LibStub("AceGUI-3.0")
assert(media:Fetch("font",media:GetDefault("font")))
assert(gui.WidgetRegistry.LSPreviewBoxItem,"Toast item-filter preview widget missing")
assert(gui.WidgetRegistry.LSM30_Font,"Toast font widget missing")
assert(gui.WidgetRegistry.LSM30_Sound,"Toast sound widget missing")
LoadXML(root.."/addon/"..flavor.."/wow_tools/ls_toasts/embeds/_embeds.xml")
assert(LibStub("LibSharedMedia-3.0")==media,"Duplicate toast dependencies replaced shared media")
print("PASS: real embedded lsToast SharedMedia/font/sound/item-preview dependencies load alongside the shared Ace3 registry and support repeated loads. Offline APIs only.")
