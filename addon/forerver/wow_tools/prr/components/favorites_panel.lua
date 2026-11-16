WoWTools.prr.RegisterSource(function(...)
-- favorites_panel.lua -- the favorite items, docked to the left edge of the
-- item window (components/side_list_panel.lua). A click opens the item in the
-- window, the small cross drops it from the favorites, an item dragged onto
-- the panel becomes a favorite.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Favorites = ns.Dataflows.Favorites
local ItemNames = ns.Dataflows.ItemNames
local Text = ns.Localization.Text

local FavoritesPanel = {}
ns.Components.FavoritesPanel = FavoritesPanel

local LOADING_NAME = "..."

local panel = nil

local function Fill(row, itemID)
    row.icon:SetTexture(C_Item.GetItemIconByID(itemID))
    row.text:SetText(ItemNames.ItemName(itemID) or LOADING_NAME)
end

local function ShowItemTooltip(row, itemID)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
    ns.Wowhead.SetHovered("item", itemID)
end

local function HideItemTooltip()
    GameTooltip:Hide()
    ns.Wowhead.SetHovered(nil)
end

-- window -- the item window; options: onSelect(itemID) -- a click on a row,
-- onChanged() -- the favorites changed (stars everywhere are redrawn).
function FavoritesPanel.Toggle(window, options)
    if not panel then
        panel = ns.Components.SideListPanel.Create(window, {
            side = "LEFT",
            title = Text("favorites.title"),
            emptyText = Text("favorites.empty"),
            hint = Text("favorites.drop_hint"),
            entries = Favorites.Items,
            fill = Fill,
            onSelect = options.onSelect,
            itemOf = function(itemID) return itemID end,
            onRemove = function(itemID)
                Favorites.Remove(itemID)
                options.onChanged()
            end,
            onEnter = ShowItemTooltip,
            onLeave = HideItemTooltip,
            onDropItem = function(itemID)
                Favorites.Add(itemID)
                options.onChanged()
            end,
        })
    end
    panel:Toggle()
end

function FavoritesPanel.Refresh()
    if panel then
        panel:Refresh()
    end
end
end)
