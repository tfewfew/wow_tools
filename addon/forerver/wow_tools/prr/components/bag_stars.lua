WoWTools.prr.RegisterSource(function(...)
-- bag_stars.lua -- the favorite star on item buttons of the bags and the bank
-- (the game's bags, BagBrother / Bagnon). events/bag_stars.lua calls Decorate
-- whenever a button gets its item; buttons seen once are kept (weakly), so a
-- change of the favorites redraws their stars at once.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Favorites = ns.Dataflows.Favorites

local BagStars = {}
ns.Components.BagStars = BagStars

local decorated = setmetatable({}, { __mode = "k" })   -- [button] = true

-- The item of a bag button: BagBrother keeps it in button.info, the game's
-- buttons know their bag and slot. Other buttons get here too (the bag
-- buttons of BagBrother have a bag id but no slot: their id is the bag's).
local function ButtonItemID(button)
    local info = rawget(button, "info")
    if type(info) == "table" and info.itemID then
        return info.itemID
    end
    local hasSlot = button.GetBagID and button.GetID and C_Container and C_Container.GetContainerItemID
    if not hasSlot then return nil end
    local ok, bagID = pcall(button.GetBagID, button)
    local slot = button:GetID()
    if not (ok and type(bagID) == "number" and type(slot) == "number" and slot >= 1) then
        return nil
    end
    local found, itemID = pcall(C_Container.GetContainerItemID, bagID, slot)
    return found and itemID or nil
end

function BagStars.Decorate(button)
    if not (button and ns.db) then return end
    local itemID = ButtonItemID(button)
    local isFavorite = Favorites.IsFavorite(itemID)
    if isFavorite or button.prrFavoriteStar then
        ns.UI.SetFavoriteStar(button, isFavorite)
    end
    decorated[button] = true
end

-- After the favorites changed.
function BagStars.RefreshAll()
    for button in pairs(decorated) do
        BagStars.Decorate(button)
    end
end
end)
