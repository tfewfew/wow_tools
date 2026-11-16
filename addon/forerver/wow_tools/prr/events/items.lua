WoWTools.prr.RegisterSource(function(...)
-- items.lua -- an item reached the client from the server: save its name
-- (dataflows/item_names.lua) and redraw the item window; the bags changed:
-- the reagents to buy of the leveling plan follow; a skill went up: a plan
-- from the current skill follows; the profession window shows its recipes:
-- the learned ones are remembered (the plan opens them).

local ADDON, ns = ...

ns.Events.On("GET_ITEM_INFO_RECEIVED", function(itemID, isSuccess)
    if not ns.db then return end
    if not (itemID and isSuccess) then return end
    -- redraw only for a name that is new to the cache
    local wasKnown = ns.Dataflows.ItemNames.IsKnown(itemID)
    ns.Dataflows.ItemNames.Remember(itemID)
    if not wasKnown then
        ns.Components.ItemWindow.RefreshSoon()
    end
end)

ns.Events.On("BAG_UPDATE_DELAYED", function()
    if not ns.db then return end
    ns.Components.LevelingTab.OnBagsChanged()
end)

ns.Events.On("SKILL_LINES_CHANGED", function()
    if not ns.db then return end
    ns.Components.LevelingTab.OnSkillsChanged()
    ns.Components.ItemWindow.RefreshSoon()
end)

ns.Events.On("NEW_RECIPE_LEARNED", function(recipeID)
    if not ns.db then return end
    ns.GameData.RememberLearnedRecipe(recipeID)
    ns.Components.ItemWindow.RefreshSoon()
end)

ns.Events.On("SPELLS_CHANGED", function()
    if not ns.db then return end
    ns.Components.ItemWindow.RefreshSoon()
end)

local function RememberLearned()
    if not ns.db then return end
    if ns.GameData.RememberLearnedRecipes() then
        ns.Components.LevelingTab.Refresh()
        ns.Components.ItemWindow.RefreshSoon()
    end
end
ns.Events.On("TRADE_SKILL_SHOW", RememberLearned)
ns.Events.On("TRADE_SKILL_LIST_UPDATE", RememberLearned)
end)
