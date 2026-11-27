WoWTools.prr.RegisterSource(function(...)
-- gather_tooltip.lua -- the lines of a herb or ore node in the world and of a
-- beast to skin (dataflows/gathering.lua):
--
--   Skinning [90][115][140][190]                               PRR
--   Skinned: 18 times
--   Skill-up chance: 100%                (in the color of the zone)
--   Possible loot:
--     Light Leather                                         12s 00c
--                                                           x1 36%
--                                                           x2 36%
--     Light Hide                                            30s 00c
--                                                            x1 5%
--   Your loot:
--     Light Leather                                         12s 00c
--                                                          x1 100%
--
-- Under an item: the chance of each amount from one loot (the item's chance x
-- the share of the amount), so the lines add up to the item's chance. The
-- sections: the loot data of WoW Forever and the character's own counted loot. Every
-- part has its setting (settings.showGathering*); nodes --
-- settings.showHerbNodes / showMiningNodes, beasts -- settings.showSkinning (on living ones too
-- with skinningUnits = "all"), for a character with Skinning.

local ADDON, ns = ...
ns.Components = ns.Components or {}

local Config = ns.Config
local Gathering = ns.Dataflows.Gathering
local ItemNames = ns.Dataflows.ItemNames
local Text = ns.Localization.Text

local GatherTooltip = {}
ns.Components.GatherTooltip = GatherTooltip

local INDENT = "  "
local LOADING_NAME = "..."
local MAX_LOOT_LINES = 6
local CHANCE_COLOR = { 0.85, 0.85, 0.85 }
local ZONE_COLORS = {
    orange = Config.COLOR_SKILL_ORANGE, yellow = Config.COLOR_SKILL_YELLOW,
    green = Config.COLOR_SKILL_GREEN, gray = Config.COLOR_SKILL_GRAY,
}
local COUNT_KEYS = {
    [Gathering.SKINNING] = "gathering.count_skinning",
    [Gathering.MINING] = "gathering.count_mining",
    [Gathering.HERBALISM] = "gathering.count_herbalism",
}

-- "[65][90][115][165]" in the colors of the zones.
local function LevelsText(levels)
    return ZONE_COLORS.orange .. "[" .. levels.learn .. "]|r"
        .. ZONE_COLORS.yellow .. "[" .. levels.yellow .. "]|r"
        .. ZONE_COLORS.green .. "[" .. levels.green .. "]|r"
        .. ZONE_COLORS.gray .. "[" .. levels.gray .. "]|r"
end

-- "12%", "1.5%", "0.3%"
function GatherTooltip.PercentText(percent)
    if percent >= 10 then
        return string.format("%d%%", math.floor(percent + 0.5))
    end
    return (string.format("%.1f", percent):gsub("%.0$", "")) .. "%"
end

-- "Skill-up chance: 83%" with the chance in the color of the zone, or
-- "Requires skill 125" below it.
local function SkillUpText(requirement, skill)
    local zone = ns.SkillRange.Zone(requirement, skill)
    if zone.zone == "locked" then
        return Config.COLOR_SKILL_ORANGE .. Text("gathering.needs", zone.learn) .. "|r"
    end
    local chance = ZONE_COLORS[zone.zone] .. math.floor(zone.chance * 100 + 0.5) .. "%|r"
    return Config.COLOR_TEXT .. Text("gathering.skill_up", chance) .. "|r"
end

-- The chance lines under an item: { "x1 36%", "x2 36%" } -- of each amount
-- from one loot; with withStacks off, { "72%" } -- the item's chance.
function GatherTooltip.ChanceLines(entry, withStacks)
    if not withStacks or not entry.stacks or #entry.stacks == 0 then
        return { GatherTooltip.PercentText(entry.percent) }
    end
    local lines = {}
    for _, stack in ipairs(entry.stacks) do
        table.insert(lines, "x" .. stack[1] .. " " .. GatherTooltip.PercentText(entry.percent * stack[2] / 100))
    end
    return lines
end

-- A section: its title, then the items by their chance -- the name with the
-- price, under it the chances.
local function AddSection(tooltip, title, source, settings)
    if not source or #source.items == 0 then return end
    tooltip:AddLine(Config.COLOR_HEADER .. title .. "|r")
    local items = {}
    for _, entry in ipairs(source.items) do table.insert(items, entry) end
    table.sort(items, function(a, b)
        if a.percent ~= b.percent then return a.percent > b.percent end
        return a.item < b.item
    end)
    for index, entry in ipairs(items) do
        if index > MAX_LOOT_LINES then break end
        local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.item)
        local iconText = icon and ("|T" .. icon .. ":0|t ") or ""
        local price = settings.showGatheringPrice and ns.Dataflows.AuctionPrices.Get(entry.item)
        tooltip:AddDoubleLine(INDENT .. iconText .. (ItemNames.ItemName(entry.item) or LOADING_NAME),
            price and ns.Utilities.Money(price) or " ", 1, 1, 1, 1, 1, 1)
        for _, line in ipairs(GatherTooltip.ChanceLines(entry, settings.showGatheringStacks)) do
            tooltip:AddDoubleLine(" ", line, 1, 1, 1, CHANCE_COLOR[1], CHANCE_COLOR[2], CHANCE_COLOR[3])
        end
    end
end

-- The block: the profession with the levels (and PRR), the times looted, the
-- skill-up chance, Wowhead's loot, the character's own loot.
local function AddBlock(tooltip, profession, requirement, wowheadSource, ownSource)
    local settings = ns.db.settings
    local levels = ns.SkillRange.Levels(requirement)
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(Config.COLOR_HEADER .. ns.GameData.ProfessionName(profession) .. "|r " .. LevelsText(levels),
        Config.COLOR_ADDON_MARK .. ns.Constants.ADDON_SHORT_TITLE .. "|r")
    if settings.showGatheringOwn then
        tooltip:AddLine(Config.COLOR_TEXT .. Text(COUNT_KEYS[profession] or COUNT_KEYS[Gathering.SKINNING],
            ownSource and ownSource.n or 0) .. "|r")
    end
    local skill = ns.GameData.ProfessionSkill(profession)
    if skill then
        tooltip:AddLine(SkillUpText(requirement, skill))
    end
    if settings.showPossibleLoot and wowheadSource then
        AddSection(tooltip, Text("gathering.possible"), wowheadSource, settings)
    end
    if settings.showGatheringOwn and ownSource then
        -- more loots than the history keeps: the chances are of the last ones
        local title = ownSource.n > ownSource.loots and Text("gathering.own_last", ownSource.loots) or Text("gathering.own")
        AddSection(tooltip, title, ownSource, settings)
    end
    ns.Components.ItemTooltip.AddSpacer(tooltip)
    tooltip:Show()
end

-- A node in the world (its object id when known): true when it was one.
function GatherTooltip.FillNode(tooltip, node, objectID)
    if not node then return false end
    local settings = ns.db.settings
    local isShown = node.profession == Gathering.MINING and settings.showMiningNodes or
        node.profession ~= Gathering.MINING and settings.showHerbNodes
    if not isShown then return false end
    local wowheadSource = Gathering.WowheadObject(objectID) or Gathering.WowheadObject(Gathering.MainObject(node.name))
    -- the recorder keys a node it does not know by its object id
    local ownSource = Gathering.OwnSource("node", node.name) or (objectID and Gathering.OwnSource("node", "object " .. objectID))
    AddBlock(tooltip, node.profession, node.levels, wowheadSource, ownSource)
    return true
end

-- A beast: the skinning lines for a character with Skinning; a living one
-- only with settings.skinningUnits = "all".
function GatherTooltip.FillBeast(tooltip, name, level, isDead, npcID)
    local settings = ns.db.settings
    if not settings.showSkinning then return false end
    if settings.skinningUnits == "dead" and not isDead then return false end
    if not ns.GameData.ProfessionSkill(Gathering.SKINNING) then return false end
    local wowheadSource = Gathering.WowheadNpc(npcID)
    local ownSource = Gathering.OwnSource("npc", npcID)
    if not wowheadSource and not ownSource then return false end
    AddBlock(tooltip, Gathering.SKINNING, Gathering.Levels(Gathering.SkinningSkill(level)), wowheadSource,
        ownSource)
    return true
end
end)
