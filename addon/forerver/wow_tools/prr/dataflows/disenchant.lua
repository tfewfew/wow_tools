WoWTools.prr.RegisterSource(function(...)
-- disenchant.lua -- what an item disenchants into (constants/disenchant_results.lua):
-- uncommon, rare and epic weapons and armor, by the item level the client gives.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local DisenchantResults = ns.Constants.DisenchantResults

local Disenchant = {}
ns.Dataflows.Disenchant = Disenchant

local CLASS_WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local CLASS_ARMOR = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
local QUALITY_UNCOMMON = 2
local QUALITY_RARE = 3
local QUALITY_EPIC = 4

local function Bands(quality, classID)
    if quality == QUALITY_UNCOMMON then
        if classID == CLASS_WEAPON then
            return DisenchantResults.UNCOMMON_WEAPON
        end
        return DisenchantResults.UNCOMMON_ARMOR
    elseif quality == QUALITY_RARE then
        return DisenchantResults.RARE
    elseif quality == QUALITY_EPIC then
        return DisenchantResults.EPIC
    end
    return nil
end

-- { { item, chance, min, max }, ... } or nil: not weapon or armor, not
-- uncommon..epic, above the tables, or the client does not know the item yet.
function Disenchant.Results(itemID)
    if DisenchantResults.NOT_DISENCHANTABLE[itemID] then return nil end
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    local _, _, quality, itemLevel, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
    if classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR then return nil end
    if not itemLevel then return nil end
    local bands = Bands(quality, classID)
    if not bands then return nil end
    for _, band in ipairs(bands) do
        if itemLevel <= band.maxLevel then
            return band
        end
    end
    return nil
end

-- The average worth of one disenchant by the auction prices of the planner's
-- scan (copper), or nil if a material has no price.
function Disenchant.AverageValue(results)
    local value = 0
    for _, result in ipairs(results) do
        local price = ns.Dataflows.AuctionPrices.Get(result[1])
        if not price then return nil end
        value = value + price * result[2] / 100 * (result[3] + result[4]) / 2
    end
    return math.floor(value + 0.5)
end
end)
