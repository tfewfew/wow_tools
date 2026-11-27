WoWTools.prr.RegisterSource(function(...)
-- disenchant_results.lua -- what an item disenchants into on Forever (the
-- vanilla tables; the same as in the addon Disenchant Buddy). By the quality,
-- weapon or armor (only uncommon ones differ) and the item level: the first
-- band whose maxLevel is not below the item level. Each result is
-- { material item, chance in %, min, max }. An item above the last band -- no
-- results (dataflows/disenchant.lua).

local ADDON, ns = ...
ns.Constants = ns.Constants or {}

local STRANGE_DUST = 10940
local SOUL_DUST = 11083
local VISION_DUST = 11137
local DREAM_DUST = 11176
local ILLUSION_DUST = 16204
local LESSER_MAGIC_ESSENCE = 10938
local GREATER_MAGIC_ESSENCE = 10939
local LESSER_ASTRAL_ESSENCE = 10998
local GREATER_ASTRAL_ESSENCE = 11082
local LESSER_MYSTIC_ESSENCE = 11134
local GREATER_MYSTIC_ESSENCE = 11135
local LESSER_NETHER_ESSENCE = 11174
local GREATER_NETHER_ESSENCE = 11175
local LESSER_ETERNAL_ESSENCE = 16202
local GREATER_ETERNAL_ESSENCE = 16203
local SMALL_GLIMMERING_SHARD = 10978
local LARGE_GLIMMERING_SHARD = 11084
local SMALL_GLOWING_SHARD = 11138
local LARGE_GLOWING_SHARD = 11139
local SMALL_RADIANT_SHARD = 11177
local LARGE_RADIANT_SHARD = 11178
local SMALL_BRILLIANT_SHARD = 14343
local LARGE_BRILLIANT_SHARD = 14344
local NEXUS_CRYSTAL = 20725

local DisenchantResults = {}
ns.Constants.DisenchantResults = DisenchantResults

DisenchantResults.UNCOMMON_ARMOR = {
    { maxLevel = 15, { STRANGE_DUST, 80, 1, 2 }, { LESSER_MAGIC_ESSENCE, 20, 1, 2 } },
    { maxLevel = 20, { STRANGE_DUST, 75, 2, 3 }, { GREATER_MAGIC_ESSENCE, 20, 1, 2 }, { SMALL_GLIMMERING_SHARD, 5, 1, 1 } },
    { maxLevel = 25, { STRANGE_DUST, 75, 4, 6 }, { LESSER_ASTRAL_ESSENCE, 15, 1, 2 }, { SMALL_GLIMMERING_SHARD, 10, 1, 1 } },
    { maxLevel = 30, { SOUL_DUST, 75, 1, 2 }, { GREATER_ASTRAL_ESSENCE, 20, 1, 2 }, { LARGE_GLIMMERING_SHARD, 5, 1, 1 } },
    { maxLevel = 35, { SOUL_DUST, 75, 2, 5 }, { LESSER_MYSTIC_ESSENCE, 20, 1, 2 }, { SMALL_GLOWING_SHARD, 5, 1, 1 } },
    { maxLevel = 40, { VISION_DUST, 75, 1, 2 }, { GREATER_MYSTIC_ESSENCE, 20, 1, 2 }, { LARGE_GLOWING_SHARD, 5, 1, 1 } },
    { maxLevel = 45, { VISION_DUST, 75, 2, 5 }, { LESSER_NETHER_ESSENCE, 20, 1, 2 }, { SMALL_RADIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 50, { DREAM_DUST, 75, 1, 2 }, { GREATER_NETHER_ESSENCE, 20, 1, 2 }, { LARGE_RADIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 55, { DREAM_DUST, 75, 2, 6 }, { LESSER_ETERNAL_ESSENCE, 20, 1, 2 }, { SMALL_BRILLIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 60, { ILLUSION_DUST, 75, 1, 2 }, { GREATER_ETERNAL_ESSENCE, 20, 1, 2 }, { LARGE_BRILLIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 65, { ILLUSION_DUST, 75, 2, 5 }, { GREATER_ETERNAL_ESSENCE, 20, 2, 3 }, { LARGE_BRILLIANT_SHARD, 5, 1, 1 } },
}

-- weapons: more essence, less dust
DisenchantResults.UNCOMMON_WEAPON = {
    { maxLevel = 15, { LESSER_MAGIC_ESSENCE, 80, 1, 2 }, { STRANGE_DUST, 20, 1, 2 } },
    { maxLevel = 20, { GREATER_MAGIC_ESSENCE, 75, 1, 2 }, { STRANGE_DUST, 20, 2, 3 }, { SMALL_GLIMMERING_SHARD, 5, 1, 1 } },
    { maxLevel = 25, { GREATER_MAGIC_ESSENCE, 75, 1, 2 }, { STRANGE_DUST, 15, 4, 6 }, { SMALL_GLIMMERING_SHARD, 10, 1, 1 } },
    { maxLevel = 30, { GREATER_MAGIC_ESSENCE, 75, 1, 2 }, { SOUL_DUST, 20, 1, 2 }, { LARGE_GLIMMERING_SHARD, 5, 1, 1 } },
    { maxLevel = 35, { LESSER_MYSTIC_ESSENCE, 75, 1, 2 }, { SOUL_DUST, 20, 2, 5 }, { SMALL_GLOWING_SHARD, 5, 1, 1 } },
    { maxLevel = 40, { GREATER_MYSTIC_ESSENCE, 75, 1, 2 }, { VISION_DUST, 20, 1, 2 }, { LARGE_GLOWING_SHARD, 5, 1, 1 } },
    { maxLevel = 45, { LESSER_NETHER_ESSENCE, 75, 1, 2 }, { VISION_DUST, 20, 2, 5 }, { SMALL_RADIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 50, { GREATER_NETHER_ESSENCE, 75, 1, 2 }, { DREAM_DUST, 20, 1, 2 }, { LARGE_RADIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 55, { LESSER_ETERNAL_ESSENCE, 75, 1, 2 }, { DREAM_DUST, 20, 2, 5 }, { SMALL_BRILLIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 60, { GREATER_ETERNAL_ESSENCE, 75, 1, 2 }, { ILLUSION_DUST, 20, 1, 2 }, { LARGE_BRILLIANT_SHARD, 5, 1, 1 } },
    { maxLevel = 65, { GREATER_ETERNAL_ESSENCE, 75, 2, 3 }, { ILLUSION_DUST, 20, 2, 5 }, { LARGE_BRILLIANT_SHARD, 5, 1, 1 } },
}

DisenchantResults.RARE = {
    { maxLevel = 25, { SMALL_GLIMMERING_SHARD, 100, 1, 1 } },
    { maxLevel = 30, { LARGE_GLIMMERING_SHARD, 100, 1, 1 } },
    { maxLevel = 35, { SMALL_GLOWING_SHARD, 100, 1, 1 } },
    { maxLevel = 40, { LARGE_GLOWING_SHARD, 100, 1, 1 } },
    { maxLevel = 45, { SMALL_RADIANT_SHARD, 100, 1, 1 } },
    { maxLevel = 50, { LARGE_RADIANT_SHARD, 100, 1, 1 } },
    { maxLevel = 55, { SMALL_BRILLIANT_SHARD, 100, 1, 1 } },
    { maxLevel = 86, { LARGE_BRILLIANT_SHARD, 99.5, 1, 1 }, { NEXUS_CRYSTAL, 0.5, 1, 1 } },
}

-- the same crystal twice: one in a third of the cases, two in the rest
DisenchantResults.EPIC = {
    { maxLevel = 45, { SMALL_RADIANT_SHARD, 100, 2, 4 } },
    { maxLevel = 50, { LARGE_RADIANT_SHARD, 100, 2, 4 } },
    { maxLevel = 55, { SMALL_BRILLIANT_SHARD, 100, 2, 4 } },
    { maxLevel = 60, { NEXUS_CRYSTAL, 100, 1, 1 } },
    { maxLevel = 92, { NEXUS_CRYSTAL, 33, 1, 1 }, { NEXUS_CRYSTAL, 67, 2, 2 } },
}

-- weapons and armor that cannot be disenchanted
DisenchantResults.NOT_DISENCHANTABLE = {
    [11287] = true,   -- Lesser Magic Wand
    [11288] = true,   -- Greater Magic Wand
    [11289] = true,   -- Lesser Mystic Wand
    [11290] = true,   -- Greater Mystic Wand
    [20406] = true,   -- Twilight Cultist Mantle
    [20407] = true,   -- Twilight Cultist Robe
    [20408] = true,   -- Twilight Cultist Cowl
}
end)
