WoWTools.prr.RegisterSource(function(...)
-- bag_click.lua -- clicks on items that put them into the item window:
--
--   * the click chosen in the settings (settings.openBinding, Alt+click by
--     default) on any item -- bags, chat links, loot -- opens the window with it;
--   * Shift+click while the window is open puts the item into it;
--   * Shift+click while the search of the planner's prices has the focus puts
--     "[name]" into it (an exact search) -- this one wins.
--
-- Item buttons (the game's bags and BagBrother / Bagnon, chat links) pass a
-- click with a modifier, with either mouse button, to HandleModifiedItemClick(link).
-- With Shift the game then opens the stack split window for a stack -- it is
-- closed on the next frame: the click meant "show this item".

local ADDON, ns = ...

local Constants = ns.Constants
local ItemWindow = ns.Components.ItemWindow

local function IsDown(isKeyDown)
    return isKeyDown and true or false
end

-- Does the click now going on match the chosen binding, modifiers exactly?
local function IsOpenBindingClick()
    local binding = Constants.OPEN_BINDINGS_BY_ID[ns.db.settings.openBinding]
    if not binding or not binding.button then
        return false
    end
    local mouseButton = "LeftButton"
    if GetMouseButtonClicked then
        mouseButton = GetMouseButtonClicked() or mouseButton
    end
    return mouseButton == binding.button
        and IsDown(IsAltKeyDown()) == IsDown(binding.alt)
        and IsDown(IsControlKeyDown()) == IsDown(binding.ctrl)
        and IsDown(IsShiftKeyDown()) == IsDown(binding.shift)
end

-- With Shift the game opens the stack split window for a stack: the click
-- meant "show this item", the window closes on the next frame.
local function CloseStackSplitSoon()
    C_Timer.After(0, function()
        if StackSplitFrame and StackSplitFrame:IsShown() then
            StackSplitFrame:Hide()
        end
    end)
end

hooksecurefunc("HandleModifiedItemClick", function(link)
    if not ns.db then return end
    local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
    if not itemID then return end

    local isShiftIntoPlannerSearch = IsShiftKeyDown() and ns.Components.PricesTab.IsSearchFocused()
    if isShiftIntoPlannerSearch then
        ns.Components.PricesTab.SearchItem(itemID)
        CloseStackSplitSoon()
        return
    end

    local isShiftIntoOpenWindow = IsShiftKeyDown() and ItemWindow.IsShown()
    if not IsOpenBindingClick() and not isShiftIntoOpenWindow then return end

    ItemWindow.SetItem(itemID)
    if IsShiftKeyDown() then
        CloseStackSplitSoon()
    end
end)
end)
