WoWTools.prr.RegisterSource(function(...)
-- hotkeys.lua -- Ctrl+C over an icon of the item window: a Wowhead link to
-- copy (components/link_dialog.lua). Elsewhere Ctrl+C does nothing here.
--
-- A hidden frame listens to the keyboard and passes every key on to the game
-- (SetPropagateKeyboardInput), so nothing else stops working; Ctrl+C has no
-- game binding by default.
--
-- A keyboard frame that does not pass keys on would take all of them -- the
-- character could not move. So the keyboard is turned on only after passing
-- keys on is set, and that is done out of combat: the client may refuse it in
-- combat (a /reload during a fight).

local ADDON, ns = ...

local listener = CreateFrame("Frame", nil, UIParent)
local isListening = false

local function StartListening()
    if isListening or InCombatLockdown() then return end
    local ok = pcall(listener.SetPropagateKeyboardInput, listener, true)
    if not ok then return end
    listener:EnableKeyboard(true)
    isListening = true
end

listener:SetScript("OnKeyDown", function(_, key)
    local isCopy = key == "C" and IsControlKeyDown()
    if not isCopy then return end
    if not (ns.db and ns.db.settings.copyLink) then return end
    local target = ns.Wowhead.hovered
    if target then
        ns.Components.LinkDialog.Show(target.kind, target.id)
    end
end)

StartListening()
-- loaded in combat: once it ends
ns.Events.On("PLAYER_REGEN_ENABLED", StartListening)
end)
