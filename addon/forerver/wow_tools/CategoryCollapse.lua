local collapse = {}
WoWTools.categoryCollapse = collapse

local scrollBoxes = setmetatable({}, {__mode = "k"})
local buttons = setmetatable({}, {__mode = "k"})
local scrollHooked, questMenuHooked = false, false

function collapse.IsEnabled()
    return type(wowDetectorDB) == "table"
        and type(wowDetectorDB.categoryCollapse) == "table"
        and wowDetectorDB.categoryCollapse.enabled == true
end

local function CollapseSkills()
    for index = C_SkillInfo.GetNumSkillLines(), 1, -1 do
        local info = C_SkillInfo.GetSkillLineInfo(index)
        if info and info.isHeader and not info.isCollapsed then
            C_SkillInfo.CollapseSkillHeader(index)
        end
    end
end

local function CollapseReputations()
    for index = C_Reputation.GetNumFactions(), 1, -1 do
        local info = C_Reputation.GetFactionDataByIndex(index)
        if info and info.isHeader and not info.isCollapsed then
            C_Reputation.CollapseFactionHeader(index)
        end
    end
end

local function CollapseQuests()
    if not collapse.IsEnabled() then return end
    local previous = QuestMapFrame.ignoreQuestLogUpdate
    QuestMapFrame.ignoreQuestLogUpdate = true
    for index = C_QuestLog.GetNumQuestLogEntries(), 1, -1 do
        local info = C_QuestLog.GetInfo(index)
        if info and info.isHeader then
            CollapseQuestHeader(info.questLogIndex, true)
            -- Searches restore these saved states when their results are dismissed.
            if QuestSearcher and QuestSearcher.headerStates then
                QuestSearcher.headerStates[info.headerSortKey] = true
            end
        end
    end
    QuestMapFrame.ignoreQuestLogUpdate = previous
    QuestMapFrame_UpdateAll()
end

local function ShowMenu(button, mouseButton)
    local entry = buttons[button]
    if mouseButton ~= "RightButton" or not collapse.IsEnabled() or not entry.action then return end
    MenuUtil.CreateContextMenu(button, function(_, menu)
        menu:CreateButton("全部收起", function()
            if collapse.IsEnabled() and entry.action then entry.action() end
        end)
    end)
end

local function BindButton(button, action)
    local entry = buttons[button]
    if not entry then
        entry = {}
        buttons[button] = entry
        -- OnMouseUp receives right clicks without changing native click registration.
        button:HookScript("OnMouseUp", ShowMenu)
    end
    entry.action = action
end

local function InitializeButton(scrollBox, button, elementData)
    local action
    if collapse.IsEnabled() and type(elementData) == "table" then
        if elementData.isHeader and elementData.skillIndex then
            action = CollapseSkills
        elseif elementData.isHeader and elementData.factionIndex then
            action = CollapseReputations
        elseif type(elementData.GetNodes) == "function" and type(elementData.GetData) == "function" then
            local data = elementData:GetData()
            local provider = scrollBox:GetDataProvider()
            if provider and type(provider.CollapseAll) == "function"
                and (#elementData:GetNodes() > 0 or type(data) == "table" and data.categoryInfo) then
                action = function()
                    -- Read the current provider after native filtering or recipe rebuilds.
                    local current = scrollBox:GetDataProvider()
                    if current and type(current.CollapseAll) == "function" then current:CollapseAll() end
                end
            end
        end
    end
    if action or buttons[button] then BindButton(button, action) end
    if button.ToggleCollapseButton and (action or buttons[button.ToggleCollapseButton]) then
        BindButton(button.ToggleCollapseButton, action)
    end
end

local function AttachScrollBox(scrollBox)
    if scrollBoxes[scrollBox] then return end
    scrollBoxes[scrollBox] = true
    -- Iterate explicitly because the native iterateExisting callback omits its owner argument.
    scrollBox:ForEachFrame(function(button, elementData)
        InitializeButton(scrollBox, button, elementData)
    end)
    ScrollUtil.AddInitializedFrameCallback(scrollBox, InitializeButton, scrollBox)
end

local function Install(refreshExisting)
    if not collapse.IsEnabled() then return end
    if not scrollHooked and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        hooksecurefunc(ScrollUtil, "InitScrollBoxListWithScrollBar", AttachScrollBox)
        scrollHooked = true
        refreshExisting = true
    end
    if not questMenuHooked and Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_QUEST_MAP_FRAME", function(_, menu)
            if collapse.IsEnabled() then menu:CreateButton("全部收起", CollapseQuests) end
        end)
        questMenuHooked = true
    end
    if refreshExisting ~= true or not scrollHooked or not EnumerateFrames then return end
    local frame = EnumerateFrames()
    while frame do
        if not frame:IsForbidden() and type(frame.GetDataProvider) == "function"
            and type(frame.ForEachFrame) == "function" then
            AttachScrollBox(frame)
        end
        frame = EnumerateFrames(frame)
    end
    for scrollBox in pairs(scrollBoxes) do
        scrollBox:ForEachFrame(function(button, elementData)
            InitializeButton(scrollBox, button, elementData)
        end)
    end
end

function collapse.SetEnabled(enabled)
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.categoryCollapse) ~= "table" then wowDetectorDB.categoryCollapse = {} end
    wowDetectorDB.categoryCollapse.enabled = enabled == true
    Install(true)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", Install)
