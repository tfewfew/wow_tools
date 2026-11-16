WoWTools.prr.RegisterSource(function(...)
-- item_name_warmup.lua -- at login asks the server, a portion per tick, for
-- every item of the base whose name is not saved yet: recipe results,
-- reagents, patterns. The names come in GET_ITEM_INFO_RECEIVED and are saved
-- by dataflows/item_names.lua (events/items.lua), so the window opens with
-- every name in place and its lists do not jump. After the first session
-- there is almost nothing left to ask.

local ADDON, ns = ...
ns.Services = ns.Services or {}

local Config = ns.Config
local ItemNames = ns.Dataflows.ItemNames
local RecipeIndex = ns.Dataflows.RecipeIndex

local ItemNameWarmup = {}
ns.Services.ItemNameWarmup = ItemNameWarmup

local queue = nil   -- item ids still to ask for
local position = 1

function ItemNameWarmup.Start()
    local seen = {}
    queue = {}
    local function Add(itemID)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            if not ItemNames.IsKnown(itemID) and not ItemNames.Remember(itemID) then
                table.insert(queue, itemID)
            end
        end
    end
    for _, recipe in ipairs(RecipeIndex.AllRecipes()) do
        Add(recipe.item)
        Add(recipe.recipeItem)
        for _, reagent in ipairs(recipe.reagents or {}) do
            Add(reagent[1])
        end
    end
    position = 1
end

function ItemNameWarmup.IsRunning()
    return queue ~= nil
end

function ItemNameWarmup.Step()
    if not queue then return end
    local last = math.min(position + Config.NAME_WARMUP_ITEMS_PER_TICK - 1, #queue)
    for i = position, last do
        ItemNames.Request(queue[i])
    end
    position = last + 1
    if position > #queue then
        queue = nil
    end
end
end)
