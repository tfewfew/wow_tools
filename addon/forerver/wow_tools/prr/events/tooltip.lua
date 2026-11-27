WoWTools.prr.RegisterSource(function(...)
-- tooltip.lua -- adds the recipe lines to item tooltips, the gathering lines
-- to herb and ore nodes in the world and to beasts (components/gather_tooltip.lua).
-- Modern clients (Forever among them) build tooltips from TooltipDataProcessor;
-- older ones fire OnTooltipSetItem.

local ADDON, ns = ...

local ItemTooltip = ns.Components.ItemTooltip

-- only the main tooltips: not comparison ones and not forbidden ones
local function IsOwnTooltip(tooltip)
    if tooltip:IsForbidden() then
        return false
    end
    return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

local function OnItem(tooltip, data)
    if not ns.db then return end
    if not IsOwnTooltip(tooltip) then return end

    local itemID = data and ns.Utilities.Open(data.id)
    if type(itemID) ~= "number" then
        local _, link = tooltip:GetItem()
        link = ns.Utilities.Open(link)
        itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    end
    if itemID then
        ItemTooltip.Fill(tooltip, itemID)
    end
end

local function GetTrainerRank(info, spellID)
    local saved = ns.db.fixes and ns.db.fixes[spellID]
    if saved and (saved.skill or saved.skillUnknown) then return end
    local serviceIndex = info.getterArgs and info.getterArgs[1]
    if not GetTrainerServiceSkillReq or (issecretvalue and issecretvalue(serviceIndex))
        or type(serviceIndex) ~= "number" or serviceIndex <= 0 then return end

    local skill, rank = GetTrainerServiceSkillReq(serviceIndex)
    if (not issecretvalue or not (issecretvalue(skill) or issecretvalue(rank)))
        and type(skill) == "string" and type(rank) == "number" and rank > 0 then
        return rank
    end
end

local function OnTrainerSpell(tooltip, data)
    if not ns.db or tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
    local info = tooltip:GetProcessingTooltipInfo()
    if not info or info.getterName ~= "GetTrainerService" or info.append then return end

    local spellID = data.id
    if (issecretvalue and issecretvalue(spellID)) or type(spellID) ~= "number" then return end
    local recipe = ns.Dataflows.RecipeIndex.Get(spellID)
    local levels = recipe and ns.SkillRange.Text(recipe, GetTrainerRank(info, spellID))
    if levels then
        tooltip:AddLine(ns.Localization.Text("tooltip.skill_range", levels), 1, 1, 1)
    end
end

if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
    if Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnTrainerSpell)
    end
else
    GameTooltip:HookScript("OnTooltipSetItem", OnItem)
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnItem)
end

-- Gathering: a node is known by the id in its GUID (any language) or by the
-- tooltip's title; a creature to skin -- by its npc id in the data (any type:
-- the Bloodhounds of Blackrock Depths are demons), its creature type (beast,
-- dragonkin), the game's "Skinnable" mark on a dead one, or a name the data has.
local GatherTooltip = ns.Components.GatherTooltip
local Gathering = ns.Dataflows.Gathering
local gatherShown = {}           -- [tooltip] = true: the gathering lines are in it already

local function IsSecret(value)
    return ns.Utilities.IsSecret(value)
end

local function ObjectID(guid)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    -- GameObject-0-[server]-[instance]-[zone]-[id]-[spawn]
    local id = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return tonumber(id)
end

local function TitleText(tooltip)
    local name = tooltip:GetName()
    local line = name and _G[name .. "TextLeft1"]
    local text = line and line:GetText()
    if type(text) ~= "string" or IsSecret(text) then return nil end
    return text
end

-- Creature-0-[server]-[instance]-[zone]-[npc id]-[spawn]: from the tooltip's
-- data, else from the unit
local function NpcID(unit, data)
    local guid = data and data.guid
    if IsSecret(guid) or type(guid) ~= "string" then
        guid = UnitGUID(unit)
    end
    if IsSecret(guid) or type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

local function CanAddGathering(tooltip)
    return ns.db ~= nil and tooltip == GameTooltip and not tooltip:IsForbidden() and not gatherShown[tooltip]
end

local function AddNode(tooltip, data)
    if not CanAddGathering(tooltip) then return end
    local id = data and (ObjectID(data.guid) or (type(data.id) == "number" and not IsSecret(data.id) and data.id))
    local node = Gathering.NodeByObject(id) or Gathering.NodeByName(TitleText(tooltip))
    if not node then return end
    -- marked before: the block shows the tooltip, and OnShow must not add it a second time
    gatherShown[tooltip] = true
    if not GatherTooltip.FillNode(tooltip, node, id or nil) then
        gatherShown[tooltip] = nil
    end
end

-- a living beast (its tooltip is of a unit) or a dead one (of a corpse: the
-- tooltip may have no unit then -- the one under the mouse is it)
local function AddBeast(tooltip, data)
    if not CanAddGathering(tooltip) then return end
    local _, unit = tooltip:GetUnit()
    if not unit and UnitExists("mouseover") then
        unit = "mouseover"
    end
    if not unit or IsSecret(unit) or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local npcID = NpcID(unit, type(data) == "table" and data or nil)
    local name = UnitName(unit)
    if IsSecret(name) then name = nil end
    -- a skull ("??", 10 levels above) gives -1: the level of the data then
    local level = UnitLevel(unit)
    if IsSecret(level) or not level or level <= 0 then
        local wowheadSource = Gathering.WowheadNpc(npcID)
        level = wowheadSource and wowheadSource.level
    end
    if not level or level <= 0 then return end
    local isDead = UnitIsDead(unit)
    -- Wowhead's lists and the own counts go by the npc id: without one of them, no block
    if not Gathering.IsSkinnedNpc(npcID) then return end
    gatherShown[tooltip] = true    -- before: see AddNode
    if not GatherTooltip.FillBeast(tooltip, name, level, isDead, npcID) then
        gatherShown[tooltip] = nil
    end
end

-- an error here must not break the game's tooltip
local function Safely(handler)
    return function(...)
        local ok, problem = pcall(handler, ...)
        if not ok and ns.db and ns.db.settings.developer then
            ns.Utilities.Print("gathering tooltip: " .. tostring(problem))
        end
    end
end

if TooltipDataProcessor and Enum.TooltipDataType then
    if Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, Safely(AddNode))
    end
    if Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Safely(AddBeast))
    end
    if Enum.TooltipDataType.Corpse then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Corpse, Safely(AddBeast))
    end
end
-- a node's tooltip filled another way: the game's own tooltip of a thing in the
-- world (on UIParent or WorldFrame), with no unit and no item in it
local function OnShow(tooltip)
    if gatherShown[tooltip] then return end
    if UnitExists("mouseover") then
        if UnitIsDead("mouseover") then
            AddBeast(tooltip)
        end
        return
    end
    local owner = tooltip:GetOwner()
    if owner and owner ~= UIParent and owner ~= WorldFrame then return end
    if tooltip:GetItem() then return end
    local data = tooltip.GetTooltipData and tooltip:GetTooltipData()
    local types = Enum and Enum.TooltipDataType
    if type(data) == "table" and types and data.type ~= nil and data.type ~= types.Object then return end
    AddNode(tooltip, type(data) == "table" and data or nil)
end

local function ForgetGathering(tooltip)
    gatherShown[tooltip] = nil
end

if GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", Safely(OnShow))
    GameTooltip:HookScript("OnTooltipCleared", ForgetGathering)
    GameTooltip:HookScript("OnHide", ForgetGathering)
end
ns.Events.GatheringHandlers = { node = AddNode, beast = AddBeast, forget = ForgetGathering }   -- for the test

-- /prr why: every step of the skinning decision for the mob under the mouse
-- (not localized, for finding why a block does not show).
function ns.Events.ExplainSkinning()
    local unit = "mouseover"
    local lines = {}
    local function Add(label, value)
        table.insert(lines, label .. ": " .. (IsSecret(value) and "secret" or tostring(value)))
    end
    Add("exists", UnitExists(unit))
    if not UnitExists(unit) then return lines end
    local npcID = NpcID(unit)
    local level = ns.Utilities.Open(UnitLevel(unit))
    local wowheadSource = Gathering.WowheadNpc(npcID)
    local tooltipData = GameTooltip.GetTooltipData and GameTooltip:GetTooltipData()
    local dataGuid = type(tooltipData) == "table" and tooltipData.guid or nil
    Add("npc id", npcID)
    Add("guid secret", IsSecret(UnitGUID(unit)))
    Add("tooltip data guid", dataGuid and (IsSecret(dataGuid) and "secret" or dataGuid) or "none")
    Add("tooltip data npc id", NpcID(unit, tooltipData))
    Add("name secret", IsSecret(UnitName(unit)))
    Add("type secret", IsSecret(UnitCreatureType(unit)))
    Add("level secret", IsSecret(UnitLevel(unit)))
    Add("level", level)
    Add("data level", wowheadSource and wowheadSource.level)
    Add("type", UnitCreatureType(unit))
    Add("dead", UnitIsDead(unit))
    Add("player", UnitIsPlayer(unit))
    Add("in Wowhead data", wowheadSource ~= nil)
    Add("skinned npc", Gathering.IsSkinnedNpc(npcID))
    local settings = ns.db.settings
    Add("setting showSkinning", settings.showSkinning)
    Add("setting skinningUnits", settings.skinningUnits)
    Add("skinning skill", ns.GameData.ProfessionSkill(Gathering.SKINNING))
    Add("block already in the tooltip", gatherShown[GameTooltip])
    local ok, problem = pcall(function()
        local probe = { lines = {} }
        function probe:AddLine(text) table.insert(self.lines, text) end
        function probe:AddDoubleLine(left) table.insert(self.lines, left) end
        function probe:Show() end
        function probe:GetName() return nil end
        return GatherTooltip.FillBeast(probe, ns.Utilities.Open(UnitName(unit)), (level and level > 0) and level
            or (wowheadSource and wowheadSource.level) or 1, UnitIsDead(unit), npcID)
    end)
    Add("fill", ok and tostring(problem) or ("ERROR " .. tostring(problem)))
    return lines
end

-- Shift shows the full lists: redraw the tooltip when it is pressed or released.
ns.Events.On("MODIFIER_STATE_CHANGED", function(key)
    local isShift = key == "LSHIFT" or key == "RSHIFT"
    if not isShift then return end
    local canRefresh = GameTooltip:IsShown() and GameTooltip.RefreshData and GameTooltip:GetItem()
    if canRefresh then
        GameTooltip:RefreshData()
    end
end)
end)
