WoWTools.prr.RegisterSource(function(...)
-- craft_service.lua -- crafts a recipe of the leveling plan from its row: the
-- game crafts only with the profession window open (C_TradeSkillUI) and only
-- from a click (a craft started by a timer is not let through). So a click
-- with the window closed opens it, the next click crafts (the tooltip of the
-- button tells it).
--
-- The crafts: as many as asked, no more than the bags have reagents for
-- (GetCraftableCount). An enchant needs an item to go on: the click opens the
-- list of them (components/enchant_target_window.lua), a click on one there
-- enchants it (CraftEnchant).

local ADDON, ns = ...
ns.Services = ns.Services or {}

local Text = ns.Localization.Text

local CraftService = {}
ns.Services.CraftService = CraftService

local PREPARE_PAUSE_SECONDS = 2   -- between two openings of the profession window
local ENCHANTING = 333

local preparedAt = -PREPARE_PAUSE_SECONDS

-- An enchant: a spell of Enchanting that makes no item.
function CraftService.IsEnchant(recipe)
    return recipe.item == nil and recipe.profession == ENCHANTING
end

-- A recipe this service can craft: one that makes an item, or an enchant
-- (put on an item of the character).
function CraftService.CanCraft(recipe)
    local api = C_TradeSkillUI
    if not api then return false end
    if CraftService.IsEnchant(recipe) then
        return api.CraftEnchant ~= nil and api.GetEnchantItems ~= nil
    end
    return recipe.item ~= nil and api.CraftRecipe ~= nil
end

-- The profession window is open and shows the recipe as learned.
local function IsReady(recipe)
    local api = C_TradeSkillUI
    if api.IsTradeSkillReady and not api.IsTradeSkillReady() then return false end
    if api.IsTradeSkillLinked and api.IsTradeSkillLinked() then return false end
    local ok, info = pcall(api.GetRecipeInfo, recipe.spellID)
    return ok and type(info) == "table" and info.learned == true
end

CraftService.IsReady = IsReady

-- "Replace the enchant?": an enchant from the profession window asks with the
-- first one (its Yes -- C_Item.ReplaceTradeskillEnchant), the old way of
-- enchanting (a spell on an item) with the second (C_Item.ReplaceEnchant)
local REPLACE_DIALOGS = { "REPLACE_TRADESKILL_ENCHANT", "REPLACE_ENCHANT" }

-- The dialog "Replace the enchant?" on the screen, nil -- none.
local MAX_DIALOGS = 4   -- StaticPopup1..4 when the client has no STATICPOPUP_NUMDIALOGS

-- The dialog windows of the game on the screen: { { frame, which } }.
function CraftService.ShownDialogs()
    local shown = {}
    for i = 1, rawget(_G, "STATICPOPUP_NUMDIALOGS") or MAX_DIALOGS do
        local frame = rawget(_G, "StaticPopup" .. i)
        if frame and frame.IsShown and frame:IsShown() then
            table.insert(shown, { frame = frame, which = frame.which })
        end
    end
    return shown
end

function CraftService.FindReplaceDialog()
    for _, which in ipairs(REPLACE_DIALOGS) do
        local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
        if dialog then return dialog end
    end
    -- the dialogs one by one: the function above may not know them
    for _, shown in ipairs(CraftService.ShownDialogs()) do
        for _, which in ipairs(REPLACE_DIALOGS) do
            if shown.which == which then
                return shown.frame
            end
        end
    end
    return nil
end

function CraftService.IsReplaceAsked()
    return CraftService.FindReplaceDialog() ~= nil
end


-- Crafts now: true, or false and why not.
local function CraftNow(recipe, count)
    local api = C_TradeSkillUI
    local craftable = count
    if api.GetCraftableCount then
        local ok, available = pcall(api.GetCraftableCount, recipe.spellID)
        if ok and type(available) == "number" then
            craftable = math.min(count, available)
        end
    end
    if craftable < 1 then
        return false, Text("planner.craft_no_reagents")
    end
    local ok = pcall(api.CraftRecipe, recipe.spellID, craftable)
    if not ok then
        return false, Text("planner.craft_failed")
    end
    return true, Text("planner.craft_started", craftable, ns.Dataflows.ItemNames.RecipeName(recipe) or "")
end

local function Report(_, message)
    if message then
        ns.Utilities.Print(message)
    end
end

-- Opens the profession window of a recipe when it is not ready yet (a few
-- tenths of a second to load). Not more often than PREPARE_PAUSE_SECONDS: the
-- game toggles the window. True -- it is opening.
local function OpenProfession(recipe)
    local api = C_TradeSkillUI
    if GetTime() - preparedAt < PREPARE_PAUSE_SECONDS then
        return true
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Professions")
    end
    local isOpened = api.OpenTradeSkill ~= nil and pcall(api.OpenTradeSkill, recipe.profession)
    if isOpened then
        preparedAt = GetTime()
    end
    return isOpened
end

-- Crafts count of a recipe (the crafts of a plan step); the result goes to the chat.
function CraftService.Craft(recipe, count)
    if InCombatLockdown and InCombatLockdown() then
        Report(false, Text("planner.craft_combat"))
        return
    end
    if not CraftService.CanCraft(recipe) then
        Report(false, Text("planner.craft_failed"))
        return
    end
    if IsReady(recipe) then
        if CraftService.IsEnchant(recipe) then
            ns.Components.EnchantTargetWindow.Show(recipe, count)
            return
        end
        Report(CraftNow(recipe, count))
        return
    end
    -- the window closed: open it, the next click crafts
    if OpenProfession(recipe) then
        Report(false, Text("planner.craft_opening"))
        return
    end
    Report(false, Text("planner.craft_failed"))
end

-- Puts an enchant on an item of the character (its GUID) count times, no more
-- than the bags have reagents for; the result goes to the chat.
function CraftService.CraftEnchant(recipe, count, itemGUID)
    if InCombatLockdown and InCombatLockdown() then
        Report(false, Text("planner.craft_combat"))
        return
    end
    local api = C_TradeSkillUI
    if not IsReady(recipe) then
        Report(false, Text("planner.craft_opening"))
        OpenProfession(recipe)
        return
    end
    local location = C_Item.GetItemLocation and C_Item.GetItemLocation(itemGUID)
    if not location then
        Report(false, Text("planner.craft_failed"))
        return
    end
    local casts = count
    if api.GetCraftableCount then
        local ok, available = pcall(api.GetCraftableCount, recipe.spellID)
        if ok and type(available) == "number" then
            casts = math.min(count, available)
        end
    end
    if casts < 1 then
        Report(false, Text("planner.craft_no_reagents"))
        return
    end
    local ok = pcall(api.CraftEnchant, recipe.spellID, casts, {}, location, false)
    if not ok then
        Report(false, Text("planner.craft_failed"))
        return
    end
    local link = C_Item.GetItemLinkByGUID and C_Item.GetItemLinkByGUID(itemGUID)
    Report(true, Text("planner.enchant_started", casts, ns.Dataflows.ItemNames.RecipeName(recipe) or "", link or ""))
end
end)
