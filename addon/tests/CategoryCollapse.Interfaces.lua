-- Forever native UI at bebcb6bf309cf41b41bd74f8ca651e6a105b2676.
-- Verify ScrollUtil owner arguments, native menu extensions and collapse API signatures.
local root = TEST_ROOT or "."
WoWTools, wowDetectorDB = {}, {unrelated = true}
local frames, callbacks, menuExtensions = {}, {}, {}
local menuAction, menuTitle, nativeClicks
local function Button()
    local button = {scripts = {OnClick = function() nativeClicks = (nativeClicks or 0) + 1 end}}
    function button:HookScript(event, callback)
        assert(event == "OnMouseUp", "Header integration must preserve native click handlers")
        assert(not self.scripts[event], "Pooled headers must be hooked once")
        self.scripts[event] = callback
    end
    return button
end
function CreateFrame(kind)
    assert(kind == "Frame")
    return {RegisterEvent = function(_, event) assert(event == "ADDON_LOADED") end,
        SetScript = function(_, event, callback) assert(event == "OnEvent"); callbacks.loaded = callback end}
end
Menu = {ModifyMenu = function(tag, callback)
    assert(tag == "MENU_QUEST_MAP_FRAME", "Quest integration must extend the native header menu")
    assert(not menuExtensions[tag], "Menu extension must be registered once")
    menuExtensions[tag] = callback
end}
local menu = {CreateButton = function(_, title, callback)
    assert(type(title) == "string" and type(callback) == "function")
    menuTitle, menuAction = title, callback
end}
MenuUtil = {CreateContextMenu = function(owner, generator)
    assert(owner and owner.scripts, "Native context menus require a frame owner")
    generator(owner, menu)
end}
ScrollUtil = {
    InitScrollBoxListWithScrollBar = function(scrollBox) scrollBox.view = {} end,
    AddInitializedFrameCallback = function(scrollBox, callback, owner, iterateExisting)
        assert(owner == scrollBox and not iterateExisting, "Use explicit iteration for existing frames")
        assert(not scrollBox.initialized, "Native list callbacks must be registered once")
        scrollBox.initialized = callback
    end,
}
function hooksecurefunc(target, method, callback)
    assert(target == ScrollUtil and method == "InitScrollBoxListWithScrollBar"
        or target == ProfessionsFrame.CraftingPage and (method == "GetCollapses" or method == "StoreCollapses"))
    local original = target[method]
    target[method] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end
function EnumerateFrames(previous)
    if not previous then return frames[1] end
    for index, frame in ipairs(frames) do
        if frame == previous then return frames[index + 1] end
    end
end
local function ScrollBox(data, initialized)
    local box = {button = Button(), data = data}
    if initialized ~= false then box.view = {} end
    function box:IsForbidden() return false end
    function box:GetView() return self.view end
    function box:GetDataProvider() return self.provider end
    function box:ForEachFrame(callback)
        assert(self:GetView(), "Native ForEachFrame requires an initialized view")
        callback(self.button, self.data)
    end
    function box:Initialize(data)
        self.data = data
        self.initialized(self, self.button, data)
    end
    frames[#frames + 1] = box
    return box
end
-- EnumerateFrames includes native lists before ScrollUtil has installed their views.
local unloaded = ScrollBox(nil, false)
local skills = ScrollBox({isHeader = true, skillIndex = 1})
skills.button.ToggleCollapseButton = Button()
local reputation = ScrollBox({isHeader = true, factionIndex = 1})
local node = {GetNodes = function() return {} end, GetData = function() return {categoryInfo = {}} end}
local recipes = ScrollBox(node)
local categoryNodes = {
    {id = 1, collapsed = true},
    {id = 2, collapsed = true}, -- A child category inside the collapsed root.
    {id = 3, collapsed = false},
    {id = 1, collapsed = false}, -- Native learned/unlearned trees share category IDs.
}
for _, entry in ipairs(categoryNodes) do
    function entry:GetData() return {categoryInfo = {categoryID = self.id}} end
    function entry:IsCollapsed() return self.collapsed end
end
local page = {RecipeList = {ScrollBox = recipes}}
function page:GetCollapses() return self.collapses end
function page:StoreCollapses(scrollBox)
    assert(scrollBox == recipes)
    self.collapses = {[1] = true} -- The native implementation stores root categories.
end
ProfessionsFrame = {CraftingPage = page}
local providerCalls = 0
recipes.provider = {EnumerateEntireRange = function() return ipairs(categoryNodes) end,
    CollapseAll = function(self)
    assert(self == recipes.provider, "Tree collapse must use the current native provider")
    providerCalls = providerCalls + 1
end}
local skillCalls, reputationCalls, questCalls = {}, {}, {}
C_SkillInfo = {
    GetNumSkillLines = function() return 3 end,
    GetSkillLineInfo = function(index) return {isHeader = index ~= 2} end,
    CollapseSkillHeader = function(index)
        assert(index == 1 or index == 3, "Skill collapse requires a native header index")
        skillCalls[#skillCalls + 1] = index
    end,
}
C_Reputation = {
    GetNumFactions = function() return 3 end,
    GetFactionDataByIndex = function(index) return {isHeader = index ~= 2} end,
    CollapseFactionHeader = function(index)
        assert(index == 1 or index == 3, "Reputation collapse requires a native faction index")
        reputationCalls[#reputationCalls + 1] = index
    end,
}
QuestMapFrame = {ignoreQuestLogUpdate = "existing"}
QuestSearcher = {headerStates = {}}
C_QuestLog = {
    GetNumQuestLogEntries = function() return 3 end,
    GetInfo = function(index)
        return {isHeader = index ~= 2, questLogIndex = index, headerSortKey = "header" .. index}
    end,
}
function CollapseQuestHeader(index, skipUpdate)
    assert((index == 1 or index == 3) and skipUpdate == true and QuestMapFrame.ignoreQuestLogUpdate == true,
        "Quest bulk collapse must use native header indices and deferred refresh")
    questCalls[#questCalls + 1] = index
end
function QuestMapFrame_UpdateAll()
    assert(QuestMapFrame.ignoreQuestLogUpdate == "existing", "Native quest update guard must be restored")
end
dofile(root .. "/addon/forerver/wow_tools/CategoryCollapse.lua")
local collapse = WoWTools.categoryCollapse
assert(not collapse.IsEnabled() and wowDetectorDB.unrelated, "Old account settings must load disabled")
collapse.SetEnabled(true)
assert(collapse.IsEnabled() and wowDetectorDB.unrelated, "Account persistence must preserve other settings")
assert(not unloaded.initialized, "Uninitialized lists must remain available for later attachment")
skills.button.scripts.OnClick()
assert(nativeClicks == 1, "Native click script must remain bound")
skills.button.scripts.OnMouseUp(skills.button, "LeftButton")
assert(not menuAction, "Left clicks must retain native handling")
skills.button.scripts.OnMouseUp(skills.button, "RightButton")
assert(menuTitle == "全部收起" and #skillCalls == 0, "Right clicks must bind a menu action")
menuAction()
assert(skillCalls[1] == 3 and skillCalls[2] == 1, "Header indices must be collapsed in reverse order")
assert(skills.button.ToggleCollapseButton.scripts.OnMouseUp, "Subheader toggles need the same menu binding")
reputation.button.scripts.OnMouseUp(reputation.button, "RightButton")
menuAction()
assert(reputationCalls[1] == 3 and reputationCalls[2] == 1)
recipes.button.scripts.OnMouseUp(recipes.button, "RightButton")
menuAction()
assert(providerCalls == 1)
local saved = page:GetCollapses()
assert(saved == page.collapses and saved[1] and saved[2] and saved[3] == nil,
    "Native recipe regeneration must receive current root and child collapse states")
categoryNodes[1].collapsed, categoryNodes[2].collapsed = false, false
saved = page:GetCollapses()
assert(saved[1] == nil and saved[2] == nil,
    "Native recipe regeneration must receive explicit category expansions")
categoryNodes[2].collapsed = true
page:StoreCollapses(recipes)
assert(page.collapses[2], "Native panel-close storage must include child categories")
recipes:Initialize({GetNodes = function() return {} end, GetData = function() return {recipeInfo = {}} end})
menuAction = nil
recipes.button.scripts.OnMouseUp(recipes.button, "RightButton")
assert(not menuAction, "Reused recipe rows must clear the category binding")
local later = ScrollBox(node)
later.provider = recipes.provider
ScrollUtil.InitScrollBoxListWithScrollBar(later)
assert(later.button.scripts.OnMouseUp, "Load-on-demand lists must receive initialization callbacks")
unloaded.data, unloaded.provider = node, recipes.provider
ScrollUtil.InitScrollBoxListWithScrollBar(unloaded)
assert(unloaded.button.scripts.OnMouseUp, "Previously uninitialized lists must bind after native initialization")
later.view = nil
collapse.SetEnabled(true)
assert(skills.button.scripts.OnMouseUp, "A detached list view must preserve other list bindings")
menuExtensions.MENU_QUEST_MAP_FRAME({}, menu)
menuAction()
assert(questCalls[1] == 3 and questCalls[2] == 1 and QuestSearcher.headerStates.header1 == true)
collapse.SetEnabled(false)
menuAction = nil
menuExtensions.MENU_QUEST_MAP_FRAME({}, menu)
skills.button.scripts.OnMouseUp(skills.button, "RightButton")
assert(not menuAction, "Disabled integration must omit the menu action")
print("PASS: Forever category collapse native UI and account-setting interfaces.")
