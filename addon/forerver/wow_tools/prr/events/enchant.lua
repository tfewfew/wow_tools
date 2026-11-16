WoWTools.prr.RegisterSource(function(...)
-- enchant.lua -- "Replace the enchant?" while leveling Enchanting with
-- Auto-replace enchant on (settings.planner.autoReplaceEnchant): the game
-- takes the answer only from a secure click (the macro /click
-- StaticPopup1Button1), so the Craft button of the plan -- a secure action
-- button -- presses the Yes of the dialog (components/craft_button.lua). Here
-- -- the question came and is still on the screen a moment later: the chat
-- tells to click Craft once more.

local ADDON, ns = ...

local Text = ns.Localization.Text

local HINT_DELAY_SECONDS = 0.3
local HINT_PAUSE_SECONDS = 3   -- one hint for one question

local hintedAt = -HINT_PAUSE_SECONDS

local function Hint()
    if not ns.db or not ns.db.settings.planner.autoReplaceEnchant then return end
    C_Timer.After(HINT_DELAY_SECONDS, function()
        if GetTime() - hintedAt < HINT_PAUSE_SECONDS then return end
        hintedAt = GetTime()
        ns.Utilities.Print(Text("planner.enchant_replace_click"))
        if ns.db.settings.developer then
            local dialog = ns.Services.CraftService.FindReplaceDialog()
            ns.Utilities.Print("replace enchant asked: dialog " .. tostring(dialog and dialog.GetName and dialog:GetName()))
        end
    end)
end

-- the profession window asks with the first, the old enchanting with the second
ns.Events.On("REPLACE_TRADESKILL_ENCHANT", Hint)
ns.Events.On("REPLACE_ENCHANT", Hint)
end)
