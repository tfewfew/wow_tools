local _, addon = ...

-- The host supplies the shared settings canvas and account-level storage.
function addon:CreateBlizzConfig() end
function addon:OpenBlizzConfig() WoWTools.modules.ls_toasts.Show() end
local createAceConfig = addon.CreateAceConfig
function addon:CreateAceConfig()
    createAceConfig(self)
    self.OpenAceConfig = function() WoWTools.modules.ls_toasts.Show() end
end

addon.Modernize = addon.P.Modernize

if addon.GAMEVERSION.TitanReforged then
    function addon.E:GetItemLevel(link)
        return C_Item.GetDetailedItemLevelInfo(link) or 0
    end
end

addon.E:RegisterEvent("PLAYER_LOGIN", function() addon.ready = true end)
