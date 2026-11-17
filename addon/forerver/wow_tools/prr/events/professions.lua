WoWTools.prr.RegisterSource(function(...)
local _, ns = ...

ns.Events.On("ADDON_LOADED", function(name)
    if name == "Blizzard_Professions" and ns.db then
        ns.Components.CraftingSkillRange.Setup()
    end
end)
end)
