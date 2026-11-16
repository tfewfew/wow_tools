WoWTools.prr.RegisterSource(function(...)
-- tab_bar.lua -- tabs hanging under the bottom edge of a window, like the
-- tabs of the character and guild windows. The game template is used:
-- PanelTabButtonTemplate on modern clients (Forever, Retail), the old
-- CharacterFrameTabButtonTemplate elsewhere -- the same choice BugSack makes.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local MODERN_TEMPLATE = "PanelTabButtonTemplate"
local OLD_TEMPLATE = "CharacterFrameTabButtonTemplate"
local MODERN_GAP = 3      -- between tabs
local OLD_GAP = -16       -- old tabs have wide transparent edges and overlap
local FIRST_TAB_LEFT = 11
local FIRST_TAB_TOP = 2   -- tabs tuck this much under the window edge
local TAB_TEXT_PADDING = 0

-- The game template, created with a global name: older tab code finds the
-- text and the edge textures by the name ("<name>Text", "<name>Left").
local function CreateTab(parent, name)
    local ok, tab = pcall(CreateFrame, "Button", name, parent, MODERN_TEMPLATE)
    if ok and tab then
        return tab, MODERN_GAP
    end
    tab = CreateFrame("Button", name, parent, OLD_TEMPLATE)
    -- the old template counts its tabs through the parent on show; we select tabs ourselves
    tab:SetScript("OnLoad", nil)
    tab:SetScript("OnShow", nil)
    return tab, OLD_GAP
end

local function SetTabText(tab, text)
    tab:SetText(text)
    if tab.Text then
        tab.Text:SetText(text)
    end
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(tab, TAB_TEXT_PADDING)
    end
end

-- The text colors of a tab that can be disabled: the game's own disable
-- (PanelTemplates_DisableTab) takes the window and the tab number, not the
-- tab, so the tab is greyed here by hand and the colors are set for all its states.
local DISABLED_COLOR = { 0.5, 0.5, 0.5 }
local NORMAL_COLOR = { 1, 0.82, 0 }      -- like GameFontNormalSmall
local SELECTED_COLOR = { 1, 1, 1 }       -- like GameFontHighlightSmall

local function SetTabTextColor(tab, color)
    local fontString = tab.Text or tab:GetFontString()
    if fontString then
        fontString:SetTextColor(color[1], color[2], color[3])
    end
end

-- options:
--   namePrefix -- global name prefix of the tab buttons, "<prefix>1", "<prefix>2", ...
--   tabs       -- { { id, text }, ... } left to right
--   onSelect(id) -- a tab was clicked
-- bar:Select(id) marks the tab as selected (does not call onSelect).
-- bar:SetTabEnabled(id, isEnabled) -- a disabled tab is grey and cannot be clicked.
function ns.UI.TabBar(parent, options)
    local bar = {}
    local tabs = {}           -- [id] = tab button
    local disabledTabs = {}   -- [id] = true
    local toggledTabs = {}    -- [id] = true: tabs ever passed to SetTabEnabled, their colors are ours
    local selectedId = nil
    local previous = nil

    for index, tabOptions in ipairs(options.tabs) do
        local tab, gap = CreateTab(parent, options.namePrefix .. index)
        SetTabText(tab, tabOptions.text)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", gap, 0)
        else
            tab:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", FIRST_TAB_LEFT, FIRST_TAB_TOP)
        end
        tab:SetScript("OnClick", function()
            options.onSelect(tabOptions.id)
        end)
        tabs[tabOptions.id] = tab
        previous = tab
    end

    -- deselecting enables a tab again, so the disabled ones are disabled after it
    function bar:Select(id)
        selectedId = id
        for tabId, tab in pairs(tabs) do
            local isSelected = tabId == id
            if isSelected then
                PanelTemplates_SelectTab(tab)
            else
                PanelTemplates_DeselectTab(tab)
            end
            local isDisabled = disabledTabs[tabId] and not isSelected
            if isDisabled then
                tab:Disable()
                SetTabTextColor(tab, DISABLED_COLOR)
            elseif toggledTabs[tabId] then
                -- a tab disabled before may stay so after deselecting on some clients
                if not isSelected then
                    tab:Enable()
                end
                SetTabTextColor(tab, isSelected and SELECTED_COLOR or NORMAL_COLOR)
            end
        end
    end

    function bar:SetTabEnabled(id, isEnabled)
        if not tabs[id] then return end
        local isDisabled = not isEnabled or nil
        if toggledTabs[id] and disabledTabs[id] == isDisabled then return end
        toggledTabs[id] = true
        disabledTabs[id] = isDisabled
        bar:Select(selectedId)
    end

    return bar
end
end)
