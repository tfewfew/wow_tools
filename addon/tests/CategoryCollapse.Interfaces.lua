-- Forever native UI at 943764493e6b16d63ded3ab304150d1f05e58b57.
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
    InitScrollBoxListWithScrollBar = function() end,
    AddInitializedFrameCallback = function(scrollBox, callback, owner, iterateExisting)
        assert(owner == scrollBox and not iterateExisting, "Use explicit iteration for existing frames")
        scrollBox.initialized = callback
    end,
}
function hooksecurefunc(target, method, callback)
    assert(target == ScrollUtil and method == "InitScrollBoxListWithScrollBar")
    local original = target[method]
    target[method] = function(...) original(...); callback(...) end
end
function EnumerateFrames(previous)
    if not previous then return frames[1] end
    for index, frame in ipairs(frames) do
        if frame == previous then return frames[index + 1] end
    end
end
local function ScrollBox(data)
    local box = {button = Button(), data = data}
    function box:IsForbidden() return false end
    function box:GetDataProvider() return self.provider end
    function box:ForEachFrame(callback) callback(self.button, self.data) end
    function box:Initialize(data)
        self.data = data
        self.initialized(self, self.button, data)
    end
    frames[#frames + 1] = box
    return box
end
local skills = ScrollBox({isHeader = true, skillIndex = 1})
skills.button.ToggleCollapseButton = Button()
local reputation = ScrollBox({isHeader = true, factionIndex = 1})
local node = {GetNodes = function() return {} end, GetData = function() return {categoryInfo = {}} end}
local recipes = ScrollBox(node)
local providerCalls = 0
recipes.provider = {CollapseAll = function(self)
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
recipes:Initialize({GetNodes = function() return {} end, GetData = function() return {recipeInfo = {}} end})
menuAction = nil
recipes.button.scripts.OnMouseUp(recipes.button, "RightButton")
assert(not menuAction, "Reused recipe rows must clear the category binding")
local later = ScrollBox(node)
later.provider = recipes.provider
ScrollUtil.InitScrollBoxListWithScrollBar(later)
assert(later.button.scripts.OnMouseUp, "Load-on-demand lists must receive initialization callbacks")
menuExtensions.MENU_QUEST_MAP_FRAME({}, menu)
menuAction()
assert(questCalls[1] == 3 and questCalls[2] == 1 and QuestSearcher.headerStates.header1 == true)
collapse.SetEnabled(false)
menuAction = nil
menuExtensions.MENU_QUEST_MAP_FRAME({}, menu)
skills.button.scripts.OnMouseUp(skills.button, "RightButton")
assert(not menuAction, "Disabled integration must omit the menu action")
print("PASS: Forever category collapse native UI and account-setting interfaces.")
