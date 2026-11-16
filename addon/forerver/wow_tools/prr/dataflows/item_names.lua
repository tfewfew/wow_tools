WoWTools.prr.RegisterSource(function(...)
-- item_names.lua -- item and recipe names, kept between sessions.
--
-- The client gives an item name only after the server sent the item, one by
-- one, so lists re-sorted while names kept coming. Every name seen is saved in
-- ns.db.itemNames and given right away next time, until the game version (or
-- the client's language) changes;
-- services/item_name_warmup.lua asks the server for the missing ones at login.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local ItemNames = {}
ns.Dataflows.ItemNames = ItemNames

-- Modern clients (Forever among them) have no global GetItemInfo, only C_Item.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- The saved names are kept until the game version (or the client's language)
-- changes: then every name is asked anew.
local function GameVersionKey()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build) .. " " .. GetLocale()
end

local savedItems = nil   -- ns.db.itemNames.items, checked against the game version once per session

local function SavedItems()
    if savedItems then
        return savedItems
    end
    local cache = ns.db.itemNames
    local versionKey = GameVersionKey()
    if cache.version ~= versionKey then
        cache.version = versionKey
        cache.items = {}
    end
    savedItems = cache.items
    return savedItems
end

-- Saves the name if the client knows it now; true if the name is saved.
function ItemNames.Remember(itemID)
    local items = SavedItems()
    if items[itemID] then
        return true
    end
    local name, _, quality = GetItemInfo(itemID)
    if not name then
        return false
    end
    items[itemID] = { name = name, quality = quality }
    return true
end

local requested = {}   -- [item id] = true: asked from the server this session

-- Asks the server for the item once per session: an item it never sends would
-- otherwise be asked on every redraw, and every answer would redraw again.
function ItemNames.Request(itemID)
    if requested[itemID] then return end
    requested[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- { name, quality }: the saved one, else from the client (and saved); nil --
-- not known yet, it is requested from the server.
local function Lookup(itemID)
    if ItemNames.Remember(itemID) then
        return SavedItems()[itemID]
    end
    ItemNames.Request(itemID)
    return nil
end

function ItemNames.IsKnown(itemID)
    return SavedItems()[itemID] ~= nil
end

-- Item name colored by its quality, or nil while it is not known.
function ItemNames.ItemName(itemID)
    local item = Lookup(itemID)
    if not item then
        return nil
    end
    local qualityColor = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
    if qualityColor and qualityColor.hex then
        return qualityColor.hex .. item.name .. "|r"
    end
    return item.name
end

-- Item name without colors, or nil while it is not known.
function ItemNames.ItemPlainName(itemID)
    local item = Lookup(itemID)
    return item and item.name
end

-- Name of a recipe: the created item, else the recipe spell (enchants), else
-- the English name from the base. nil -- the item is not known yet.
function ItemNames.RecipeName(recipe)
    if recipe.item then
        return ItemNames.ItemName(recipe.item)
    end
    return ns.GameData.SpellName(recipe.spellID) or recipe.name
end

-- The same name without colors, for search.
function ItemNames.RecipePlainName(recipe)
    if recipe.item then
        return ItemNames.ItemPlainName(recipe.item)
    end
    return ns.GameData.SpellName(recipe.spellID) or recipe.name
end
end)
