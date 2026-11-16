WoWTools.prr.RegisterSource(function(...)
-- favorites.lua -- the items marked with a star (the star in the item window,
-- dropping an item on the favorites panel). Kept between sessions in
-- ns.db.favorites, newest first; a favorite item carries a star everywhere --
-- bags, bank, the item window (components/bag_stars.lua).

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local Favorites = {}
ns.Dataflows.Favorites = Favorites

local lookup = nil   -- [item id] = true, built from the saved list on demand

local function Lookup()
    if not lookup then
        lookup = {}
        for _, itemID in ipairs(ns.db.favorites) do
            lookup[itemID] = true
        end
    end
    return lookup
end

function Favorites.IsFavorite(itemID)
    if not (itemID and ns.db) then
        return false
    end
    return Lookup()[itemID] == true
end

function Favorites.Add(itemID)
    if Favorites.IsFavorite(itemID) then return end
    table.insert(ns.db.favorites, 1, itemID)
    lookup = nil
end

function Favorites.Remove(itemID)
    local list = ns.db.favorites
    for i = #list, 1, -1 do
        if list[i] == itemID then
            table.remove(list, i)
        end
    end
    lookup = nil
end

function Favorites.Toggle(itemID)
    if Favorites.IsFavorite(itemID) then
        Favorites.Remove(itemID)
    else
        Favorites.Add(itemID)
    end
end

-- The favorite item ids, newest first (the saved list itself: do not change it).
function Favorites.Items()
    return ns.db.favorites
end
end)
