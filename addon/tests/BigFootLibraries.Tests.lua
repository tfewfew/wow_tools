-- Load the bundled Ace3 implementation without any standalone addon or mock LibStub.
local flavor = TEST_FLAVOR or "forerver"
local root = TEST_ROOT or "."
local addon = root .. "/addon/"..flavor.."/wow_tools/"
local frames = {}
local errors = {}
local originalXpcall = xpcall
xpcall = function(callback, handler, ...)
    local arguments = {...}
    return originalXpcall(function() return callback(unpack(arguments)) end, handler)
end
local function Frame(name)
    local frame = {scripts={}, events={}}
    local methods = {
        SetScript = function(self, event, callback) self.scripts[event] = callback end,
        GetScript = function(self, event) return self.scripts[event] end,
        RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterEvent = function(self, event) self.events[event] = nil end,
        UnregisterAllEvents = function(self) self.events = {} end,
        GetName = function() return name end,
        IsShown = function() return false end,
        Hide = function() end,
        Show = function() end,
        CreateFontString = function() return Frame() end,
        CreateTexture = function() return Frame() end,
        GetNormalTexture = function() return Frame() end,
        GetPushedTexture = function() return Frame() end,
        GetHighlightTexture = function() return Frame() end,
    }
    setmetatable(frame, {__index=function(_, method)
        if methods[method] then return methods[method] end
        if method:match("^%u") then return function() end end
    end})
    frames[#frames+1] = frame
    if name then _G[name] = frame end
    return frame
end
CreateFrame = function(_, name) return Frame(name) end
UIParent, GameTooltip, ColorPickerFrame = Frame(), Frame(), Frame()
SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
GetLocale = function() return "zhCN" end
GetRealmName = function() return "测试服务器" end
UnitName = function() return "测试角色" end
UnitNameUnmodified = UnitName
UnitClass = function() return "战士", "WARRIOR" end
UnitRace = function() return "人类", "Human" end
UnitFactionGroup = function() return "Alliance" end
UnitSex = function() return 2 end
GetCurrentRegionName = function() return "CN" end
GetCurrentRegion = function() return 5 end
strlenutf8 = string.len
IsLoggedIn = function() return true end
GetTime = function() return 0 end
GetBuildInfo = function()
    if flavor=="titan" then return "3.80.2", "70522", "", 38002 end
    return "1.60.1", "70888", "", 16001
end
geterrorhandler = function() return function(message) errors[#errors+1] = message end end
hooksecurefunc = function() end
securecallfunction = function(callback, ...) return callback(...) end
C_Timer = {After=function() end, NewTimer=function() return {Cancel=function() end} end}
C_AddOns = {GetAddOnMetadata=function() return "wow_tools" end}
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_WRATH_CLASSIC = 1, 2, 11
WOW_PROJECT_ID = flavor=="titan" and WOW_PROJECT_WRATH_CLASSIC or WOW_PROJECT_MAINLINE
wipe = function(values) for key in pairs(values) do values[key] = nil end end
table.wipe = wipe
strtrim = function(value) return value:match("^%s*(.-)%s*$") end
strsplit = function(separator, value) return value:match("^(.-)" .. separator .. "(.*)$") end
LibStub = nil

local loaded = {}
local function LoadXML(path)
    local file = assert(io.open(path)); local xml = file:read("*a"); file:close()
    xml = xml:gsub("<!%-%-.-%-%->", "")
    local directory = path:match("^(.*[/\\])")
    for tag, relative in xml:gmatch('<(%w+)%s+file="([^"]+)"') do
        local child = directory .. relative:gsub("\\", "/")
        if tag == "Include" then LoadXML(child)
        elseif tag == "Script" then dofile(child); loaded[#loaded+1] = child end
    end
end
local function LoadLibraries()
    local file = assert(io.open(addon .. "wow_tools.toc")); local toc = file:read("*a"); file:close()
    assert(not toc:find("!!!Libs",1,true), "Standalone Ace dependency remains in TOC")
    assert(toc:find("LibStub.lua",1,true) < toc:find("Init.lua",1,true), "LibStub loads after chat")
    for line in toc:gmatch("[^\r\n]+") do
        if line:match("^bigfoot_channel\\Libs\\") then
            local path = addon .. line:gsub("\\", "/")
            if path:match("%.xml$") then LoadXML(path) else dofile(path); loaded[#loaded+1] = path end
        end
    end
end
LoadLibraries()
local required = {"CallbackHandler-1.0", "AceAddon-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0",
    "AceDB-3.0", "AceDBOptions-3.0", "AceLocale-3.0", "AceConsole-3.0", "AceGUI-3.0",
    "AceConfigRegistry-3.0", "AceConfigDialog-3.0", "AceConfigCmd-3.0", "AceConfig-3.0"}
local libraries = {}
for _, name in ipairs(required) do libraries[name] = assert(LibStub(name), name) end
for _, kind in ipairs({"Frame", "TabGroup", "SimpleGroup", "ScrollFrame", "CheckBox", "EditBox",
    "MultiLineEditBox", "Dropdown", "Button", "Label"}) do
    assert(LibStub("AceGUI-3.0").WidgetRegistry[kind], "Missing settings widget " .. kind)
end
assert(type(libraries["AceAddon-3.0"].NewAddon) == "function")
assert(type(libraries["AceConfigDialog-3.0"].Open) == "function")
assert(type(libraries["AceDB-3.0"].New) == "function")
assert(#errors == 0, table.concat(errors, "\n"))
print("PASS: " .. flavor .. " embedded Ace3 dependency loading, widget registration and API exports.")
