WoWTools.prr.RegisterSource(function(...)
-- history_panel.lua -- the history of the item window, docked to its right
-- edge (components/side_list_panel.lua). Rows: an item -- its icon, name and
-- tooltip; a search -- a magnifier and the text. A click opens the entry
-- again, the small cross drops it from the history.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Favorites = ns.Dataflows.Favorites
local ItemNames = ns.Dataflows.ItemNames
local SearchHistory = ns.Dataflows.SearchHistory
local Text = ns.Localization.Text

local HistoryPanel = {}
ns.Components.HistoryPanel = HistoryPanel

-- the magnifier of the game's search field (SearchBoxTemplate)
local SEARCH_ICON_ATLAS = "common-search-magnifyingglass"
local ROW_STAR_SIZE = 9
local LOADING_NAME = "..."

local panel = nil

local function Fill(row, entry)
    if entry.kind == "item" then
        row.icon:SetTexCoord(0, 1, 0, 1)
        row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemID))
        row.text:SetText(ItemNames.ItemName(entry.itemID) or LOADING_NAME)
        ns.UI.SetFavoriteStar(row.iconFrame, Favorites.IsFavorite(entry.itemID), ROW_STAR_SIZE)
    else
        row.icon:SetAtlas(SEARCH_ICON_ATLAS)
        row.text:SetText(Text("history.search", entry.text))
        ns.UI.SetFavoriteStar(row.iconFrame, false)
    end
end

local function ShowItemTooltip(row, entry)
    if entry.kind ~= "item" then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(entry.itemID)
    GameTooltip:Show()
    ns.Wowhead.SetHovered("item", entry.itemID)
end

local function HideItemTooltip()
    GameTooltip:Hide()
    ns.Wowhead.SetHovered(nil)
end

-- window -- the item window; onSelect(entry) -- a click on a row.
function HistoryPanel.Toggle(window, onSelect)
    if not panel then
        panel = ns.Components.SideListPanel.Create(window, {
            side = "RIGHT",
            title = Text("history.title"),
            emptyText = Text("history.empty"),
            entries = SearchHistory.Entries,
            fill = Fill,
            onSelect = onSelect,
            itemOf = function(entry) return entry.kind == "item" and entry.itemID or nil end,
            onRemove = SearchHistory.Remove,
            onEnter = ShowItemTooltip,
            onLeave = HideItemTooltip,
            footer = { text = Text("history.clear"), onClick = SearchHistory.Clear },
        })
    end
    panel:Toggle()
end

function HistoryPanel.Refresh()
    if panel then
        panel:Refresh()
    end
end
end)
