-- Initialize each client source against its API contract and typed UI methods.
local flavor = TEST_FLAVOR or "forerver"
local root = TEST_ROOT or "."
local addon = root .. "/addon/"..flavor.."/wow_tools/"
local frames, names, widgets = {}, {}, {}
local scale, width, height, dead, free = 0.7, 1920, 1080, false, 10
local pole, enchants, channelName, channelID, castName, castID = true, {}, nil, nil, nil, nil
local apiFailure, cvarWrites, menuEntries = false, 0, {}
local playerFaction = "Horde"
local targetGUID, targetName, interactable, interactCVar = nil, "模拟鱼漂", false, "3"
local guidFailure, interactFailure = false, false
local messages = {}
local gcValues, gcCalls = { setpause = 350, setstepmul = 250 }, 0
function collectgarbage(option, value)
    if option == "count" then return 1024 end
    assert(gcValues[option] and type(value) == "number", "Unexpected GC operation")
    gcCalls = gcCalls + 1
    local previous = gcValues[option]
    gcValues[option] = value
    return previous
end
function date() return "12:00:00" end
function UnitFactionGroup(unit)
    assert(type(unit) == "string" and unit:lower() == "player", "Unexpected faction-query unit")
    return playerFaction
end
function InCombatLockdown() return false end
function ClearOverrideBindings() end
function SetOverrideBindingClick() end
local secret = setmetatable({}, {
    __eq = function() error("Compared a restricted value") end,
    __tostring = function() error("Printed a restricted value") end,
})
function issecretvalue(value) return rawequal(value, secret) end
local VisibilityChanged
local function widget(name, parent, kind)
    local object = { scripts = {}, events = {}, textures = {}, shown = true, text = "", enabled = true, mockParent = parent, kind = kind }
    function object:SetAttribute() end
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:HookScript(event, callback)
        local previous = self.scripts[event]
        self.scripts[event] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function object:RegisterEvent(event) self.events[event] = true end
    function object:UnregisterEvent(event) self.events[event] = nil end
    function object:CreateTexture()
        local texture = widget(nil, self, "Texture")
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function object:CreateMaskTexture() return widget() end
    function object:AddMaskTexture(mask) self.mask=mask end
    function object:RemoveMaskTexture(mask) if self.mask==mask then self.mask=nil end end
    function object:SetTextureSliceMargins(...) self.sliceMargins={ ... } end
    function object:ClearTextureSlice() self.sliceMargins=nil end
    function object:CreateFontString() return widget(nil, self, "FontString") end
    function object:GetParent() return self.mockParent end
    function object:SetFrameStrata(value) self.strata = value end
    function object:GetFrameStrata()
        return self.strata or (self.mockParent and self.mockParent:GetFrameStrata()) or "MEDIUM"
    end
    function object:IsVisible() return self.shown and (not self.mockParent or self.mockParent:IsVisible()) end
    function object:SetParent(parent)
        local visible = self:IsVisible()
        self.mockParent = parent
        VisibilityChanged(self, visible)
    end
    function object:GetEffectiveScale() return scale end
    function object:GetCenter() return 960, 540 end
    function object:SetSize(w, h) self.width, self.height = w, h end
    function object:GetWidth() return self.fill and self.fill:GetWidth() or self.width or 140 end
    function object:GetHeight() return self.fill and self.fill:GetHeight() or self.height or 140 end
    function object:SetWidth(value) self.width = value end
    function object:SetHeight(value) self.height = value end
    function object:SetAllPoints(target) self.fill = target or self.mockParent end
    function object:SetColorTexture(...) self.color = { ... } end
    function object:SetVertexColor(...) self.vertex = { ... } end
    function object:SetAlpha(value) self.alpha = value end
    function object:GetAlpha() return self.alpha or 1 end
    for _, state in ipairs({"Normal","Pushed","Highlight","Disabled"}) do
        object["Get"..state.."Texture"] = function(self) return self[state.."Texture"] end
        object["Set"..state.."Texture"] = function(self, texture) self[state.."Texture"] = texture end
    end
    function object:SetPoint(...) self.point = { ... } end
    function object:GetPoint() return "LEFT", nil, "CENTER", -20, 0 end
    function object:SetText(value)
        if self.text == value then return end
        self.text = value
        if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
    end
    function object:GetText() return self.text end
    function object:GetFontString()
        self.buttonText = self.buttonText or widget(nil, self, "FontString")
        return self.buttonText
    end
    function object:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
    function object:GetFont() return "mock-font", 12, "" end
    if kind == "FontString" then
        function object:GetStringHeight() return 36 end
        function object:GetStringWidth() return #self.text * 8 end
        function object:SetWordWrap(value) self.wordWrap = value end
        function object:SetMaxLines(value) self.maxLines = value end
        function object:SetDrawLayer() end
        function object:SetShadowColor() end
        function object:SetShadowOffset() end
    elseif kind == "Texture" then
        function object:SetHorizTile() end
        function object:SetVertTile() end
        function object:SetRotation(value) self.rotation = value end
    elseif kind == "StatusBar" then
        function object:SetStatusBarTexture(texture)
            self.statusTexture = widget(nil, self, "Texture")
            self.statusTexture:SetTexture(texture)
        end
        function object:GetStatusBarTexture() return self.statusTexture end
        function object:SetStatusBarColor(...) self.statusColor = {...} end
    elseif kind == "EditBox" then
        function object:GetNumLines()
            local _, newlines = self.text:gsub("\n", "")
            return self.mockLineCount or newlines + 1
        end
        function object:GetSpacing() return self.spacing or 0 end
        function object:HasFocus() return false end
        function object:SetTextInsets(...) self.textInsets = {...} end
    elseif kind == "ScrollFrame" then
        function object:UpdateScrollChildRect() self.scrollRectUpdated = true end
    end
    function object:SetEnabled(value) self.enabled = value end
    function object:Enable() self.enabled = true end
    function object:Disable() self.enabled = false end
    function object:GetChecked() return self.checked end
    function object:SetNumeric(value) self.numeric = value end
    function object:SetChecked(value) self.checked = value end
    function object:Hide() local visible=self:IsVisible(); self.shown=false; VisibilityChanged(self,visible) end
    function object:Show() local visible=self:IsVisible(); self.shown=true; VisibilityChanged(self,visible) end
    function object:IsShown() return self.shown end
    function object:SetShown(value) if value then self:Show() else self:Hide() end end
    function object:GetFrameLevel() return 1 end
    function object:SetValue(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function object:GetValue() return self.value end
    function object:GetThumbTexture() self.thumb = self.thumb or widget(nil, self); return self.thumb end
    function object:IsEnabled() return self.enabled end
    function object:IsMouseOver() return false end
    function object:SetupMenu(generator) self.generator = generator end
    function object:GenerateMenu()
        self.generator(self, {SetScrollMode=function() end, CreateRadio=function() end})
    end
    function object:SetDefaultText(text) self.defaultText = text end
    function object:CloseMenu() self.menuClosed = true end
    local harmless = {
        "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetHitRectInsets", "SetFrameLevel", "SetScale", "SetButtonState", "LockHighlight", "UnlockHighlight", "SetClampedToScreen", "SetMovable", "EnableMouse",
        "RegisterForDrag", "RegisterForClicks", "SetHighlightTexture", "SetTexture",
        "ClearAllPoints", "SetFont", "SetJustifyH", "SetAutoFocus",
        "SetMaxLetters", "ClearFocus", "SetScrollChild", "StartMoving", "StopMovingOrSizing", "SetMultiLine", "SetFontObject", "SetBlendMode", "SetTexCoord",
        "SetOrientation", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture", "EnableMouseWheel", "SetTextColor",
        "SetPropagateKeyboardInput", "EnableKeyboard",
    }
    for _, method in ipairs(harmless) do object[method] = function() end end
    if kind == "Texture" then
        function object:SetTexture(value) self.texture = value end
        function object:GetTexture() return self.texture end
        function object:SetDesaturated(value) self.desaturated = value end
        function object:SetTexCoord(...) self.coordinates = {...} end
        function object:GetTexCoord() return unpack(self.coordinates or {0, 1, 0, 1}) end
        function object:GetVertexColor() return unpack(self.vertex or {1, 1, 1, 1}) end
    end
    widgets[#widgets + 1] = object
    object.lastVisible = object:IsVisible()
    if name then names[name] = object end
    return object
end
VisibilityChanged = function()
    local changes = {}
    for _, object in ipairs(widgets) do
        local visible = object:IsVisible()
        if visible ~= object.lastVisible then
            object.lastVisible = visible
            changes[#changes + 1] = {object=object, event=visible and "OnShow" or "OnHide"}
        end
    end
    for _, change in ipairs(changes) do
        local callback = change.object.scripts[change.event]
        if callback then callback(change.object) end
    end
end
function CreateFrame(kind, name, parent, template)
    assert(kind ~= "OffScreenFrame", "Portraits must not create the retired protected snapshot frame")
    assert(template ~= "UIDropDownMenuTemplate", "Forever still depends on legacy dropdown templates")
    local object = widget(name, parent, kind)
    object.template = template
    if template == "MaximizeMinimizeButtonFrameTemplate" then
        object.MaximizeButton = widget(nil, object, "Button")
        object.MinimizeButton = widget(nil, object, "Button")
    end
    if template == "UICheckButtonTemplate" then object.Text = widget(nil, object, "FontString") end
    if template == "MinimalTabTemplate" then
        object.Text = widget(nil, object, "FontString")
        function object:SetSelected(value) self.selected = value end
        function object:IsSelected() return self.selected == true end
        object:SetScript("OnClick", function(self) self.nativeClicks = (self.nativeClicks or 0) + 1 end)
    end
    if template == "BasicFrameTemplateWithInset" then
        object.TitleText = widget(nil, object, "FontString")
        object.Bg = widget(nil, object, "Texture")
        object.InsetBg = widget(nil, object, "Texture")
        object.TitleBg = widget(nil, object, "Texture")
        object.TopTileStreaks = widget(nil, object, "Texture")
    end
    frames[#frames + 1] = object
    return object
end
function CreateRadioButtonGroup()
    local group = { buttons = {} }
    function group:AddButton(button)
        self.buttons[#self.buttons + 1] = button
        button.selectionGroup = self
        local index = #self.buttons
        button:HookScript("OnClick", function() self:SelectAtIndex(index) end)
    end
    function group:SelectAtIndex(index)
        assert(self.buttons[index], "Radio selection is outside the registered tabs")
        for buttonIndex, button in ipairs(self.buttons) do
            button:SetSelected(buttonIndex == index)
        end
    end
    return group
end
UIParent, Minimap, FramerateFrame, GameTooltip = widget(), widget(), widget(), widget()
ItemRefTooltip = widget()
FramerateLabel = flavor=="titan" and widget() or nil
function GameTooltip:SetOwner(owner, anchor)
    self.owner, self.anchor, self.lines = owner, anchor, {}
end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:IsOwned(owner) return self.owner == owner end
function GameTooltip:IsForbidden() return self.forbidden == true end
function GameTooltip:AddLine(text)
    self.lines = self.lines or {}
    self.lines[#self.lines + 1] = text
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
YES, NO = "Yes", "No"
BackdropTemplateMixin = {}
local registeredCategories, addonCategories = {}, {}
Settings = { RegisterCanvasLayoutCategory = function(frame, name)
    local category = {frame=frame,name=name}
    registeredCategories[#registeredCategories + 1] = category
    return category
end, RegisterAddOnCategory = function(category) addonCategories[#addonCategories + 1] = category end }
function GetMinRenderScale() return 0.5 end
function GetMaxRenderScale() return 2 end
local resampleCVars = {ResampleQuality = "3", ResampleAlwaysSharpen = "0", ResampleSharpness = "0.2", RenderScale = "1"}
local textureCVars = {
    graphicsTextureResolution = flavor == "titan" and "1" or "2", textureFilteringMode = "5",
    worldBaseMip = "0", terrainMipLevel = "0", componentTextureLevel = "0", useHighResTextures = "1",
}
local allocationCVars = {
    componentTexCacheSize = "32", componentTexLoadLimit = "16", componentCompress = "1",
    GxAllowCachelessShaderMode = "0", ThreadPoolPerThreadAllocator = "1",
    FrameBufferCacheForceNoHeaps = "0", worldPreloadHighResTextures = "1",
}
C_CVar = { GetCVar = function(key)
    assert(type(key) == "string", "CVar getter requires a name")
    return key == "softTargetInteract" and interactCVar or resampleCVars[key] or textureCVars[key] or allocationCVars[key]
end, SetCVar = function(key, value)
    assert(type(key) == "string" and type(value) == "string", "CVar setter requires name and value strings")
    cvarWrites = cvarWrites + 1
end }
MenuUtil = { CreateContextMenu = function(owner, generator)
    menuEntries = {}
    local description = {
        CreateTitle = function() end,
        CreateCheckbox = function(_, title, isSelected, onSelect)
            menuEntries[#menuEntries + 1] = { title = title, isSelected = isSelected, onSelect = onSelect }
        end,
    }
    generator(owner, description)
end }
Enum = { WeaponSlot = {MainHand = 0}, ItemEnchantType = {Permanent = 1, Temporary = 2, Imbue = 3} }
local trainerSpellPostCall
local itemTooltipPostCalls = {}
if flavor == "forerver" then
    Enum.TooltipDataType = {Item = 0, Spell = 1}
    TooltipDataProcessor = {AddTooltipPostCall = function(dataType, callback)
        if dataType == Enum.TooltipDataType.Item then
            itemTooltipPostCalls[#itemTooltipPostCalls + 1] = callback
            return
        end
        if dataType ~= Enum.TooltipDataType.Spell then return end
        assert(not trainerSpellPostCall and type(callback) == "function", "Invalid spell tooltip post-call binding")
        trainerSpellPostCall = callback
    end}
    function GameTooltip:GetProcessingTooltipInfo() return self.processingInfo end
    function GameTooltip:GetPrimaryTooltipInfo() return self.primaryInfo end
    function GameTooltip:GetPrimaryTooltipData() return self.primaryInfo and self.primaryInfo.tooltipData end
end
ItemLocation = { CreateFromEquipmentSlot = function(_, slot) assert(slot == 16); return {slot = slot} end }
C_Item = {
    GetItemInfo = function(itemID) return "物品" .. itemID, "item:" .. itemID, 1 end,
    GetItemIconByID = function() return 134400 end,
    GetItemID = function(location) assert(location.slot == 16); return 1 end,
    GetItemInfoInstant = function() return 1, nil, nil, nil, nil, 2, pole and 20 or 7 end,
    GetWeaponEnchantInfo = function(slot)
        assert(flavor~="titan", "Titan used Forever's namespaced enchant list")
        assert(slot == Enum.WeaponSlot.MainHand, "Wrong weapon-slot enumeration")
        if apiFailure then error("Unavailable enchant scan") end
        return enchants
    end,
}
C_Spell = { GetSpellName = function() return "Fishing" end }
C_Map = {
    GetMapInfo = function(uiMapID)
        assert(type(uiMapID) == "number", "Map info requires a numeric UI map ID")
        return {name = "Zone " .. uiMapID}
    end,
    GetAreaInfo = function(areaID)
        assert(type(areaID) == "number", "Area info requires a numeric area ID")
        return "Area " .. areaID
    end,
}
function GetBuildInfo() return flavor == "titan" and "3.80.2" or "1.60.1", "70790" end
local localizedNameReads = 0
LibQuestieDB = {Npc = {Get = function(id, field)
    if field == "zoneID" then return id == 9990001 and 14 or nil end
    assert(field == "name", "Localized NPC adapter requested the wrong field")
    localizedNameReads = localizedNameReads + 1
    return id == 6 and "狗头人歹徒" or nil
end}}
function GetInventoryItemLink(unit, slot)
    assert(unit=="player" and slot==16)
    return pole and "fishing-pole" or "sword"
end
function GetWeaponEnchantInfo()
    assert(flavor=="titan", "Forever used Titan's legacy enchant tuple")
    if apiFailure then error("Unavailable enchant scan") end
    for _, enchant in ipairs(enchants) do
        if enchant.enchantType==2 then return enchant.hasEnchant, enchant.timeLeft end
    end
    return false, nil
end
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function() return free, 0 end,
}
if flavor == "forerver" then Enum.BagIndex = {ReagentBag = 5} end
function UnitIsDeadOrGhost() return dead end
local ghost=false
UnitIsDead=UnitIsDeadOrGhost
function UnitIsGhost() return ghost end
function UnitClass() return "战士", "WARRIOR", 1 end
function GetPhysicalScreenSize() return width, height end
function UnitChannelInfo() return channelName, nil, nil, nil, nil, nil, nil, channelID end
function UnitCastingInfo() return castName, nil, nil, nil, nil, nil, "cast-guid", false, castID end
function UnitGUID(unit)
    assert(unit == "softinteract", "Wrong interaction target")
    if guidFailure then error("Unavailable GUID") end
    return targetGUID
end
function UnitIsInteractable(unit)
    assert(unit == "softinteract", "Wrong interactability target")
    if interactFailure then error("Unavailable interaction") end
    return interactable
end
function UnitName(unit) assert(unit == "softinteract"); return targetName end
function UnitExists() error("Do not reject GameObjects with UnitExists") end
-- Native pet contracts are present in both client sources.
function HasPetUI() return false, false end
function IsAltKeyDown() return false end
function GetPetExperience() return 0, 1000 end
function UnitLevel(unit)
    assert(unit == "player" or unit == "pet", "Unexpected pet-level unit")
    return unit == "player" and 60 or 59
end
if flavor == "titan" then
    function GetMaxLevelForLatestExpansion() return 80 end
else
    function GetMaxPlayerLevel() return 60 end
end
local chatMock = dofile(root .. "/addon/tests/BigFootChannel.Mock.lua")
function C_Timer.NewTicker(seconds, callback)
    assert(type(seconds) == "number" and seconds > 0 and type(callback) == "function")
    return {Cancel = function() end}
end
local originalHook = hooksecurefunc
function hooksecurefunc(target, method, callback)
    if type(target) == "table" and (method == "SetBarText" or method == "Init" or method == "Invalidate") then
        local original = target[method]
        assert(type(original) == "function", "Post-hooks require a native method")
        target[method] = function(...) original(...); callback(...) end
    else originalHook(target, method, callback) end
end
local recipeHoverEvent = "Professions.RecipeListOnEnter"
local nativeRecipeHover
local function CreateNativeProfessionForm()
    ProfessionsFrame = CreateFrame("Frame", nil, UIParent)
    local page = CreateFrame("Frame", nil, ProfessionsFrame)
    ProfessionsFrame.CraftingPage = page
    page.RecipeList = CreateFrame("Frame", nil, page)
    local form = CreateFrame("Frame", nil, page)
    page.SchematicForm = form
    form:SetSize(360, 484)
    form.currentRecipeInfo = {recipeID = 2159}
    form.TrackRecipeCheckbox = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
    local checkbox = form.TrackRecipeCheckbox
    checkbox.nativeClick = function(self) self:SetChecked(not self:GetChecked()) end
    checkbox:SetScript("OnClick", checkbox.nativeClick)
    function form:GetRecipeInfo() return self.currentRecipeInfo end
    function form:Init(info)
        self.currentRecipeInfo = info
        self.TrackRecipeCheckbox:SetShown(info ~= nil)
    end
    return form
end
if flavor == "forerver" and TEST_PROFESSIONS_PRELOADED then CreateNativeProfessionForm() end
local xpText = widget(nil, nil, "FontString")
local xpBar = {OverlayFrame = {Text = xpText}}
function xpBar:SetBarText(text) self.OverlayFrame.Text:SetText(text) end
function xpBar:UpdateCurrentText() self:SetBarText("100 / 1000") end
StatusTrackingBarInfo = {BarsEnum = {Experience = 4}}
StatusTrackingBarManager = {barContainers = {{bars = {[4] = xpBar}}}}
function GetXPExhaustion() return 12345 end
function UnitXP(unit) assert(unit == "player"); return 100 end
function UnitXPMax(unit) assert(unit == "player"); return 1000 end
for line in io.lines(addon .. "wow_tools.toc") do
    if line:match("%.lua%s*$") or line:match("%.xml%s*$") then
        chatMock.LoadAddonFile(addon .. line:gsub("\\", "/"):gsub("%s+$", ""))
    end
end
function GameTooltip:SetText(text) self.text = text end
EventRegistry = EventRegistry or {}
function EventRegistry:RegisterCallback(event, callback, recipient)
    if event ~= recipeHoverEvent then return end
    assert(not nativeRecipeHover, "PRR registered the native recipe hover event twice")
    assert(type(callback) == "function" and type(recipient) == "table", "Native callback registry signature mismatch")
    nativeRecipeHover = function(row, info) callback(recipient, row, {recipeInfo = info}) end
end
-- SavedVariables become available after the TOC scripts and before ADDON_LOADED.
if TEST_PLUGIN_LANGUAGE then
    wowDetectorDB = {prr = {db = {settings = {language = TEST_PLUGIN_LANGUAGE}}}}
    wowToolsCharacterSettings = {raynnaBestiary = {db = {language = TEST_PLUGIN_LANGUAGE}}}
end
if TEST_PRR_AUTO_LANGUAGE then
    wowDetectorDB = {prr = {languageDefaultApplied = true, db = {settings = {language = "auto"}}}}
end
if TEST_THIRD_PARTY_DISABLED then
    wowDetectorDB = {thirdPartyAddons = {bigfoot_channel = false, ls_toasts = false, forever_faces = false, better_vendor_ui = false, pet_xp_bar = false,
        raynna_bestiary = false, prr = false}}
end
wowDetectorDB = wowDetectorDB or {}
wowDetectorDB.autoShop = {[159] = 1}
wowDetectorDB.autoShopExitOnPurchase = true
for _, frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "wow_tools") end
end
assert(WoWTools and type(WoWTools.modules) == "table", "Addon namespace failed to initialize")
for _, name in ipairs({"wowDetector", "fight_detector", "pet_tamer", "button_style", "ui_addons"}) do
    assert(type(WoWTools.modules[name]) == "table", "Missing module export " .. name)
end
assert(WoWTools.settings and type(WoWTools.settings.Open) == "function", "Missing settings interface")
assert(WoWTools.settings.categories[3].selected == "third_party",
    "Plugin list must be the initial third-party tab")
if flavor == "forerver" then
    local bestiary, prr = WoWTools.raynnaBestiary, WoWTools.prr
    assert(bestiary == WoWTools.modules.raynna_bestiary and prr == WoWTools.modules.prr,
        "Bestiary/PRR module namespaces are not isolated")
    assert(bestiary.sourceVersion == "2.4.8" and prr.sourceVersion == "1.6.0", "Adopted source versions differ")
    if TEST_THIRD_PARTY_DISABLED then
        assert(not bestiary.db and not bestiary.BuildBestiary and not RaynnaBestiaryAPI,
            "Disabled Bestiary initialized its runtime")
        assert(not prr.db and not prr.Events and not prr.ready, "Disabled PRR initialized its runtime")
        assert(not trainerSpellPostCall, "Disabled PRR registered the trainer tooltip post-call")
        assert(not nativeRecipeHover and (not ProfessionsFrame
            or not ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox.prrSkillRange),
            "Disabled PRR attached its native crafting skill display")
    else
        assert(bestiary.db == wowToolsCharacterSettings.raynnaBestiary.db,
            "Bestiary character settings binding failed")
        assert(prr.db == wowDetectorDB.prr.db and prr.ready, "PRR account settings or options binding failed")
        local expectedLanguage = TEST_PLUGIN_LANGUAGE or "zh"
        assert(prr.db.settings.language == (TEST_PRR_AUTO_LANGUAGE and "auto" or expectedLanguage),
            "PRR language default/persistence binding failed")
        assert(prr.Constants.ADDON_TITLE == (expectedLanguage == "zh" and "PRR 配方用途" or "PRR: Professions, Recipes, Reagents"),
            "PRR title localization failed")
        assert(type(prr.Components.ItemTooltip.Fill) == "function"
            and type(prr.Components.GatherTooltip.FillNode) == "function"
            and type(prr.Dataflows.Disenchant.Results) == "function",
            "PRR tooltip component load order failed")
        local options = chatMock.options.WoWToolsPRR().args
        assert(options.gathering.args.recordGathering.type == "toggle"
            and options.profession.args.showSkillZones.type == "toggle",
            "PRR 1.6 options did not bind to the shared settings canvas")
        assert(type(bestiary.AdvanceHoverLoot) == "function", "Bestiary progressive source interface did not load")
        assert(prr.GameData.RememberLearnedRecipe(2149)
            and prr.GameData.IsRecipeKnown(2149), "PRR learned recipe event data binding failed")
        local recipeRow = prr.Components.RecipeRow.Create(CreateFrame("Frame"), function() end)
        prr.Components.RecipeRow.Fill(recipeRow, {
            spellID = 2149, item = 2302, recipeItem = 2406, count = 1,
            reagents = {{2318, 2}, {2320, 1}},
        }, 2318)
        for _, icon in ipairs({recipeRow.result, recipeRow.recipeItem}) do
            local marker = assert(icon.prrKnownRecipe, "PRR learned icon marker binding failed")
            assert(marker.gray.fill == icon.icon and marker.gray.desaturated
                and marker.gray:GetTexture() == icon.icon:GetTexture(), "PRR learned icon grayscale binding failed")
            assert(marker.check:GetTexture() == 136814 and marker.check:IsShown(),
                "PRR learned icon uses a different check mark from Vendor")
        end
        prr.Components.RecipeRow.Fill(recipeRow, {
            spellID = 2152, item = 2303, count = 1, reagents = {},
        }, 2318)
        assert(not recipeRow.result.prrKnownRecipe.check:IsShown()
            and not recipeRow.result.prrKnownRecipe.gray:IsShown()
            and not recipeRow.recipeItem.prrKnownRecipe.check:IsShown(), "PRR recipe row retained an old marker binding")
        assert(type(chatMock.options.WoWToolsPRR) == "function", "PRR options were not registered")
        local options = chatMock.options.WoWToolsPRR()
        assert(options.args.general and options.args.tooltip and options.args.language,
            "PRR embedded options lost pages")
        local postCallCount = #itemTooltipPostCalls
        bestiary.events.scripts.OnEvent(bestiary.events, "PLAYER_LOGIN")
        assert(#itemTooltipPostCalls == postCallCount + 1, "Bestiary item tooltip post-call is not registered")
        local bestiaryItemPostCall = itemTooltipPostCalls[#itemTooltipPostCalls]
        assert(bestiary.ready and type(bestiary.OpenBrowser) == "function", "Bestiary initialization contract failed")
        assert(bestiary.language == expectedLanguage and bestiary.db.language == expectedLanguage,
            "Bestiary language default/persistence binding failed")
        assert(bestiary.Text("Item sources") == (expectedLanguage == "zh" and "物品来源" or "Item sources"),
            "Bestiary text resource binding failed")
        local nameReadsBefore = localizedNameReads
        local name = bestiary.EntityName("Npc", 6, "Kobold Vermin")
        assert(name == (expectedLanguage == "zh" and "狗头人歹徒" or "Kobold Vermin"),
            "Bestiary localized NPC name API binding failed")
        bestiary.EntityName("Npc", 6, "Kobold Vermin")
        assert(localizedNameReads == nameReadsBefore + (expectedLanguage == "zh" and 1 or 0),
            "Bestiary repeated its localized name lookup")
        assert(bestiary.Text("Skinning") == (expectedLanguage == "zh" and "剥皮" or "Skinning"),
            "Bestiary skinning text resource binding failed")
        assert(bestiary.SkinningReference.creatures[113][1] == 113,
            "Bestiary skinning data dependency/load order failed")
        assert(bestiary.ReferenceMonster(250660).drops[271204]
            and bestiary.ReferenceItem(271204).drops[250660],
            "Bestiary Forever dungeon source binding failed")
        local hammer = bestiary.ReferenceItem(285289)
        local observedVendor = assert(hammer.drops["vendor:248197"], "Bestiary omitted an observed recipe vendor")
        local referenceVendor = assert(hammer.drops["vendor:256730"], "Bestiary omitted a reference recipe vendor")
        assert(hammer.recipeItem and observedVendor.kind == "Vendor" and observedVendor.npcID == 248197
            and observedVendor.details == "Area 17"
            and observedVendor.source == "Efficient Games Forever vendor observations"
            and referenceVendor.source == "DungeonsForeverProf Forever vendor reference",
            "Bestiary recipe vendor identity, area or provenance binding failed")
        assert(bestiary.ReferenceItem(16382).drops["vendor:5815"].source
                == "Efficient Games earlier Forever vendor observations"
            and bestiary.ReferenceItem(277716).drops["vendor:3168"].source == "QuestieDB Forever metadata",
            "Bestiary earlier and QuestieDB recipe vendor provenance binding failed")
        local spawn = bestiary.SourceLocations(6)[1]
        assert(spawn and type(spawn.area) == "number" and type(spawn.x) == "number"
            and type(spawn.y) == "number" and type(bestiary.ShowSourceLocation) == "function",
            "Bestiary spawn data and map interface binding failed")
        local leatherSources = bestiary.ReferenceItem(2318).drops
        local skinningSource = assert(leatherSources["skinning:113"], "Bestiary item-to-skinning query binding failed")
        assert(skinningSource.kind == "Skinning" and skinningSource.npcID == 113
            and type(skinningSource.rate) == "number" and skinningSource.rate > 0 and skinningSource.rate <= 100,
            "Bestiary skinning source lost its NPC identity or probability contract")
        assert(not leatherSources[113] and not bestiary.ReferenceItem(769).drops[113].kind,
            "Bestiary skinning sources collided with corpse loot")
        local boar = bestiary.ReferenceMonster(113)
        assert(boar.skinning[2318].kind == "Skinning" and boar.skinning[2318].link == "item:2318"
            and boar.skinning[2318].rate == skinningSource.rate and boar.drops[769] and not boar.drops[2318],
            "Bestiary creature skinning query lost its independent loot table or probability units")
        local detail = bestiary.detailFrame
        local originalCursor = GetCursorPosition
        local originalWidth, originalHeight = UIParent.GetWidth, UIParent.GetHeight
        local originalParentScale = UIParent.GetEffectiveScale
        local originalSetScale, originalEffectiveScale = detail.SetScale, detail.GetEffectiveScale
        local cursorX, cursorY, frameScale = 600, 540, 1
        local viewportWidth, viewportHeight, parentScale = width, height, scale
        function GetCursorPosition() return cursorX, cursorY end
        function UIParent:GetWidth() return viewportWidth / parentScale end
        function UIParent:GetHeight() return viewportHeight / parentScale end
        function UIParent:GetEffectiveScale() return parentScale end
        function detail:SetScale(value) frameScale = value end
        function detail:GetEffectiveScale() return parentScale * frameScale end
        local raptor = prr.Dataflows.RecipeIndex.Get(1250153)
        assert(raptor.item == 250076 and raptor.recipeItem == 250184,
            "PRR Raptor Rouladen output and recipe IDs changed")
        local originalAlt, originalContainerID = IsAltKeyDown, C_Container.GetContainerItemID
        function IsAltKeyDown() return true end
        function C_Container.GetContainerItemID(bag, slot)
            assert(bag == 0 and slot == 4, "Bestiary used the wrong native bag/slot arguments")
            return raptor.recipeItem
        end
        local produced = {type = Enum.TooltipDataType.Item, id = raptor.item, hyperlink = "item:" .. raptor.item}
        for _, request in ipairs({
            {getterName = "GetItemByID", getterArgs = {raptor.recipeItem}},
            {getterName = "GetHyperlink", getterArgs = {"|Hitem:" .. raptor.recipeItem .. ":0|h[Recipe]|h"}},
            {getterName = "GetBagItem", getterArgs = {0, 4}},
        }) do
            detail:Hide()
            request.tooltipData = produced
            GameTooltip.primaryInfo = request
            bestiaryItemPostCall(GameTooltip, {type = produced.type, id = raptor.item})
            assert(not detail:IsShown(), "An appended preview claimed the Bestiary Alt selection")
            bestiaryItemPostCall(GameTooltip, produced)
            assert(detail:IsShown() and detail.name:GetText() == "物品" .. raptor.recipeItem
                and detail.columns[1].rows[1].entry.id == 4357,
                "Bestiary did not use the primary request to show the recipe's Bloodfen Lashtail source")
        end
        detail:Hide()
        GameTooltip.primaryInfo = {getterName = "GetItemByID", getterArgs = {raptor.item}, tooltipData = produced}
        bestiaryItemPostCall(GameTooltip, produced)
        assert(detail:IsShown() and detail.name:GetText() == "物品" .. raptor.item,
            "Bestiary source lookup changed the identity of the crafted food")
        detail:Hide()
        GameTooltip.primaryInfo = nil
        IsAltKeyDown, C_Container.GetContainerItemID = originalAlt, originalContainerID
        local savedScale = bestiary.db.bestiary.scale
        local right = detail.columns[2]
        bestiary.ShowBestiary(boar, false, false)
        assert(detail:GetWidth() == 600 and right.frame:IsShown()
            and right.section:GetText() == bestiary.Text("SKINNING  /  ") .. "2"
            and right.rows[1].entry.drop.kind == "Skinning"
            and right.rows[1].detail:GetText():find("%%")
            and right.frame.point[2] == 300,
            "Bestiary two-column labels, rates, rows or parent anchors are not bound")
        for _, viewport in ipairs({{1920, 1080, 0.7}, {800, 600, 1.25}}) do
            viewportWidth, viewportHeight, parentScale = unpack(viewport)
            for _, configuredScale in ipairs({0.4, 1, 1.8}) do
                bestiary.db.bestiary.scale = configuredScale
                for _, cursor in ipairs({{8, 8}, {viewportWidth / 2, viewportHeight / 2},
                    {viewportWidth - 8, viewportHeight - 8}}) do
                    cursorX, cursorY = unpack(cursor)
                    bestiary.ShowBestiary(boar, false, false)
                    local effective = detail:GetEffectiveScale()
                    local left, top = detail.point[4] * effective, detail.point[5] * effective
                    local panelWidth, panelHeight = detail:GetWidth() * effective, detail:GetHeight() * effective
                    assert(detail.point[2] == UIParent and detail.point[3] == "BOTTOMLEFT"
                        and left >= 7.99 and left + panelWidth <= viewportWidth - 7.99
                        and top <= viewportHeight - 7.99 and top - panelHeight >= 7.99
                        and (left >= cursorX + 15.99 or left + panelWidth <= cursorX - 15.99),
                        "Bestiary cursor/screen coordinate contract fails for combined width and effective scale")
                    assert(bestiary.db.bestiary.scale == configuredScale,
                        "Bestiary cursor fitting changed the saved scale")
                end
            end
        end
        bestiary.ShowBestiary(bestiary.ReferenceMonster(6), false, true)
        assert(detail:GetWidth() == 300 and not right.frame:IsShown(),
            "Bestiary single-column creature binding retained the skinning column")
        bestiary.ShowBestiary(bestiary.ReferenceItem(2318), false, true)
        assert(detail:GetWidth() == 300 and not right.frame:IsShown()
            and detail.columns[1].rows[1].location:IsShown(),
            "Bestiary item-source row binding changed with the creature columns")
        local potion = bestiary.ReferenceItem(5642)
        assert(potion.drops["vendor:3348"] and potion.drops["vendor:12245"],
            "Bestiary failed to merge existing and observed recipe vendor records")
        local flask = bestiary.ReferenceItem(13519)
        assert(flask.drops[10363].rate and flask.drops["vendor:227853"],
            "Bestiary lost the existing drop or the supplemental recipe vendor")
        bestiary.ShowBestiary(flask, false, true)
        assert(detail.columns[1].rows[1].entry.drop.kind == "Vendor"
            and detail.columns[1].rows[1].detail:GetText() == bestiary.Text("Vendor sale")
            and detail.columns[1].rows[2].entry.id == 10363,
            "Bestiary recipe sources do not put the vendor sale ahead of a rated drop")
        detail:Hide()
        bestiary.db.bestiary.scale = savedScale
        GetCursorPosition = originalCursor
        UIParent.GetWidth, UIParent.GetHeight = originalWidth, originalHeight
        UIParent.GetEffectiveScale = originalParentScale
        detail.SetScale, detail.GetEffectiveScale = originalSetScale, originalEffectiveScale
        local recipes = prr.Dataflows.RecipeIndex.ReagentFor(2318)
        assert(type(recipes) == "table" and #recipes > 0 and recipes[1].spellID,
            "PRR indexed item recipe query contract failed")
        assert(not bestiary.CreateRecipeView and not bestiary.RefreshRecipeView and not prr.GetItemRecipes
            and not bestiary.detailFrame.recipeView and not bestiary.detailFrame.recipesTab,
            "Bestiary still loads its retired recipe integration")
        local repairedRecipe = prr.Dataflows.RecipeIndex.CraftedBy(2308)[1]
        assert(repairedRecipe.spellID == 2159 and repairedRecipe.skill == 50 and not repairedRecipe.skillReference,
            "PRR native Forever skill supplement binding failed")
        local sourceDetails = assert(repairedRecipe.details, "PRR recipe detail dependency/load order failed")
        assert(sourceDetails.trainers[1].npcID == 1385 and not sourceDetails.trainers[1].reference
            and prr.Database.Trainers[1385].name == "Brawn", "PRR named trainer identity binding failed")
        assert(prr.Database.RecipeDetails[3861].skill == 150 and not prr.Database.RecipeDetails[3861].skillReference,
            "PRR observed Forever skill requirement did not replace the conflicting borrowed value")
        assert(prr.SkillRange.Text({skill = 185, skillReference = true}):find("[185*]", 1, true),
            "PRR borrowed skill label lost its reference marker")
        prr.Components.RecipeRow.Fill(recipeRow, repairedRecipe, 2318)
        assert(recipeRow.trainers:IsShown()
            and recipeRow.trainers:GetText():find("Zone 1434 (31.7, 28.8)", 1, true)
            and not recipeRow.trainers:GetText():find("Brawn", 1, true),
            "PRR recipe row does not bind its location-only map/coordinate summary")
        assert(prr.RecipeSources.TrainerLocation(3184) == "Zone 1411 (55.5, 74.1)",
            "PRR documented Forever trainer location is missing")
        assert(prr.RecipeSources.TrainerLocation(9990001) == "Area 14",
            "PRR trainer location did not bind the Questie zone/native area fallback")
        local ruggedRecipe = prr.Dataflows.RecipeIndex.CraftedBy(8170)[1]
        assert(ruggedRecipe.skill == 225
            and prr.SkillRange.Text(ruggedRecipe):find("[225]", 1, true)
            and prr.RecipeSources.Summary(ruggedRecipe):find("Zone 1444 (74.4, 43.1)", 1, true)
            and not prr.RecipeSources.Summary(ruggedRecipe):find("1425", 1, true)
            and not prr.RecipeSources.Summary(ruggedRecipe):find("1434", 1, true),
            "PRR Rugged Leather still binds the unknown requirement or Stranglethorn trainer list")
        prr.RecipeSources.AddTooltip(GameTooltip, repairedRecipe)
        local locationLines = {}
        prr.RecipeSources.AddTooltip({AddLine = function(_, line) locationLines[#locationLines + 1] = line end}, {
            spellID = 2159,
            details = {trainers = {{npcID = 1385, reference = true}, {npcID = 1385}, {npcID = 1385}}},
        })
        assert(#locationLines == 1 and locationLines[1]:find("Zone 1434 (31.7, 28.8)", 1, true)
            and not locationLines[1]:find("Brawn", 1, true),
            "PRR location tooltip must deduplicate locations and prefer observed source provenance")
        local factionRecipe = {details = {trainers = {
            {npcID = 11097}, {npcID = 11098}, {npcID = 2836}, {npcID = 2836},
            {npcID = 11097, reference = true},
        }}}
        local text = prr.Localization.Text
        local function checkFactionLocations(faction, included, excluded)
            playerFaction = faction
            local location = prr.RecipeSources.TrainerLocation(included)
            local neutral = prr.RecipeSources.TrainerLocation(2836)
            assert(prr.RecipeSources.Summary(factionRecipe) == text("tooltip.learning_location", location)
                .. text("tooltip.other_locations", 1),
                "PRR location summary or count includes an opposing-faction trainer")
            local lines = {}
            prr.RecipeSources.AddTooltip({AddLine = function(_, line) lines[#lines + 1] = line end}, factionRecipe)
            assert(#lines == 1 and lines[1]:find(location, 1, true) and lines[1]:find(neutral, 1, true)
                and not lines[1]:find(prr.RecipeSources.TrainerLocation(excluded), 1, true),
                "PRR tooltip did not retain friendly and neutral learning locations")
            local opposing = {details = {trainers = {{npcID = excluded}, {npcID = excluded, reference = true}}}}
            assert(prr.RecipeSources.Summary(opposing) == nil, "An opposing-only recipe still shows a learning location")
            lines = {}
            prr.RecipeSources.AddTooltip({AddLine = function(_, line) lines[#lines + 1] = line end}, opposing)
            assert(#lines == 0, "An opposing-only recipe still adds tooltip locations")
        end
        checkFactionLocations("Alliance", 11097, 11098)
        checkFactionLocations("Horde", 11098, 11097)
        playerFaction = secret
        assert(prr.RecipeSources.Summary(factionRecipe) == text("tooltip.learning_location",
            prr.RecipeSources.TrainerLocation(2836)), "A restricted player faction leaked faction-specific locations")
        playerFaction = "Horde"
        local unknownTeacher = {details = {trainers = {{npcID = 9990001}}}}
        assert(prr.RecipeSources.Summary(unknownTeacher) == nil,
            "A teacher with unknown faction was treated as neutral")
        local neutralReference = {details = {trainers = {{npcID = 11557, reference = true}}}}
        assert(prr.RecipeSources.Summary(neutralReference) == text("tooltip.learning_location",
            prr.RecipeSources.TrainerLocation(11557) .. text("tooltip.reference_mark")),
            "A neutral reputation teacher lost its location or reference marker")
        local form = ProfessionsFrame and ProfessionsFrame.CraftingPage.SchematicForm
        if not form then
            form = CreateNativeProfessionForm()
            for _, frame in ipairs(frames) do
                if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "Blizzard_Professions") end
            end
        end
        local checkbox = form.TrackRecipeCheckbox
        local levels = assert(checkbox.prrSkillRange, "PRR did not bind the native recipe tracking checkbox")
        prr.Components.CraftingSkillRange.Setup()
        assert(checkbox.prrSkillRange == levels and levels:GetParent() == checkbox
            and levels.point[1] == "RIGHT" and levels.point[2] == checkbox
            and levels.point[3] == "LEFT" and levels.point[4] == -8 and not levels.wordWrap
            and checkbox:GetScript("OnClick") == checkbox.nativeClick,
            "PRR skill thresholds lost their left-side anchor, native parent or tracking click binding")
        form:Init({recipeID = 2159})
        assert(levels:IsShown() and levels:GetText() == prr.SkillRange.Text(repairedRecipe)
            and levels:GetText():find("[50]", 1, true) and levels:GetText():find("[70]", 1, true)
            and levels:GetText():find("[85]", 1, true) and levels:GetText():find("[100]", 1, true),
            "PRR native crafting selection does not bind all four colored skill thresholds")
        form:Init({recipeID = 2149})
        assert(levels:GetText() == prr.SkillRange.Text(prr.Dataflows.RecipeIndex.Get(2149)),
            "PRR native crafting selection retained a previous recipe's thresholds")
        form:Init({recipeID = 22331})
        assert(levels:GetText() == prr.SkillRange.Text(ruggedRecipe)
            and not levels:GetText():find("[?]", 1, true),
            "PRR native Rugged Leather detail does not use the corrected indexed requirement")
        form:Init({recipeID = 99999999})
        assert(not levels:IsShown() and levels:GetText() == "", "PRR unknown recipes retained old thresholds")
        form:Init({recipeID = secret})
        assert(not levels:IsShown(), "PRR native selection compared a restricted recipe ID")
        form:Init(nil)
        assert(not levels:IsShown(), "PRR empty native selection retained its skill label")
        form:Init({recipeID = 2159})
        local savedFix = prr.db.fixes[2159]
        prr.Services.RecipeFix.SetSkill(2159, 55)
        assert(levels:GetText():find("[55]", 1, true), "PRR native skill label did not bind index invalidation")
        prr.db.fixes[2159] = savedFix
        prr.Dataflows.RecipeIndex.Invalidate()
        assert(levels:GetText() == prr.SkillRange.Text(repairedRecipe),
            "PRR native skill display did not restore the indexed supplement")
        local hover = assert(nativeRecipeHover, "PRR did not register the native recipe hover event")
        local list = ProfessionsFrame.CraftingPage.RecipeList
        local scrollTarget = CreateFrame("Frame", nil, list)
        local row = CreateFrame("Button", nil, scrollTarget)
        row.Label = row:CreateFontString()
        local info = {recipeID = 2149, name = "Handstitched Leather Boots"}
        local hoverLevels = prr.SkillRange.Text(prr.Dataflows.RecipeIndex.Get(info.recipeID))
        local skillLine = text("tooltip.skill_range", hoverLevels)
        GameTooltip:Hide()
        hover(row, info)
        assert(GameTooltip:IsOwned(row) and GameTooltip.anchor == "ANCHOR_RIGHT"
            and GameTooltip:GetText() == info.name and GameTooltip.lines[1] == skillLine
            and hoverLevels ~= levels:GetText(), "Native hover must use the hovered recipe ID and native tooltip API")
        GameTooltip:SetOwner(row.Label, "ANCHOR_RIGHT")
        GameTooltip:AddLine(info.name)
        GameTooltip:Show()
        hover(row, info)
        assert(GameTooltip:IsOwned(row.Label) and #GameTooltip.lines == 2
            and GameTooltip.lines[1] == info.name and GameTooltip.lines[2] == skillLine,
            "PRR did not append the skill range to the native truncated-title tooltip")
        local otherListRow = CreateFrame("Button", nil, ProfessionsFrame)
        hover(otherListRow, info)
        hover(row, {recipeID = secret})
        hover(row, {recipeID = 99999999, name = "Unknown recipe"})
        assert(GameTooltip:IsOwned(row.Label) and #GameTooltip.lines == 2,
            "PRR decorated a foreign recipe list or a recipe without a readable skill range")
        GameTooltip:Hide()

        local trainerPostCall = assert(trainerSpellPostCall, "PRR did not bind the native spell tooltip post-call")
        local trainerLevels = prr.SkillRange.Text(prr.Dataflows.RecipeIndex.Get(9198))
        GameTooltip.lines = {"Native trainer tooltip"}
        GameTooltip.processingInfo = {getterName = "GetTrainerService"}
        trainerPostCall(GameTooltip, {id = 9198})
        assert(GameTooltip.lines[1] == "Native trainer tooltip"
            and GameTooltip.lines[2] == text("tooltip.skill_range", trainerLevels),
            "PRR trainer tooltip did not append the indexed recipe skill range")
        local trainerRecipe = prr.Dataflows.RecipeIndex.Get(1257426)
        assert(trainerRecipe.skill == 140 and trainerRecipe.yellow == 145)
        local aboveYellow = prr.Dataflows.RecipeIndex.Get(10619)
        assert(prr.SkillRange.Zone(aboveYellow, 224).zone == "locked"
            and prr.SkillRange.Zone(aboveYellow, 225).zone ~= "locked",
            "PRR 1.6 skill zones did not honor a verified above-yellow learning requirement")
        local nativeTrainerRank = 150
        function GetTrainerServiceSkillReq(serviceIndex)
            assert(serviceIndex == 7, "PRR did not use the tooltip's trainer service index")
            return "Tailoring", nativeTrainerRank, false
        end
        GameTooltip.processingInfo.getterArgs = {7}
        GameTooltip.lines = {}
        trainerPostCall(GameTooltip, {id = trainerRecipe.spellID})
        assert(GameTooltip.lines[1] == text("tooltip.skill_range", prr.SkillRange.Text(trainerRecipe, 150))
            and GameTooltip.lines[1]:find("[150]", 1, true),
            "PRR did not use the native trainer rank for the current teaching route")
        nativeTrainerRank = secret
        trainerPostCall(GameTooltip, {id = trainerRecipe.spellID})
        assert(GameTooltip.lines[2] == text("tooltip.skill_range", prr.SkillRange.Text(trainerRecipe)),
            "PRR did not fall back to the index for a restricted trainer rank")
        GetTrainerServiceSkillReq = nil
        trainerPostCall(GameTooltip, {id = 99999999})
        trainerPostCall(GameTooltip, {id = secret})
        GameTooltip.processingInfo = {getterName = "GetSpellByID"}
        trainerPostCall(GameTooltip, {id = 9198})
        assert(#GameTooltip.lines == 2, "PRR added trainer levels to an unrelated or unreadable spell")
        GameTooltip.processingInfo = nil
        ProfessionsFrame:Hide()
        WoWTools.settings.Open("raynna_bestiary")
        assert(bestiary.optionsPanel and bestiary.optionsPanel:GetParent() == bestiary.settingsPanel,
            "Bestiary options are not embedded in the shared canvas")
        assert(bestiary.languageDropdown.template == "WowStyle1DropdownTemplate",
            "Bestiary language selector is not the native dropdown")
        bestiary.languageDropdown:GenerateMenu()
        WoWTools.settings.window:Hide()
    end
end
local experienceText = assert(WoWTools.experienceText, "Missing experience text module")
assert(type(experienceText.SetPercentEnabled) == "function"
    and type(experienceText.IsPercentEnabled) == "function", "Missing XP percentage interfaces")
assert(not experienceText.IsPercentEnabled(), "XP percentage must default to disabled")
assert(experienceText.SetEnabled(true) and experienceText.SetPercentEnabled(true), "XP text setters failed")
assert(wowDetectorDB.displayFonts.showRestedXP and wowDetectorDB.displayFonts.showXPPercent
    and xpText:GetText() == "100 / 1000-10.0%（12345-1234.5%）", "XP text API or persistence binding failed")
local xpEvents
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_LEVEL_UP and frame.events.PLAYER_XP_UPDATE and frame.events.ADDON_LOADED then
        assert(not xpEvents, "Experience text events are registered more than once")
        xpEvents = frame
    end
end
assert(xpEvents, "Missing XP level-up event binding")
local levelRefresh, originalAfter = nil, C_Timer.After
C_Timer.After = function(delay, callback)
    assert(delay == 0 and type(callback) == "function", "XP level-up refresh timer signature failed")
    assert(not levelRefresh, "XP level-up refresh registered more than once")
    levelRefresh = callback
end
xpEvents.scripts.OnEvent(xpEvents, "PLAYER_LEVEL_UP", 61)
C_Timer.After = originalAfter
assert(levelRefresh, "Missing XP level-up refresh callback")
levelRefresh()
local experienceControl = assert(WoWTools.displayFonts.controls[1], "Missing experience font controls")
assert(experienceControl.key == "experience" and experienceControl.percent.kind == "CheckButton"
    and experienceControl.rested.kind == "CheckButton", "XP text options require independent checkboxes")
local settingsWindow, settingsCanvas = WoWTools.settings.window, WoWTools.settings.canvas
for _, texture in ipairs({settingsWindow.Bg, settingsWindow.InsetBg, settingsWindow.TitleBg, settingsCanvas.background}) do
    assert(texture.color and texture.color[1] == 32 / 255 and texture.color[2] == 32 / 255
        and texture.color[3] == 32 / 255 and texture.color[4] == 1, "Settings background must use opaque solid dark gray")
end
assert(not settingsWindow.TopTileStreaks:IsShown(), "Settings background retains native streak artwork")
assert(settingsCanvas.background:GetParent() == settingsCanvas and settingsCanvas.background.fill == settingsCanvas,
    "Solid settings background does not cover the shared canvas")
assert(WoWTools.settings.pages.button_style.frame == WoWTools.buttonStyle.panel
    and WoWTools.modules.button_style == WoWTools.buttonStyle, "Button skin page module binding failed")
assert(#WoWTools.buttonStyle.editors == 1, "Button skin editor is registered more than once")

local graphicControls, graphicTabs, uiTabs = {}, {}, {}
local hoverControl, framerateControl
local graphicContent = WoWTools.settings.pages.inner_graphic_config.content
local uiContent = WoWTools.settings.pages.ui_addons.content
for _, frame in ipairs(frames) do
    local definition = frame.definition
    if definition and definition.cvar then
        assert(not graphicControls[definition.cvar], "Graphics control was registered twice " .. definition.cvar)
        graphicControls[definition.cvar] = frame
    end
    if definition and definition.key == "chatItemHover" then
        assert(not hoverControl, "Chat item hover checkbox must be unique")
        hoverControl = frame
    elseif definition and definition.key == "frameratePosition" then
        framerateControl = frame
    end
    if frame.template == "MinimalTabTemplate" and frame:GetParent() == graphicContent then
        graphicTabs[frame.Text:GetText()] = frame
    elseif frame.template == "MinimalTabTemplate" and frame:GetParent() == uiContent then
        uiTabs[frame.Text:GetText()] = frame
    end
end
for _, name in ipairs({"缓存与分配", "界面", "字体", "Lua"}) do
    assert(uiTabs[name] and not graphicTabs[name], "UI category is bound to the wrong settings page " .. name)
end
assert(hoverControl and framerateControl and hoverControl:GetParent() == framerateControl:GetParent(),
    "Chat item hover must share the UI interface tab")
assert(hoverControl.template == "UICheckButtonTemplate" and not hoverControl:GetChecked(),
    "Chat item hover must initially be optional")
hoverControl:SetChecked(true)
hoverControl.scripts.OnClick(hoverControl)
assert(WoWTools.chatItemHover.IsEnabled() and wowDetectorDB.chatItemHover == true,
    "Chat item hover checkbox must save its account value")
hoverControl:SetChecked(false)
hoverControl.scripts.OnClick(hoverControl)
assert(not WoWTools.chatItemHover.IsEnabled(), "Chat item hover checkbox must support disabling")
if flavor == "forerver" then
    local categoryControl
    for _, frame in ipairs(frames) do
        local definition = frame.definition
        if definition and definition.categoryCollapse then
            assert(not categoryControl, "Category collapse checkbox must be unique")
            categoryControl = frame
        end
    end
    assert(categoryControl and framerateControl and categoryControl:GetParent() == framerateControl:GetParent(),
        "Category collapse must share the UI interface tab")
    assert(categoryControl.template == "UICheckButtonTemplate" and not categoryControl:GetChecked(),
        "Category collapse must initially be optional")
    categoryControl:SetChecked(true)
    categoryControl.scripts.OnClick(categoryControl)
    assert(WoWTools.categoryCollapse.IsEnabled() and wowDetectorDB.categoryCollapse.enabled == true,
        "Category collapse checkbox must bind to the account setter")
    categoryControl:SetChecked(false)
    categoryControl.scripts.OnClick(categoryControl)
    assert(not WoWTools.categoryCollapse.IsEnabled(), "Category collapse checkbox must support disabling")
    assert(uiTabs["背包整合"] and not graphicTabs["背包整合"], "Bag integration settings page binding failed")
    local bags = assert(WoWTools.bagIntegration, "Missing bag integration module")
    assert(type(bags.SetEnabled) == "function" and type(bags.IsEnabled) == "function", "Missing bag settings interfaces")
    assert(not bags.IsEnabled() and not bags.active, "Bag integration must initially be optional")
    assert(#bags.views == 1 and bags.views[1].enabled.template == "UICheckButtonTemplate",
        "Bag integration checkbox must bind to the shared UI page")
end
for tabName, values in pairs({["重采样"] = resampleCVars, ["贴图质量"] = textureCVars, ["缓存与分配"] = allocationCVars}) do
    local tabs = tabName == "缓存与分配" and uiTabs or graphicTabs
    local tab = assert(tabs[tabName], "Missing settings tab " .. tabName)
    assert(tab.Text.wordWrap == false and tab:GetWidth() >= tab.Text:GetStringWidth(),
        "Graphics navigation does not fit its single-line label " .. tabName)
    local pageParent
    for key, value in pairs(values) do
        local control = assert(graphicControls[key], "Missing graphics control " .. key)
        local definition = control.definition
        assert(type(definition.description) == "string" and #definition.description > 0, "Missing graphics value descriptions")
        pageParent = pageParent or control:GetParent()
        assert(control:GetParent() == pageParent, "Graphics controls use different category pages")
        local content = tabName == "缓存与分配" and uiContent or graphicContent
        assert(pageParent:GetParent():GetParent() == content, "CVar control has the wrong settings host")
        if definition.numeric then
            assert(control.input.numeric == not definition.decimal, "Numeric CVar input mode does not match its type")
            assert(tonumber(control.input:GetText()) == tonumber(value), "CVar input binding failed")
        else
            assert(control:GetChecked() == (value ~= "0"), "Boolean CVar binding failed")
        end
    end
end
assert(graphicControls.graphicsTextureResolution.definition.maximum == (flavor == "titan" and 1 or 2),
    "Texture resolution enum uses the other client's range")
assert(graphicControls.textureFilteringMode.definition.maximum == 5
    and graphicControls.textureFilteringMode.definition.meanings[5], "Texture filtering enum contract failed")
assert(graphicControls.ThreadPoolPerThreadAllocator.definition.maximum == 2
    and graphicControls.ThreadPoolPerThreadAllocator.definition.meanings[0], "Thread allocator enum contract failed")
assert(graphicControls.ResampleQuality.definition.maximum == 3 and graphicControls.ResampleQuality.definition.meanings[0],
    "Resample quality enum contract failed")
assert(graphicControls.ResampleAlwaysSharpen.definition.meanings[0] and graphicControls.ResampleAlwaysSharpen.definition.meanings[1],
    "Sharpening boolean contract failed")
assert(graphicControls.ResampleSharpness.definition.disabledValue == -1 and graphicControls.ResampleSharpness.definition.maximum == 2,
    "Resample sharpness range contract failed")
assert(graphicControls.RenderScale.definition.minimum == GetMinRenderScale()
    and graphicControls.RenderScale.definition.maximum == GetMaxRenderScale(), "Render scale native bounds binding failed")

assert(WoWTools.luaGC and type(WoWTools.luaGC.Save) == "function", "Missing Lua GC settings interface")
assert(#WoWTools.luaGC.views > 0, "Missing Lua GC settings controls")
for _, view in ipairs(WoWTools.luaGC.views) do
    assert(view.period:GetText() == "60", "Lua GC period must default to 60 seconds")
end
local secondsLabel
for _, object in ipairs(widgets) do
    if object.kind == "FontString" and object:GetText() == "校准周期（秒）" then secondsLabel = object end
end
assert(secondsLabel, "Lua GC period unit must be seconds")

local petXP = WoWTools.petXPBar
assert(petXP == WoWTools.modules.pet_xp_bar, "Pet XP module export failed")
assert(WoWTools.settings.pages.pet_xp_bar.frame == petXP.settingsPanel, "Pet XP settings page binding failed")
assert(petXP.sourceVersion == "1.3.1" and petXP.sourceCommit == "0c5da2aef6b2b56e307a77e37151fe4675be6c82",
    "Pet XP upstream identity mismatch")
assert(petXP.Compat.isForever == (flavor == "forerver"), "Pet XP client identity mismatch")
assert(petXP.Compat.GetLevelCap() == (flavor == "titan" and 80 or 60), "Pet XP level-cap API binding failed")
if TEST_THIRD_PARTY_DISABLED then
    assert(not petXP.ready and not petXP.frame and not petXP.db, "Disabled Pet XP initialized its runtime")
else
    assert(petXP.ready and petXP.db == wowDetectorDB.petXPBar.db, "Pet XP account persistence binding failed")
    WoWTools.settings.Open("pet_xp_bar")
    assert(petXP.optionsPanel and petXP.optionsPanel.name == "宠物经验", "Pet XP options builder contract failed")
    assert(type(petXP.Refresh) == "function" and type(petXP.HandleCommand) == "function", "Pet XP runtime load order failed")
    WoWTools.settings.Open("wowDetector")
end

local vendor = WoWTools.betterVendorUI
assert(vendor and vendor == WoWTools.modules.better_vendor_ui, "Embedded vendor module export failed")
assert(WoWTools.settings.pages.better_vendor_ui.frame == vendor.settingsPanel, "Vendor settings page binding failed")
assert(vendor.sourceVersion == "1.3.4" and vendor.sourceFileID == 9833185, "Vendor upstream identity mismatch")
if TEST_THIRD_PARTY_DISABLED then
    assert(not vendor.ready and not vendor.DB, "Disabled vendor registered its runtime")
else
    assert(vendor.ready and vendor.DB == wowDetectorDB.betterVendorUI.db, "Vendor account persistence binding failed")
    assert(type(vendor.ToggleConfig) == "function" and type(vendor.PassesFilters) == "function", "Vendor source load order failed")
    assert(vendor.Get("knownRecipes") == true, "Known recipe marks lack their default")
    WoWTools.settings.Open("better_vendor_ui")
    assert(vendor.optionsPanel and vendor.optionsPanel:GetParent() == vendor.settingsPanel, "Vendor options were not embedded")
    assert(vendor.optionsPanel.name == "商人增强", "Vendor settings title is not localized")
    WoWTools.settings.Open("wowDetector")
end

local expectedCategories = {
    wowDetector="game_assist", fight_detector="game_assist", pet_tamer="game_assist", auto_shop="game_assist",
    button_style="game_settings", inner_graphic_config="game_settings", ui_addons="game_settings", sound_control="game_settings",
    bigfoot_channel="third_party", ls_toasts="third_party", forever_faces="third_party", better_vendor_ui="third_party", pet_xp_bar="third_party", third_party="third_party",
    raynna_bestiary="third_party", prr="third_party",
    pet_skills="information",
}
assert(#WoWTools.settings.categories == 4, "Wrong primary settings category count")
local categoryWidth = math.max(1, settingsCanvas:GetWidth() - 16) / #WoWTools.settings.categories
local divider = assert(settingsCanvas.categoryDivider, "Missing primary navigation divider")
assert(divider:GetParent() == settingsCanvas and divider.kind == "Texture" and divider:GetHeight() == 1,
    "Primary divider texture binding failed")
assert(divider.point[1] == "TOPRIGHT" and divider.point[2] == settingsCanvas
    and divider.point[3] == "TOPRIGHT" and divider.point[4] == -8 and divider.point[5] == -49,
    "Primary divider must stretch across the canvas below the tabs")
assert(divider.color[1] == 0.4 and divider.color[2] == 0.4 and divider.color[3] == 0.4 and divider.color[4] == 1,
    "Primary divider color binding failed")
for index, label in ipairs({"游戏辅助", "游戏设置", "三方插件", "信息展示"}) do
    local category = WoWTools.settings.categories[index]
    local tab = WoWTools.settings.categoryTabs[category.key]
    assert(category.label == label and tab.Text:GetText() == label and tab.Text.wordWrap == false,
        "Primary category label binding failed")
    assert(tab.template == "MinimalTabTemplate" and tab.selectionGroup,
        "Primary navigation lacks the native tab/radio interface")
    assert(tab:GetParent() == settingsCanvas and tab.point[1] == "TOPLEFT"
        and tab.point[2] == 8 + (index - 1) * categoryWidth and tab.point[3] == -8,
        "Primary category anchor must use the top horizontal row")
    assert(tab:GetWidth() == categoryWidth and tab:GetHeight() == 37,
        "Primary tabs must divide the canvas width equally")
end
local secondaryRow = 0
for _, group in ipairs(WoWTools.settings.groups) do
    assert(group.category == expectedCategories[group.key], "Settings page has the wrong primary category " .. group.key)
    local tab = WoWTools.settings.tabs[group.key]
    assert(tab.Text:GetText() == group.label and tab.Text.wordWrap == false,
        "Secondary tab label is not a single unwrapped line")
    local activeCategory = group.category == WoWTools.settings.selectedCategory
    assert(tab:IsShown() == activeCategory, "Secondary navigation has the wrong category binding")
    if activeCategory then
        assert(tab.point[1] == "TOPLEFT" and tab.point[2] == 8 and tab.point[3] == -57 - secondaryRow * 45,
            "Secondary tab anchor must use the left column")
        secondaryRow = secondaryRow + 1
    end
end
do
    local settings = WoWTools.settings
    local previous = settings.selected
    assert(settings.tabs.pet_skills.Text:GetText() == "宠物技能", "Pet skills secondary tab is not labeled")
    local panel = settings.pages.pet_skills.frame
    local function HasLine(text)
        for _, region in ipairs(widgets) do
            local parent = region:GetParent()
            if parent and (parent == panel or parent:GetParent() == panel) and region.kind == "FontString"
                and region:IsVisible() and region:GetText() == text then return true end
        end
    end
    if flavor == "titan" then
        settings.Open("pet_skills")
        assert(HasLine("时光服没有可通过抓宠领悟的猎人宠物技能。") and not panel.scripts.OnEvent,
            "Titan pet skills must not use the Forever Beast Training interface")
    else
        local learnedSuffix = "-有 |A:common-icon-checkmark:14:14:0:-1|a"
        local unlearnedSuffix = "-无 |A:common-icon-redx:14:14:0:-1|a"
        settings.Open("pet_skills")
        assert(HasLine("请使用猎人角色查看。") and not HasLine("公共技能") and not HasLine("家族技能"),
            "The pet skill sections are visible on a non-hunter")
        local savedUnitClass, savedSpellName, savedSpellBook = UnitClass, C_Spell.GetSpellName, C_SpellBook
        local savedCharacterSettings = wowToolsCharacterSettings
        wowToolsCharacterSettings = {knownPetSkills = {[3666] = true}}
        function UnitClass(unit)
            assert(unit == "player", "Pet skills must query the hunter")
            return "猎人", "HUNTER", 3
        end
        function C_Spell.GetSpellName(spellID)
            if spellID == 17261 then return "本地化撕咬" end
        end
        Enum.SpellBookSpellBank = {Player = 0, Pet = 1}
        C_SpellBook = {IsSpellKnown = function(spellID, bank)
            assert(type(spellID) == "number" and bank == Enum.SpellBookSpellBank.Player,
                "Pet skills must check the hunter's teaching spell in the player bank")
            return spellID == 24599 or spellID == 17267 or spellID == 17261
        end}
        panel.scripts.OnEvent(panel, "PLAYER_LOGIN")
        settings.Open("pet_skills")
        assert(HasLine("公共技能") and HasLine("家族技能") and HasLine("风蛇-闪电吐息" .. unlearnedSuffix),
            "Pet skills must display the two sections and exclusive family labels")
        assert(HasLine("本地化撕咬" .. unlearnedSuffix) and HasLine("爪击" .. learnedSuffix)
            and HasLine("狼-狂怒之嚎" .. learnedSuffix),
            "Pet skill rows must append the correct icon for the highest teaching rank")
        assert(not HasLine("低吼" .. unlearnedSuffix) and not HasLine("低吼" .. learnedSuffix),
            "NPC trainer spells must stay out of the list")

        local savedTrainer, savedTooltip = C_Trainer, C_TooltipInfo
        local savedCount, savedServiceInfo = GetNumTrainerServices, GetTrainerServiceInfo
        local trainerType = 0
        Enum.TrainerType = {Pet = 3}
        C_Trainer = {GetTrainerType = function() return trainerType end}
        function GetNumTrainerServices() return 2 end
        function GetTrainerServiceInfo(index)
            if index == 1 then return "本地化撕咬", "used", nil, 48, "等级 7" end
            return "突进", "unavailable", nil, 50, nil
        end
        C_TooltipInfo = {GetTrainerService = function(index)
            if index == 1 then return {id = 17267} end
        end}
        panel.scripts.OnEvent(panel, "TRAINER_SHOW")
        assert(HasLine("突进" .. unlearnedSuffix), "NPC trainer windows must not mark a spell learned")
        trainerType = Enum.TrainerType.Pet
        panel.scripts.OnEvent(panel, "TRAINER_UPDATE")
        assert(HasLine("突进" .. learnedSuffix) and HasLine("本地化撕咬" .. unlearnedSuffix),
            "Beast Training must distinguish exact ranks even when a row omits the rank text")
        panel.scripts.OnEvent(panel, "LEARNED_SPELL_IN_SKILL_LINE", 17268)
        assert(HasLine("本地化撕咬" .. learnedSuffix) and wowToolsCharacterSettings.knownPetSkills[17268],
            "Learned teaching spell event must bind to the character record")
        local savedLearnText = ERR_LEARN_ABILITY_S
        ERR_LEARN_ABILITY_S = "你学会了%s。"
        panel.scripts.OnEvent(panel, "CHAT_MSG_SYSTEM", "你学会了|Hspell:1264482|h[音爆]|h。")
        assert(HasLine("蝙蝠-音爆" .. learnedSuffix) and wowToolsCharacterSettings.knownPetSkills[1264488],
            "The client learning message must bind the exact pet spell to its teaching ID")
        ERR_LEARN_ABILITY_S = savedLearnText
        UnitClass, C_Spell.GetSpellName, C_SpellBook = savedUnitClass, savedSpellName, savedSpellBook
        wowToolsCharacterSettings = savedCharacterSettings
        C_Trainer, C_TooltipInfo = savedTrainer, savedTooltip
        GetNumTrainerServices, GetTrainerServiceInfo = savedCount, savedServiceInfo
    end
    settings.Open(previous)
end
local loginPoint = assert(names.wowToolsLoginPoint, "Missing shared in-world mode marker")
assert(WoWTools.loginPoint == loginPoint and loginPoint:GetParent() == UIParent and #loginPoint.textures == 1
    and type(SlashCmdList.WOWTOOLSREST) == "function" and SLASH_WOWTOOLSREST1 == "/wowrest",
    "Shared mode marker or rest entry point contract failed")
local autoShop = assert(WoWTools.modules.auto_shop, "Missing automatic shopping module")
assert(type(autoShop.BuildSettings) == "function" and type(SlashCmdList.WOWTOOLSAUTOSHOP) == "function"
    and SLASH_WOWTOOLSAUTOSHOP1 == "/autoshop" and not autoShop.IsEnabled(),
    "Automatic shopping settings, slash command or initial state contract failed")
local shopPanel = assert(WoWTools.settings.pages.auto_shop.frame, "Missing shopping settings panel")
local shopExitCheck, shopList, shopAdd, shopNameEvents
local shopInputs = {}
for _, child in ipairs(frames) do
    if child:GetParent() == shopPanel then
        if child.kind == "CheckButton" and child.template == "UICheckButtonTemplate" then
            shopExitCheck = child
        elseif child.template == "BackdropTemplate" then
            shopList = child
        elseif child.kind == "EditBox" then
            shopInputs[#shopInputs + 1] = child
        elseif child.kind == "Button" and child:GetText() == "添加" then
            shopAdd = child
        elseif child.events.GET_ITEM_INFO_RECEIVED and child.events.ITEM_DATA_LOAD_RESULT then
            shopNameEvents = child
        end
    end
end
assert(#shopInputs == 2 and shopInputs[1].numeric and shopInputs[2].numeric
    and shopInputs[1].template == "InputBoxTemplate" and shopInputs[2].template == "InputBoxTemplate"
    and shopAdd and type(shopAdd.scripts.OnClick) == "function", "Shopping item entry controls are missing")
assert(shopNameEvents and type(shopNameEvents.scripts.OnEvent) == "function", "Shopping item-name events are unbound")
local shopScroll, shopContent, shopRow, shopQuantity
for _, child in ipairs(frames) do
    if child:GetParent() == shopList and child.template == "UIPanelScrollFrameTemplate" then
        shopScroll = child
    elseif shopScroll and child:GetParent() == shopScroll and child.kind == "Frame" then
        shopContent = child
    elseif shopContent and child:GetParent() == shopContent and child.kind == "Frame" then
        shopRow = child
    elseif shopRow and child:GetParent() == shopRow and child.kind == "EditBox" then
        shopQuantity = child
    end
end
assert(shopList and shopScroll and shopContent and shopRow, "Missing shopping list frame hierarchy")
assert(shopQuantity and shopQuantity.template == "InputBoxTemplate" and shopQuantity.numeric
    and shopQuantity:GetText() == "1", "Shopping quantity did not bind loaded SavedVariables to an editable row")
for _, target in ipairs({shopList, shopScroll, shopContent, shopRow, shopQuantity}) do
    assert(type(target.scripts.OnReceiveDrag) == "function" and type(target.scripts.OnMouseUp) == "function",
        "Shopping list drag/drop interface is unbound")
end
local shopHeaders, shopLabels = {}, {}
for _, widget in ipairs(widgets) do
    if widget.kind == "FontString" then
        if widget:GetParent() == shopList then shopHeaders[widget:GetText()] = true end
        if widget:GetParent() == shopRow then shopLabels[widget:GetText()] = true end
    end
end
assert(shopHeaders["物品名称"] and shopHeaders.ID and shopHeaders["数量"], "Shopping list column headers are missing")
assert(shopLabels["物品159"] and shopLabels["159"], "Loaded shopping row is missing its resolved name or item ID")
assert(shopExitCheck and shopExitCheck.Text:GetText() == "买到后下线并关闭游戏（仅限 wowAuto 单商品任务）"
    and shopExitCheck:GetChecked() and shopExitCheck:IsEnabled(), "Automatic shopping exit checkbox binding failed")
assert(WoWTools.settings.tabs.third_party.Text:GetText() == "插件列表", "Plugin list label binding failed")
local firstThirdPartyGroup
for _, group in ipairs(WoWTools.settings.groups) do
    if group.category == "third_party" then
        firstThirdPartyGroup = group
        break
    end
end
assert(firstThirdPartyGroup.key == "third_party", "Plugin list must be the top third-party tab")
assert(WoWTools.settings.pages.third_party and WoWTools.modules.third_party.BuildSettings,
    "Missing third-party settings interface")
assert(#WoWTools.thirdParty.entries == (flavor == "forerver" and 7 or 5), "Wrong client plugin list")
for _, row in ipairs(WoWTools.thirdParty.panel.rows) do
    local entry = row.entry
    local metadata = assert(WoWTools.thirdPartyCatalog[entry.key], "Missing plugin catalog entry")
    assert(entry.version == metadata.version and entry.updatedAt == metadata.updatedAt,
        "Plugin row metadata binding failed")
    assert(row.label:GetText() == entry.label .. "  " .. metadata.version .. "  " .. metadata.updatedAt,
        "Plugin name must be followed by its version and update date")
end
if TEST_THIRD_PARTY_DISABLED then
    assert(not WoWTools.lsToasts.C.db, "Disabled toast addon initialized its database")
    assert(not WoWTools.bigfootChannel.addon.db, "Disabled chat addon initialized its database")
else
    assert(WoWTools.lsToasts.C.db and WoWTools.bigfootChannel.addon.db, "Enabled addons failed to initialize")
end
do
    assert(WoWTools.foreverFaces ~= WoWTools.lsToasts, "Portrait and toast namespaces overlap")
    assert(WoWTools.settings.pages.forever_faces and WoWTools.modules.forever_faces == WoWTools.foreverFaces,
        "Missing unified portrait settings page or module")
    assert(WoWTools.settings.pages.forever_faces.frame == WoWTools.foreverFaces.settingsPanel,
        "Portrait settings page did not use the embedded settings interface")
    assert(WoWTools.foreverFaces.ToggleWindow == WoWTools.foreverFaces.Toggle,
        "Portrait legacy settings entry did not use the unified interface")
    assert(WoWTools.foreverFaces.DB() == wowDetectorDB.foreverFaces.db, "Portrait persistence binding failed")
    if not TEST_THIRD_PARTY_DISABLED then
        if WoWTools.foreverFaces.InitLevelCircle then WoWTools.foreverFaces.InitLevelCircle() end
        WoWTools.foreverFaces.InitPortraits()
        WoWTools.foreverFaces.InitUI()
        local portraitPanel = WoWTools.foreverFaces.settingsPanel
        local isVisible = portraitPanel.IsVisible
        portraitPanel.IsVisible = function() return true end
        WoWTools.foreverFaces.RefreshSettings()
        portraitPanel.IsVisible = isVisible
        assert(ForeverFacesWindow:GetParent() == portraitPanel.content,
            "Portrait controls did not initialize in the unified settings card")
        assert(portraitPanel.submenus.general and portraitPanel.submenus.style,
            "Portrait settings lack the general/style submenus")
        assert(portraitPanel.scroll.scrollRectUpdated, "Portrait scroll-child geometry was not refreshed")
        local style = WoWTools.foreverFaces.style
        assert(style.Config() == wowDetectorDB.foreverFaces.db.style and not style.Config().pixelEnabled,
            "Portrait style defaults or persistence binding failed")
        local stylePanel = WoWTools.foreverFaces.BuildStyleSettings(portraitPanel.content)
        stylePanel:Refresh()
        for _, option in ipairs(style.options) do
            local control = assert(stylePanel.controls[option.key], "Missing portrait style control " .. option.key)
            assert(option.help and control:GetScript("OnEnter") and control:GetScript("OnLeave"),
                "Missing portrait tooltip binding on control " .. option.key)
            assert(control:IsEnabled() == not option.unavailable,
                "Portrait option availability binding failed " .. option.key)
            if option.minimum then
                assert(control:GetScript("OnTextChanged") and control:GetScript("OnEditFocusGained")
                    and control:GetScript("OnEditFocusLost") and control:GetScript("OnEscapePressed"),
                    "Portrait numeric control lacks editing/save bindings " .. option.key)
                assert(control.apply:GetScript("OnClick") and control.apply:GetScript("OnEnter"),
                    "Portrait apply button lacks save/tooltip bindings " .. option.key)
                assert(control.apply:IsEnabled() == not option.unavailable,
                    "Unavailable snapshot parameters must disable their apply button " .. option.key)
            end
        end
        local modelContract = {
            SetUnit = function(_, unit, blend, ...)
                assert(type(unit) == "string" and type(blend) == "boolean" and select("#", ...) == 0,
                    "Portrait SetUnit must use the common two-argument client signature")
                return true
            end,
            SetDisplayInfo = function(_, id)
                assert(type(id) == "number" and id > 0, "Portrait DisplayID binding failed")
            end,
            SetModel = function(_, id, noMip)
                assert(type(id) == "number" and id > 0 and type(noMip) == "boolean",
                    "Portrait model FileID/noMip binding failed")
            end,
            SetPaused = function(_, paused) assert(type(paused) == "boolean", "Portrait pause binding failed") end,
            SetAnimation = function(_, animation) assert(animation == 0, "Portrait idle animation binding failed") end,
        }
        local savedStyle = wowDetectorDB.foreverFaces.db.style
        local enabled, unavailable = WoWTools.foreverFaces.SetStyle("pixelEnabled", true)
        assert(enabled == false and unavailable == style.Status() and not style.Config().pixelEnabled,
            "Portrait snapshot setter must reject the retired implementation")
        wowDetectorDB.foreverFaces.db.style = {pixelEnabled=true, resolution=48}
        assert(not style.Config().pixelEnabled and style.Config().resolution == 48,
            "Previously enabled snapshots must normalize to the unavailable state")
        WoWTools.foreverFaces.SetStyle("resolution", 48)
        WoWTools.foreverFaces.SetStyle("fps", 12)
        assert(style.Config() == wowDetectorDB.foreverFaces.db.style
            and style.Config().resolution == 48 and style.Config().fps == 12,
            "Portrait style setters failed to retain saved values across notifications")
        for _, source in ipairs({"unit", "display", "file"}) do
            wowDetectorDB.foreverFaces.db.style = {source=source, displayID=123, fileID=456, animation="idle"}
            assert(style.Load(modelContract, "player"), "Portrait model source interface failed " .. source)
        end
        wowDetectorDB.foreverFaces.db.style = savedStyle
        local unitPortraitHook = chatMock.hooks.UnitFramePortrait_Update
        assert(type(unitPortraitHook) == "function", "Missing native unit-frame portrait hook")
        local unitFrame = CreateFrame("Frame")
        unitFrame:SetAttribute("unit", "target")
        unitFrame.unit = "target"
        unitFrame.portrait = {
            GetObjectType = function() return "Texture" end,
            GetParent = function() return unitFrame end,
            GetSize = function() return 58, 58 end,
            GetAlpha = function() return 1 end,
            IsShown = function() return false end,
        }
        local originalGUID, boundUnit = UnitGUID
        UnitGUID = function(unit) boundUnit = unit end
        unitPortraitHook(unitFrame)
        UnitGUID = originalGUID
        assert(boundUnit == "target", "Native unit-frame portrait argument binding failed")

        local createFrame = CreateFrame
        local unitExists, unitVisible, unitReady, getTime = UnitExists, UnitIsVisible, IsUnitModelReadyForUI, GetTime
        local model, cameraConfigured, modelAlpha
        CreateFrame = function(kind, ...)
            local frame = createFrame(kind, ...)
            if kind == "PlayerModel" then
                model = frame
                frame.ClearModel = function() end
                frame.GetModelFileID = function() return 0 end
                frame.SetModelAlpha = function(_, alpha) modelAlpha = alpha end
                frame.SetCamDistanceScale = function(_, value) assert(type(value) == "number") end
                frame.SetPosition = function(_, x, y, z) assert(x == 0 and y == 0 and z == 0) end
                frame.SetPortraitZoom = function(_, zoom) cameraConfigured = zoom == 1 end
                frame.SetUnit = function(_, unit, blend, ...)
                    assert(unit == "targettarget" and blend == false and select("#", ...) == 0)
                    return true
                end
            end
            return frame
        end
        local function TargetOfTargetAPI(unit, ...)
            assert(unit == "targettarget" and select("#", ...) == 0, "Invalid target-of-target model unit argument")
            return true
        end
        UnitExists, UnitIsVisible, IsUnitModelReadyForUI = TargetOfTargetAPI, TargetOfTargetAPI, TargetOfTargetAPI
        UnitGUID, GetTime = function() return "test-target-of-target" end, function() return 0 end
        unitFrame.unit = "targettarget"
        function unitFrame:GetAttribute(key) if key == "unit" then return self.unit end end
        unitFrame.portrait = unitFrame:CreateTexture()
        unitFrame.portrait.GetObjectType = function() return "Texture" end
        unitFrame.portrait.GetSize = function() return 36, 36 end
        unitPortraitHook(unitFrame)
        assert(model and cameraConfigured, "Target-of-target PlayerModel contract failed")
        assert(modelAlpha == nil, "SetUnit success is not a model-loaded signal")
        model:GetScript("OnModelLoaded")(model)
        assert(modelAlpha == 1, "The native model-loaded callback must configure the portrait with no file ID")
        CreateFrame, UnitGUID, GetTime = createFrame, originalGUID, getTime
        UnitExists, UnitIsVisible, IsUnitModelReadyForUI = unitExists, unitVisible, unitReady
    end
end
assert(#registeredCategories == 1 and #addonCategories == 1, "Settings category interface failed")
for _, name in ipairs({"WOWDETECTOR", "FIGHTDETECTOR", "WOWTOOLS"}) do
    assert(type(SlashCmdList[name]) == "function", "Missing slash-command interface " .. name)
end
print("PASS: " .. flavor .. " TOC initialization, third-party " .. (TEST_THIRD_PARTY_DISABLED and "disabled" or "enabled")
    .. " module exports, native templates and typed UI/API compatibility.")
