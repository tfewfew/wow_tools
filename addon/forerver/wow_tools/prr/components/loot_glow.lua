WoWTools.prr.RegisterSource(function(...)
-- loot_glow.lua -- favorite items in the loot window: a pulsing gold border
-- around the row (ui/glow.lua) and the star on the icon. events/loot_glow.lua
-- calls Decorate for every row the window draws.
--
-- The loot window of this client is a list (LootFrame.ScrollBox) of rows with
-- the item button in row.Item and the loot slot in the row data; the old one
-- has buttons LootButton1..N with the slot in button.slot.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Favorites = ns.Dataflows.Favorites

local LootGlow = {}
ns.Components.LootGlow = LootGlow

local GLOW_INSET = 0
local OLD_LOOT_BUTTONS = 4   -- LOOTFRAME_NUMBUTTONS of the old window

-- The loot slot of a row: the method of the list row, its data, or the field
-- of an old button.
local function SlotOf(row)
    if row.GetSlotIndex then
        local ok, slot = pcall(row.GetSlotIndex, row)
        if ok and slot then return slot end
    end
    if row.GetElementData then
        local ok, data = pcall(row.GetElementData, row)
        if ok and type(data) == "table" and data.slotIndex then return data.slotIndex end
    end
    return rawget(row, "slot")
end

local function ItemIDOfSlot(slot)
    if not (slot and GetLootSlotLink) then return nil end
    local link = GetLootSlotLink(slot)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function LootGlow.Decorate(row)
    if not (row and ns.db) then return end
    local isFavorite = Favorites.IsFavorite(ItemIDOfSlot(SlotOf(row))) and true or false
    local isGlowing = isFavorite and ns.db.settings.lootGlow
    if isGlowing and not rawget(row, "prrLootGlow") then
        row.prrLootGlow = ns.UI.Glow(row, GLOW_INSET)
    end
    if rawget(row, "prrLootGlow") then
        row.prrLootGlow:SetShown(isGlowing)
    end
    local iconButton = rawget(row, "Item") or row
    if isFavorite or iconButton.prrFavoriteStar then
        ns.UI.SetFavoriteStar(iconButton, isFavorite)
    end
end

-- Every row the loot window shows now (after the favorites changed, and when
-- the loot changed).
function LootGlow.RefreshAll()
    if not (LootFrame and LootFrame:IsShown()) then return end
    local scrollBox = rawget(LootFrame, "ScrollBox")
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(LootGlow.Decorate)
        return
    end
    for index = 1, LOOTFRAME_NUMBUTTONS or OLD_LOOT_BUTTONS do
        local button = _G["LootButton" .. index]
        if button and button:IsShown() then
            LootGlow.Decorate(button)
        end
    end
end
end)
