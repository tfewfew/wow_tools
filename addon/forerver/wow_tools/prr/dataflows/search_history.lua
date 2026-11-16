WoWTools.prr.RegisterSource(function(...)
-- search_history.lua -- what was looked at in the item window: items put into
-- the slot and search texts, newest first, at most Config.HISTORY_LIMIT, kept
-- between sessions in ns.db.history. Looking at something again moves it to the
-- top instead of adding it twice.
--
-- An entry: { kind = "item", itemID = 2318 } or { kind = "search", text = "boots" }.

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local SearchHistory = {}
ns.Dataflows.SearchHistory = SearchHistory

local function IsSame(a, b)
    return a.kind == b.kind and a.itemID == b.itemID and a.text == b.text
end

function SearchHistory.Remove(entry)
    local history = ns.db.history
    for i = #history, 1, -1 do
        if IsSame(history[i], entry) then
            table.remove(history, i)
        end
    end
end

local function Add(entry)
    local history = ns.db.history
    SearchHistory.Remove(entry)
    table.insert(history, 1, entry)
    while #history > ns.Config.HISTORY_LIMIT do
        table.remove(history)
    end
end

function SearchHistory.AddItem(itemID)
    Add({ kind = "item", itemID = itemID })
end

-- Search texts are saved trimmed; an empty one is not saved.
function SearchHistory.AddSearch(text)
    local trimmed = text and text:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" then
        Add({ kind = "search", text = trimmed })
    end
end

-- The entries, newest first (the saved table itself: do not change it).
function SearchHistory.Entries()
    return ns.db.history
end

function SearchHistory.Clear()
    wipe(ns.db.history)
end
end)
