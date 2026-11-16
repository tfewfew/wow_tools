WoWTools.prr.RegisterSource(function(...)
-- craft_button.lua -- the Craft button of a step of the leveling plan
-- (services/craft_service.lua does the craft):
--
--   a recipe that makes an item -- the icon of the profession; a click crafts
--     the crafts of the step;
--   an enchant -- the item it goes on is chosen once (the window of
--     components/enchant_target_window.lua) and remembered for the enchant
--     (settings.planner.enchantTargets): its icon on the button, every next
--     click enchants it at once; a right click forgets it. An enchant with no
--     item of its own takes the last one chosen when that one can take it
--     (the same bracers for every bracer enchant). An item gone or not fitting
--     any more -- the window again. With Auto-replace enchant on, a click while
--     the game asks "Replace the enchant?" presses its Yes -- the way the macro
--     /click StaticPopup1Button1 does: a secure action button over the Craft
--     button (SecureActionButtonTemplate, see Cover) gets that macro for the
--     click; the game does not let an addon's own call through. The question breaks off the
--     casts in a row: one more click goes on, with no questions (the same
--     enchant again).

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Text = ns.Localization.Text

local CraftButton = {}
ns.Components.CraftButton = CraftButton

local SIZE = 24

local function Settings()
    return ns.db.settings.planner
end

-- The item an enchant goes on: { guid, itemID }, nil -- none chosen.
local function TargetOf(recipe)
    return Settings().enchantTargets[recipe.spellID]
end

local function SetTarget(recipe, item)
    local settings = Settings()
    if item then
        local target = { guid = item.guid, itemID = item.itemID }
        settings.enchantTargets[recipe.spellID] = target
        settings.lastEnchantTarget = target
        return
    end
    local target = settings.enchantTargets[recipe.spellID]
    settings.enchantTargets[recipe.spellID] = nil
    local last = settings.lastEnchantTarget
    if target and last and last.guid == target.guid then
        settings.lastEnchantTarget = nil
    end
end

-- The item can take the enchant now: true / false, nil -- the game does not tell.
local function CanTake(recipe, guid)
    local api = C_TradeSkillUI
    if not (api and api.GetEnchantItems) then return nil end
    local ok, guids = pcall(api.GetEnchantItems, recipe.spellID, {})
    if not ok or type(guids) ~= "table" then return nil end
    for _, candidate in ipairs(guids) do
        if candidate == guid then
            return true
        end
    end
    return false
end

local function UpdateIcon(button)
    local recipe = button.step.recipe
    local target = ns.Services.CraftService.IsEnchant(recipe) and TargetOf(recipe)
    local icon = target and C_Item.GetItemIconByID(target.itemID)
    button.icon:SetTexture(icon or ns.GameData.ProfessionIcon(recipe.profession))
end

local function Enchant(button)
    local CraftService = ns.Services.CraftService
    local step = button.step
    local recipe = step.recipe
    local count = ns.Dataflows.SkillPlanner.StepCrafts(step)
    -- the profession window first (the click opens it, the next one goes on)
    if not CraftService.IsReady(recipe) then
        CraftService.Craft(recipe, count)
        return
    end
    local target = TargetOf(recipe)
    local last = Settings().lastEnchantTarget
    if not target and last and CanTake(recipe, last.guid) then
        SetTarget(recipe, last)
        target = last
    end
    if target and CanTake(recipe, target.guid) ~= false then
        UpdateIcon(button)
        CraftService.CraftEnchant(recipe, count, target.guid)
        return
    end
    if target then
        SetTarget(recipe, nil)
        UpdateIcon(button)
    end
    ns.Components.EnchantTargetWindow.Show(recipe, count, function(item)
        SetTarget(recipe, item)
        UpdateIcon(button)
        CraftService.CraftEnchant(recipe, count, item.guid)
    end)
end

-- The secure button over the hovered Craft button. The game does not let a
-- protected (secure) frame hang on the regions of an addon's window, and a
-- window with one inside would turn protected itself (no hiding or scrolling
-- it in combat) -- so there is one, on the screen (UIParent), put over the
-- Craft button the mouse comes to, out of combat; the Craft buttons stay
-- plain (a click on one -- in combat, the cover away -- crafts the plain way).
local SECURE_TEMPLATE = "SecureActionButtonTemplate"
local COVER_NAME = "PRRCraftButtonCover"
local COVER_STRATA = "FULLSCREEN_DIALOG"
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

local cover = nil

-- A secure action button gets the press and the release (the game wants both
-- registered); it acts on the press with "ActionButtonUseKeyDown" on, else on
-- the release -- this does the same.
local function IsActingClick(down)
    local onDown = GetCVarBool ~= nil and GetCVarBool("ActionButtonUseKeyDown") or false
    return (down and true or false) == (onDown and true or false)
end

-- the answer of the macro (/script ReplaceEnchant()), for an enchant from the
-- profession window -- C_Item.ReplaceTradeskillEnchant (the Yes of its
-- REPLACE_TRADESKILL_ENCHANT dialog); with no question it does nothing
local REPLACE_LINE = "/run local i = C_Item or {} local f = i.ReplaceTradeskillEnchant or i.ReplaceEnchant or ReplaceEnchant if f then f() end"

-- The secure part of the click to come (secure -- the cover; nil -- a plain
-- click), as the macro of the player does it:
--   afterCast -- the cast just started: REPLACE_LINE (the dialog comes later);
--   the "Replace the enchant?" dialog on the screen -- its Yes: /click
--   StaticPopupNButton1, for that dialog only (not a blind StaticPopup1).
-- Nothing with Auto-replace enchant off. True -- the dialog was there.
local function ArmSecureYes(secure, isEnchant, afterCast)
    if not secure or (InCombatLockdown and InCombatLockdown()) then return false end
    local lines = {}
    local isOn = isEnchant and Settings().autoReplaceEnchant
    if isOn and afterCast then
        table.insert(lines, REPLACE_LINE)
    end
    local dialog = isOn and ns.Services.CraftService.FindReplaceDialog()
    local name = dialog and dialog.GetName and dialog:GetName() or nil
    if name then
        table.insert(lines, "/click " .. name .. "Button1")
    end
    local macro = #lines > 0 and table.concat(lines, "\n") or nil
    secure:SetAttribute("type1", macro and "macro" or nil)
    secure:SetAttribute("macrotext1", macro)
    if ns.db.settings.developer and isEnchant then
        local dialogs = {}
        for _, shown in ipairs(ns.Services.CraftService.ShownDialogs()) do
            table.insert(dialogs, (shown.frame.GetName and shown.frame:GetName() or "?") .. "=" .. tostring(shown.which))
        end
        ns.Utilities.Print(string.format("craft click: auto-replace %s, dialog %s, shown dialogs [%s], macro %s",
            tostring(isOn), tostring(name), table.concat(dialogs, ", "), tostring(macro)))
    end
    return name ~= nil
end

-- A click on a Craft button; secure -- the cover over it (its secure action
-- comes after this).
local function Act(button, mouseButton, secure)
    local step = button.step
    if not step then return end
    local recipe = step.recipe
    local isEnchant = ns.Services.CraftService.IsEnchant(recipe)
    if mouseButton == "RightButton" then
        if isEnchant and TargetOf(recipe) then
            SetTarget(recipe, nil)
            UpdateIcon(button)
            ns.Utilities.Print(Text("planner.enchant_target_cleared"))
        end
        return
    end
    if ArmSecureYes(secure, isEnchant, false) then
        -- the macro of the cover answers yes; the casts in a row stopped at the question
        ns.Utilities.Print(Text("planner.enchant_replaced_continue"))
        return
    end
    if isEnchant then
        Enchant(button)
        -- answered in this same click, as the macro does: the cast, then
        -- /script ReplaceEnchant() (and /click of the dialog when it is there)
        ArmSecureYes(secure, isEnchant, true)
        return
    end
    ns.Services.CraftService.Craft(recipe, ns.Dataflows.SkillPlanner.StepCrafts(step))
end

local function ShowTooltip(owner, button)
    local recipe = button.step and button.step.recipe
    if not recipe then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(Text("planner.craft"))
    if ns.Services.CraftService.IsEnchant(recipe) then
        local target = TargetOf(recipe)
        if target then
            local name = ns.Dataflows.ItemNames.ItemName(target.itemID) or "..."
            GameTooltip:AddLine(Text("planner.enchant_target", name), 0.4, 1, 0.4, true)
            GameTooltip:AddLine(Text("planner.enchant_target_hint"), 1, 1, 1, true)
        else
            GameTooltip:AddLine(Text("planner.enchant_pick_first"), 1, 1, 1, true)
        end
    end
    GameTooltip:AddLine(Text("planner.craft_hint"), 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideCover()
    if not cover or (InCombatLockdown and InCombatLockdown()) then return end
    cover:Hide()
    cover.target = nil
end

local function CreateCover()
    cover = CreateFrame("Button", COVER_NAME, UIParent, SECURE_TEMPLATE)
    cover:SetFrameStrata(COVER_STRATA)
    cover:RegisterForClicks("AnyUp", "AnyDown")
    cover:SetHighlightTexture(HIGHLIGHT_TEXTURE, "ADD")
    cover:Hide()
    cover:SetScript("PreClick", function(self, mouseButton, down)
        if self.target and IsActingClick(down) then
            Act(self.target, mouseButton, self)
        end
    end)
    cover:SetScript("OnEnter", function(self)
        if self.target then
            ShowTooltip(self, self.target)
        end
    end)
    cover:SetScript("OnLeave", function()
        GameTooltip:Hide()
        HideCover()
    end)
    -- the button under it went away (the window closed, the list scrolled)
    cover:SetScript("OnUpdate", function(self)
        local target = self.target
        local isGone = not target or not target:IsVisible() or not target:IsMouseOver()
        if isGone then
            HideCover()
        end
    end)
end

-- The cover over a Craft button the mouse came to: on the screen, where the
-- button is (by coordinates -- not hung on it).
local function Cover(button)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not cover then
        CreateCover()
    end
    local x, y = button:GetCenter()
    if not (x and y) then return false end
    local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
    cover:ClearAllPoints()
    cover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    cover:SetSize(button:GetWidth() * scale, button:GetHeight() * scale)
    cover:SetAttribute("type1", nil)
    cover:SetAttribute("macrotext1", nil)
    cover.target = button
    cover:Show()
    ShowTooltip(cover, button)
    return true
end

-- The button of a row; button:SetStep(step) fills it.
function CraftButton.Create(parent)
    local button = ns.UI.IconToolButton(parent, {
        size = SIZE,
        icon = ns.GameData.ProfessionIcon(nil),
        tooltip = Text("planner.craft"),
        -- a plain click: the cover is not there (in combat)
        onClick = function(self, mouseButton)
            Act(self, mouseButton, nil)
        end,
    })
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", function(self)
        if not Cover(self) then
            ShowTooltip(self, self)
        end
    end)

    function button:SetStep(step)
        self.step = step
        UpdateIcon(self)
    end
    return button
end

-- The cover, for the tests.
function CraftButton.Cover()
    return cover
end
end)
