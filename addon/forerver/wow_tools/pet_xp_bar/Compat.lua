local Addon = WoWTools.petXPBar
local Compat = {}
Addon.Compat = Compat
Compat.isForever = true

function Compat.GetLevelCap()
    for _, name in ipairs({ "GetEffectivePlayerMaxLevel", "GetMaxPlayerLevel" }) do
        local ok, level = pcall(_G[name])
        local restricted = type(issecretvalue) == "function" and issecretvalue(level)
        if ok and not restricted and type(level) == "number" and level > 0 then return level end
    end
end
