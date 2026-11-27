WoWTools.prr.RegisterSource(function(...)
-- utilities.lua -- chat output, default settings, lowercase for search,
-- Shift+click links into the chat, money.

local ADDON, ns = ...

local Utilities = {}
ns.Utilities = Utilities

function Utilities.Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. ns.Constants.ADDON_SHORT_TITLE .. "|r: " .. tostring(text))
end

-- Adds missing keys from defaults into target; nested tables -- recursively.
function Utilities.Defaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = Utilities.Defaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

-- Lowercase including Cyrillic. string.lower in the game only knows Latin,
-- and Cyrillic letters in UTF-8 are byte pairs: uppercase 208 144..159 -> 208 176..191,
-- uppercase 208 160..175 -> 209 128..143, uppercase Yo 208 129 -> 209 145.
local function LowerCyrillic(letter)
    local second = letter:byte(2)
    if second == 129 then
        return "\209\145"
    end
    if second < 160 then
        return string.char(208, second + 32)
    end
    return string.char(209, second - 32)
end

-- A "secret" value of the game (unit identity in a dungeon): it can be
-- printed, but an addon may not compare it, use it as a table key or read it.
-- issecretvalue tells it where the client has it; otherwise a table key is tried.
local secretProbe = {}
function Utilities.IsSecret(value)
    if value == nil then return false end
    if issecretvalue then
        return issecretvalue(value) == true
    end
    local ok = pcall(function()
        secretProbe[value] = true
        secretProbe[value] = nil
    end)
    return not ok
end

-- The value, or nil when it is secret.
function Utilities.Open(value)
    if Utilities.IsSecret(value) then return nil end
    return value
end

function Utilities.Lower(text)
    local lowered = text:lower()
    lowered = lowered:gsub("\208[\129\144-\175]", LowerCyrillic)
    return lowered
end

local function ItemLink(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    if link then
        return link
    end
    -- not cached by the client yet: a link of the name this addon keeps
    local name = ns.Dataflows.ItemNames.ItemName(itemID)
    if not name then return nil end
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local colorCode = color and color.hex or "|cffffffff"
    return colorCode .. "|Hitem:" .. itemID .. "::::::::::::|h[" .. name .. "]|h|r"
end

local function SpellLink(spellID)
    if C_Spell and C_Spell.GetSpellLink then
        return C_Spell.GetSpellLink(spellID)
    end
    return GetSpellLink and GetSpellLink(spellID)
end

-- The Shopping tab of Auctionator is shown: it takes the links of Shift+clicks
-- (it hooks ChatFrameUtil.InsertLink) and searches the auction house for them.
function Utilities.IsAuctionatorShoppingShown()
    local frame = rawget(_G, "AuctionatorShoppingFrame")
    return frame ~= nil and frame.IsVisible ~= nil and frame:IsVisible() and true or false
end

-- The shopping list API of Auctionator (Auctionator.API.v1), or nil without it.
local function AuctionatorApi()
    local auctionator = rawget(_G, "Auctionator")
    local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1
    local hasShoppingLists = type(api) == "table" and type(api.CreateShoppingList) == "function"
        and type(api.ConvertToSearchString) == "function"
    return hasShoppingLists and api or nil
end

function Utilities.HasAuctionatorShoppingLists()
    return AuctionatorApi() ~= nil
end

-- A shopping list of Auctionator: an exact search of every item with the
-- quantity to buy. entries -- { { name = "Light Leather", quantity = 12 }, ... };
-- a list of that name is replaced (Auctionator does it). True when it is made.
function Utilities.CreateAuctionatorShoppingList(listName, entries)
    local api = AuctionatorApi()
    if not api then return false end
    local callerID = ns.Constants.ADDON_SHORT_TITLE
    -- an error inside Auctionator (another version of its API) must not break the planner
    local ok = pcall(function()
        local searchStrings = {}
        for _, entry in ipairs(entries) do
            table.insert(searchStrings, api.ConvertToSearchString(callerID, {
                searchString = entry.name,
                isExact = true,
                quantity = entry.quantity,
            }))
        end
        api.CreateShoppingList(callerID, listName, searchStrings)
    end)
    return ok
end

-- Shift+click (the game's "chat link" modifier): the link of the item / spell
-- goes into the open chat input -- and to whoever hooks the game's InsertLink,
-- as the Shopping tab of Auctionator does. kind -- "item" | "spell".
-- True when the click is used up: the link went into the chat, or Auctionator
-- Shopping is shown (no second link for it, e.g. the spell after the item).
function Utilities.InsertChatLink(kind, id)
    if not (id and IsModifiedClick and IsModifiedClick("CHATLINK")) then
        return false
    end
    local link = kind == "item" and ItemLink(id) or SpellLink(id)
    if not link then return false end
    local isInserted = false
    -- the modern one first: Auctionator hooks it when it is there
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        isInserted = ChatFrameUtil.InsertLink(link) and true or false
    elseif ChatEdit_InsertLink then
        isInserted = ChatEdit_InsertLink(link) and true or false
    end
    return isInserted or Utilities.IsAuctionatorShoppingShown()
end

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000
-- the coins of the game's money frames, as in bags and on the auction house
-- (GetCoinTextureString of this client draws them dim)
local COIN_ICON = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:%d|t"

-- Copper as gold / silver / copper with the coin icons, zero parts left out;
-- a loss gets a minus. coinOffsetY -- the coins lowered by it (a negative
-- number): in a larger font they stand too high (0 -- the small text of tables).
function Utilities.Money(copper, coinOffsetY)
    local offset = coinOffsetY or 0
    local GOLD_ICON = string.format(COIN_ICON, "Gold", offset)
    local SILVER_ICON = string.format(COIN_ICON, "Silver", offset)
    local COPPER_ICON = string.format(COIN_ICON, "Copper", offset)
    local amount = math.floor(math.abs(copper) + 0.5)
    local gold = math.floor(amount / COPPER_PER_GOLD)
    local silver = math.floor((amount % COPPER_PER_GOLD) / COPPER_PER_SILVER)
    local rest = amount % COPPER_PER_SILVER

    -- from the highest coin down to copper, the lower ones in two digits even
    -- when zero: 4s 00c, 1g 05s 00c (12c -- just copper)
    local parts = {}
    if gold > 0 then
        table.insert(parts, gold .. GOLD_ICON)
        table.insert(parts, string.format("%02d", silver) .. SILVER_ICON)
    elseif silver > 0 then
        table.insert(parts, silver .. SILVER_ICON)
    end
    if #parts > 0 then
        table.insert(parts, string.format("%02d", rest) .. COPPER_ICON)
    else
        table.insert(parts, rest .. COPPER_ICON)
    end
    local text = table.concat(parts, " ")
    if copper < 0 then
        text = "-" .. text
    end
    return text
end

-- Copper as plain text for an input field: "1g 20s 5c".
function Utilities.PlainMoney(copper)
    local gold = math.floor(copper / COPPER_PER_GOLD)
    local silver = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
    local rest = copper % COPPER_PER_SILVER
    local parts = {}
    if gold > 0 then
        table.insert(parts, gold .. "g")
    end
    if silver > 0 then
        table.insert(parts, silver .. "s")
    end
    if rest > 0 or #parts == 0 then
        table.insert(parts, rest .. "c")
    end
    return table.concat(parts, " ")
end

local MONEY_UNITS = { g = COPPER_PER_GOLD, s = COPPER_PER_SILVER, c = 1 }

-- Text typed by the player as copper: "1g 20s 5c", "35s", "80c", or a bare
-- number of gold ("1.5"). Nil -- not money.
function Utilities.ParseMoney(text)
    local cleaned = Utilities.Lower(text or ""):gsub(",", "."):gsub("%s+", "")
    if cleaned == "" then
        return nil
    end
    local gold = tonumber(cleaned)
    if gold then
        return gold >= 0 and math.floor(gold * COPPER_PER_GOLD + 0.5) or nil
    end
    local copper = 0
    local rest = cleaned:gsub("(%d+%.?%d*)([gsc])", function(amount, unit)
        copper = copper + tonumber(amount) * MONEY_UNITS[unit]
        return ""
    end)
    if rest ~= "" then
        return nil
    end
    return math.floor(copper + 0.5)
end

-- How many of an item the player has in the bags and the bank.
function Utilities.ItemCount(itemID)
    local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not GetCount then
        return 0
    end
    return GetCount(itemID, true) or 0
end
end)
