WoWTools.prr.RegisterSource(function(...)
-- enchant_target_window.lua -- the items an enchant of the leveling plan can
-- go on, for its Craft button: every one the character has that the game
-- lets it enchant (C_TradeSkillUI.GetEnchantItems); a click on one enchants
-- it the crafts of the step (services/craft_service.lua).
--
--   Enchant Bracer - Minor Health
--   [icon] Cheap Bracers
--   [icon] Linen Bracers
--   ...

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local EnchantTargetWindow = {}
ns.Components.EnchantTargetWindow = EnchantTargetWindow

local FRAME_NAME = "PRREnchantTargetWindow"
local WIDTH = 320
local HEIGHT = 360
local HEADER_HEIGHT = 34
local PADDING = 14
local HINT_HEIGHT = 30
local ROW_HEIGHT = 30
local ICON_SIZE = 26

local frame = nil
local shown = nil   -- { recipe, count, items = { { guid, itemID, link } } }

-- The items of the character the enchant can go on.
local function TargetItems(recipe)
    local api = C_TradeSkillUI
    local items = {}
    if not (api and api.GetEnchantItems) then return items end
    local ok, guids = pcall(api.GetEnchantItems, recipe.spellID, {})
    if not ok or type(guids) ~= "table" then return items end
    for _, guid in ipairs(guids) do
        local itemID = C_Item.GetItemIDByGUID and C_Item.GetItemIDByGUID(guid)
        local link = C_Item.GetItemLinkByGUID and C_Item.GetItemLinkByGUID(guid)
        if itemID then
            table.insert(items, { guid = guid, itemID = itemID, link = link })
        end
    end
    return items
end

local function FillRow(row, item)
    row.item = item
    row.icon:SetItem(item.itemID)
    row.name:SetText(item.link or ns.Dataflows.ItemNames.ItemName(item.itemID) or "...")
end

local function Refresh()
    local items = shown.items
    frame.hint:SetText(#items > 0 and Text("planner.enchant_pick_hint", shown.count)
        or Text("planner.enchant_no_items"))
    frame.list:Fill(#items, function(row, index)
        FillRow(row, items[index])
    end)
end

local function Create()
    frame = ns.UI.Panel(FRAME_NAME, UIParent, {
        width = WIDTH,
        height = HEIGHT,
        title = "",
        gameSkin = true,
    })
    frame:SetPoint("CENTER")
    table.insert(UISpecialFrames, FRAME_NAME)   -- Escape closes the window

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", PADDING, -HEADER_HEIGHT)
    frame.hint:SetPoint("RIGHT", -PADDING, 0)
    frame.hint:SetHeight(HINT_HEIGHT)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetWordWrap(true)

    frame.list = ns.UI.ColumnList(frame, {
        columns = {},
        plain = true,
        rowHeight = ROW_HEIGHT,
        iconSize = ICON_SIZE,
        onClick = function(row)
            if not row.item then return end
            if ns.Utilities.InsertChatLink("item", row.item.itemID) then return end
            local recipe, count, item, onPick = shown.recipe, shown.count, row.item, shown.onPick
            frame:Hide()
            if onPick then
                onPick(item)
                return
            end
            ns.Services.CraftService.CraftEnchant(recipe, count, item.guid)
        end,
        onEnter = function(row)
            if not row.item then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByGUID then
                GameTooltip:SetItemByGUID(row.item.guid)
            elseif row.item.link then
                GameTooltip:SetHyperlink(row.item.link)
            end
            GameTooltip:Show()
        end,
    })
    frame.list:SetPoint("TOPLEFT", frame.hint, "BOTTOMLEFT", 0, -4)
    frame.list:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
end

-- Shows the items an enchant can go on; count -- the crafts of the step;
-- onPick(item = { guid, itemID, link }) -- the click on one (optional: it is
-- enchanted else).
function EnchantTargetWindow.Show(recipe, count, onPick)
    if not frame then
        Create()
    end
    shown = { recipe = recipe, count = count, items = TargetItems(recipe), onPick = onPick }
    frame.title:SetText(ns.Dataflows.ItemNames.RecipeName(recipe) or "")
    frame:Show()
    Refresh()
end
end)
