-- Ace3/XML adapter for offline tests. All game APIs remain simulated.
local mock = { filters = {}, options = {}, timers = {}, sent = {}, hooks = {}, joins = 0, now = 100 }
local function Noop() end
local function AddMethods(frame, name, parent)
    frame.scripts, frame.events = frame.scripts or {}, frame.events or {}
    frame.mockName, frame.mockParent = name, parent or UIParent
    function frame:GetName() return self.mockName end
    function frame:GetParent() return self.mockParent end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:HookScript(event, callback)
        local previous = self.scripts[event]
        self.scripts[event] = function(...) if previous then previous(...) end; callback(...) end
    end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetShown(value) if value then self:Show() else self:Hide() end end
    function frame:GetID() return self.mockID or 1 end
    function frame:GetAlpha() return self.alpha or 1 end
    function frame:SetFocus() self.focused = true end
    function frame:ClearFocus() self.focused = false end
    function frame:Insert(text) self:SetText((self:GetText() or "") .. text) end
    function frame:HighlightText() self.highlighted = true end
    function frame:SetChannelEnabled(channel, value) self.channelEnabled = value end
    function frame:GetNumMessages() return #(self.messages or {}) end
    function frame:GetMessageInfo(index) return self.messages[index] end
    function frame:GetLeft() return 10 end
    function frame:GetTop() return 300 end
    function frame:GetBottom() return 10 end
    function frame:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes and self.attributes[key] end
    if name then _G[name] = frame end
    return frame
end
local originalCreate = CreateFrame
function CreateFrame(kind, name, parent, template)
    local frame = AddMethods(originalCreate(kind, name, parent, template), name, parent)
    if template == "BFCChatTabTemplate" then _G[name .. "Text"] = AddMethods(originalCreate("Frame")) end
    return frame
end
UIParent = UIParent or CreateFrame("Frame", "UIParent")
WorldFrame = WorldFrame or CreateFrame("Frame", "WorldFrame")
ChatFrame1 = ChatFrame1 or CreateFrame("Frame", "ChatFrame1")
ChatFrame1EditBox = ChatFrame1EditBox or CreateFrame("EditBox", "ChatFrame1EditBox")
SELECTED_CHAT_FRAME = ChatFrame1
ItemRefTooltip = ItemRefTooltip or { SetHyperlink = Noop }
NUM_CHAT_WINDOWS, LE_PARTY_CATEGORY_INSTANCE = 10, 2
floor, ceil, min, max, mod = math.floor, math.ceil, math.min, math.max, math.fmod
tinsert, strsub, strlen, strupper, format, gsub = table.insert, string.sub, string.len, string.upper, string.format, string.gsub
wipe = function(values) for key in pairs(values) do values[key] = nil end end
GetLocale = GetLocale or function() return "zhCN" end
local originalUnitName = UnitName
UnitName = function(unit) if unit == "player" then return "测试角色" end; return originalUnitName(unit) end
GetRealmName = function() return "测试服务器" end
GetZoneText = function() return mock.zone or "测试区域" end
GetChannelName = function() return mock.channelID or 0 end
GetChannelList = function() return 6, "大脚世界频道", false end
Ambiguate = function(name) return name:match("^[^-]+") end
time = function() return mock.now end
JoinTemporaryChannel = function() mock.joins = mock.joins + 1 end
hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then mock.hooks[target] = method end
end
ToggleChatColorNamesByClassGroup, UIFrameFadeIn, UIFrameFadeOut = Noop, Noop, Noop
ChatTypeInfo = { SAY = {}, CHANNEL6 = { r=1, g=1, b=1 } }
ChatFrame1.channelList, ChatFrame1.zoneChannelList = { "大脚世界频道" }, { 0 }
CreateColor = function(...) return { ... } end
C_ColorUtil = { WrapTextInColor = function(text) return text end }
ChatFrameEditBoxMixin = { UpdateHeader = Noop, SendText = Noop, ClearChat = Noop,
    HandleChatType = function(editBox, _, text) editBox:SetAttribute("chatType", text) end }
C_ChatInfo = { InChatMessagingLockdown = function() return mock.lockdown end,
    SendChatMessage = function(text, destination) mock.sent[#mock.sent+1] = {text, destination} end }
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        mock.filters[event] = mock.filters[event] or {}
        table.insert(mock.filters[event], callback)
    end,
    ChooseBoxForSend = function() return ChatFrame1EditBox end,
    AddChannel = function() mock.attached = true end,
    ReplyTell = Noop, ReplyTell2 = Noop,
}
C_Timer = { After = function(delay, callback) mock.timers[#mock.timers+1] = { delay=delay, callback=callback } end }
IsInRaid, IsInGroup = function() return false end, function() return false end
if GameTooltip then GameTooltip.SetText = Noop end

local libraries, locales, addons = {}, {}, {}
mock.libraries = libraries
LibStub = setmetatable({ GetLibrary = function(_, name, silent)
    if not silent then assert(libraries[name], name) end
    return libraries[name]
end }, { __call = function(self, name, silent) return self:GetLibrary(name, silent) end })
libraries["AceLocale-3.0"] = {
    NewLocale = function(_, name, locale, default)
        locales[name] = locales[name] or setmetatable({}, {__index=function(_, key) return key end})
        if default or locale == GetLocale() then return locales[name] end
    end,
    GetLocale = function(_, name) return assert(locales[name]) end,
}
local function FillDefaults(values, defaults)
    for key, value in pairs(defaults) do
        if key ~= "*" and key ~= "**" then
            if type(value) == "table" then values[key] = values[key] or {}; FillDefaults(values[key], value)
            elseif values[key] == nil then values[key] = value end
        end
    end
    local wildcard = defaults["**"] or defaults["*"]
    if wildcard ~= nil then
        if type(wildcard) == "table" then
            for key, value in pairs(values) do
                if type(value) == "table" and (defaults["**"] or defaults[key] == nil) then FillDefaults(value, wildcard) end
            end
        end
        setmetatable(values, {__index=function(self, key)
            if type(wildcard) == "table" then
                local value = {}
                FillDefaults(value, wildcard)
                rawset(self, key, value)
                return value
            end
            return wildcard
        end})
    end
end
local function Database(raw, defaults, profileName)
    raw.profiles = raw.profiles or {}
    raw.profiles[profileName] = raw.profiles[profileName] or {}
    FillDefaults(raw.profiles[profileName], defaults.profile or {})
    local db = {profile=raw.profiles[profileName], raw=raw, callbacks={}}
    db.RegisterCallback = function(owner, event, method)
        db.callbacks[event] = type(method) == "function" and method or function() owner[method](owner) end
    end
    function db:RegisterNamespace(name, namespaceDefaults)
        raw.namespaces = raw.namespaces or {}; raw.namespaces[name] = raw.namespaces[name] or {}
        return Database(raw.namespaces[name], namespaceDefaults, profileName)
    end
    return db
end
libraries["AceDB-3.0"] = { New = function(_, raw, defaults, profileName)
    return Database(raw, defaults, profileName == true and "Default" or profileName)
end }
libraries["AceDBOptions-3.0"] = { GetOptionsTable = function() return {type="group",name="配置",args={}} end }
local configCallbacks = {}
libraries["AceConfigRegistry-3.0"] = {
    RegisterOptionsTable = function(_, name, options) mock.options[name] = options end,
    RegisterCallback = function(owner, event, method) configCallbacks[owner] = method end,
    NotifyChange = function(_, app)
        for owner, method in pairs(configCallbacks) do owner[method](owner, "ConfigTableChange", app) end
    end,
}
local dialog = { OpenFrames = {}, BlizOptions = {} }
function dialog:Open(name, container)
    if container then
        mock.customContainers = mock.customContainers or {}
        mock.customContainers[name] = container
        container:SetUserData("appName", name)
        container.opens = (container.opens or 0) + 1
        return
    end
    self.OpenFrames[name] = {frame=CreateFrame("Frame")}
    self.OpenFrames[name].frame:Show()
end
function dialog:Close(name) self.OpenFrames[name] = nil end
function dialog:SelectGroup(name, tab) mock.selectedTab = tab end
function dialog:SetDefaultSize() end
libraries["AceConfigDialog-3.0"] = dialog
libraries["AceGUI-3.0"] = { Create = function(_, kind)
    assert(kind == "SimpleGroup")
    local container = {frame=CreateFrame("Frame"),userdata={}}
    function container:SetUserData(key, value) self.userdata[key] = value end
    function container:GetUserData(key) return self.userdata[key] end
    function container:GetUserDataTable() return self.userdata end
    function container:SetAutoAdjustHeight(value) self.autoHeight = value end
    function container:SetLayout(value) self.layout = value end
    function container:SetWidth(value) self.frame:SetWidth(value) end
    function container:SetHeight(value) self.frame:SetHeight(value) end
    function container:ReleaseChildren() self.released = true end
    function container:IsVisible() return self.frame:IsVisible() end
    return container
end }
local function Addon(name)
    local addon = {name=name, modules={}, enabled=true, hooks={}}
    function addon:NewModule(moduleName) local module = Addon(moduleName); self.modules[moduleName] = module; return module end
    function addon:GetModule(moduleName) return self.modules[moduleName] end
    function addon:IterateModules() return pairs(self.modules) end
    function addon:SetEnabledState(value) self.enabled = value end
    function addon:IsEnabled() return self.enabled end
    function addon:EnableModule(moduleName)
        local module=self.modules[moduleName]
        if not module.enabled then module.enabled=true; module:OnEnable() end
    end
    function addon:DisableModule(moduleName)
        local module=self.modules[moduleName]
        if module.enabled then module.enabled=false; module:OnDisable() end
    end
    addon.IsHooked = function() return false end
    addon.SecureHook, addon.Unhook, addon.UnregisterAllEvents = Noop, Noop, Noop
    return addon
end
libraries["AceAddon-3.0"] = {
    NewAddon = function(_, name) local addon=Addon(name); addons[name]=addon; return addon end,
    GetAddon = function(_, name) return addons[name] end,
}
local lifecycle = CreateFrame("Frame")
lifecycle:RegisterEvent("ADDON_LOADED")
lifecycle:SetScript("OnEvent", function(self, _, name)
    if name ~= "wow_tools" then return end
    for _, addon in pairs(addons) do
        addon:OnInitialize()
        for _, module in addon:IterateModules() do module:OnInitialize() end
        addon:OnEnable()
        for _, module in addon:IterateModules() do if module.enabled then module:OnEnable() end end
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

function mock.LoadXML(path)
    local file = assert(io.open(path)); local xml = file:read("*a"); file:close()
    local directory = path:match("^(.*[/\\])")
    for script in xml:gmatch('<Script file="([^"]+)"') do dofile(directory .. script) end
    for kind, attributes in xml:gmatch("<(%w+)(.-)>") do
        local name = attributes:match('name="([^"]+)"')
        if (kind == "Button" or kind == "Frame") and name and not attributes:find('virtual="true"',1,true) then
            CreateFrame(kind, name, _G[attributes:match('parent="([^"]+)"')] or UIParent)
        end
    end
    BFChannelMuteButtonMute, ChannelFilterMuteButtonMute = CreateFrame("Frame"), CreateFrame("Frame")
    BFCIconFrameRaidersButton_OnLoad(BFCIconFrameRaidersButton)
end
function mock.LoadAddonFile(path)
    -- Embedded libraries have a separate dependency API check.
    if path:find("/bigfoot_channel/Libs/", 1, true) then return end
    if path:find("/ls_toasts/", 1, true) then
        if not mock.toasts then mock.toasts = dofile((TEST_ROOT or ".") .. "/addon/tests/LsToasts.Mock.lua")(mock) end
        mock.toasts.LoadXML(path)
        return
    end
    if path:match("%.xml$") then mock.LoadXML(path) else dofile(path) end
end
return mock
