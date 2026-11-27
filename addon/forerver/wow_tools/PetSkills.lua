local module = {}
WoWTools.modules.pet_skills = module

-- Taming sources: https://www.wow-petopia.com/forever/abilities.php.
-- Max ranks and family assignments use the 1.60.1.71139 client SpellEffect,
-- SkillLineAbility and zhCN CreatureFamily tables.
-- Sonic Blast uses a server-granted teaching spell outside skill line 261.
local skills = {
    -- Chinese fallback, pet spell, hunter teaching spell, max rank, required pet level, exclusive family
    {"撕咬",       17261,   17268, 8, 56},
    {"爪击",        3009,    3666, 8, 56},
    {"畏缩",       16697,   16698, 6, 55},
    {"突进",       23110,   23112, 3, 50},
    {"俯冲",       23148,   23150, 3, 50},
    {"狂怒之嚎",   24597,   24599, 4, 56, "狼"},
    {"潜伏",       24453,   24455, 3, 50, "豹"},
    {"蛛网",     1265883, 1265892, 5, 60, "蜘蛛"},
    {"横扫",     1264502, 1264732, 5, 60, "熊"},
    {"冲锋",       27685,   28343, 6, 60, "野猪"},
    {"肢解",     1264933, 1264972, 5, 60, "鳄鱼"},
    {"挫志尖啸",   24579,   24582, 4, 56, "食腐鸟"},
    {"钳夹",     1264742, 1264752, 5, 60, "螃蟹"},
    {"雷霆践踏", 1264455, 1264456, 4, 60, "猩猩"},
    {"野蛮撕扯", 1265069, 1265836, 5, 60, "迅猛龙"},
    {"尘雾之云", 1265904, 1265911, 5, 60, "陆行鸟"},
    {"蝎毒",       24587,   24589, 4, 56, "蝎子"},
    {"甲壳护盾",   26064,   26065, 1, 20, "海龟"},
    {"音爆",     1264482, 1264488, 5, 60, "蝙蝠"},
    {"裂筋",     1265042, 1265048, 5, 60, "土狼"},
    {"归我了！", 1265058, 1265064, 5, 50, "猛禽"},
    {"闪电吐息",   25012,   25017, 6, 60, "风蛇"},
    {"欺诈者之舞", 1310612, 1310617, 1, 20, "狐狸"},
}

local bySpell = {}
local sharedSkills = {title = "公共技能"}
local familySkills = {title = "家族技能"}
for _, skill in ipairs(skills) do
    bySpell[skill[2]] = skill[3]
    bySpell[skill[3]] = skill[3]
    local section = skill[6] and familySkills or sharedSkills
    section[#section + 1] = skill
end

local known, panel, message, skillList
local rows = {}
local rowHeight = 25
local learnedStatus = "有 |A:common-icon-checkmark:14:14:0:-1|a"
local unlearnedStatus = "无 |A:common-icon-redx:14:14:0:-1|a"

local function IsHunter()
    return select(2, UnitClass("player")) == "HUNTER"
end

local function Readable(value)
    if not issecretvalue or not issecretvalue(value) then return value end
end

local function SkillName(skill)
    return Readable(C_Spell.GetSpellName(skill[2])) or skill[1]
end

local function Refresh()
    if not panel or not panel:IsVisible() then return end
    local hunter = IsHunter()
    message:SetText(hunter and "打开法术书中的「训练野兽」可同步已有技能。切换宠物后可补齐对应家族的记录。"
        or "请使用猎人角色查看。")
    skillList:SetShown(hunter)
    if not hunter then return end
    for _, skill in ipairs(skills) do
        local teachSpell = skill[3]
        local learned = known and known[teachSpell] == true
            or Readable(C_SpellBook.IsSpellKnown(teachSpell, Enum.SpellBookSpellBank.Player))
        local row = rows[skill]
        row.name:SetText(SkillName(skill))
        row.status:SetText(learned and learnedStatus or unlearnedStatus)
    end
end

local function ReadTraining()
    if C_Trainer.GetTrainerType() ~= Enum.TrainerType.Pet then return end
    local byName = {}
    for _, skill in ipairs(skills) do byName[SkillName(skill)] = skill end
    for index = 1, Readable(GetNumTrainerServices()) or 0 do
        local name, status, _, level, rankText = GetTrainerServiceInfo(index)
        status = Readable(status)
        if status == "available" or status == "unavailable" or status == "used" then
            local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
            data = ok and Readable(data)
            local spell = type(data) == "table" and Readable(data.id)
            local teachSpell = bySpell[spell]
            if not teachSpell then
                local skill = byName[Readable(name)]
                rankText = Readable(rankText)
                local rank = type(rankText) == "string" and tonumber(rankText:match("%d+")) or nil
                -- Forever can omit rank text. The listed pet level distinguishes these ranks.
                if skill and (rank == skill[4] or not rank and Readable(level) == skill[5]) then
                    teachSpell = skill[3]
                end
            end
            if teachSpell then known[teachSpell] = true end
        end
    end
end

local learnMessages = {"ERR_LEARN_ABILITY_S", "ERR_LEARN_SPELL_S", "ERR_LEARN_PASSIVE_S"}
local function ReadLearnMessage(text)
    text = Readable(text)
    local id = type(text) == "string" and text:match("|Hspell:(%d+)")
    local teachSpell = id and bySpell[tonumber(id)]
    if not teachSpell then return end
    for _, key in ipairs(learnMessages) do
        local format = _G[key]
        if format then
            local prefix, suffix = format:match("^(.-)%%s(.*)$")
            if prefix and text:sub(1, #prefix) == prefix and (suffix == "" or text:sub(-#suffix) == suffix) then
                known[teachSpell] = true
                return true
            end
        end
    end
end

local function OnHunterEvent(_, event, value)
    if event == "LEARNED_SPELL_IN_SKILL_LINE" then
        local spell = Readable(value)
        if not spell or bySpell[spell] ~= spell then return end
        known[spell] = true
    elseif event == "CHAT_MSG_SYSTEM" then
        if not ReadLearnMessage(value) then return end
    elseif event ~= "SPELLS_CHANGED" then
        ReadTraining()
    end
    Refresh()
end

local function OnLogin(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if IsHunter() then
        if type(wowToolsCharacterSettings) ~= "table" then wowToolsCharacterSettings = {} end
        if type(wowToolsCharacterSettings.knownPetSkills) ~= "table" then
            wowToolsCharacterSettings.knownPetSkills = {}
        end
        known = wowToolsCharacterSettings.knownPetSkills
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        self:RegisterEvent("TRAINER_SHOW")
        self:RegisterEvent("TRAINER_UPDATE")
        self:RegisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE")
        self:SetScript("OnEvent", OnHunterEvent)
    end
    Refresh()
end

local function AddSkillCell(anchor, left, top, width, text)
    local cell = skillList:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cell:SetPoint("TOPLEFT", skillList, anchor, left, -top)
    cell:SetSize(width, rowHeight)
    cell:SetJustifyH("CENTER")
    cell:SetWordWrap(false)
    cell:SetText(text or "")
    return cell
end

function module.BuildSettings(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    message:SetPoint("TOPLEFT", 16, -16)
    message:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    message:SetJustifyH("LEFT")
    skillList = CreateFrame("Frame", nil, panel)
    skillList:SetAllPoints(panel)
    local top = 52
    local familyWidth, nameWidth, separatorWidth, statusWidth = 48, 120, 10, 42
    for _, section in ipairs({sharedSkills, familySkills}) do
        local heading = skillList:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        heading:SetPoint("TOPLEFT", 16, -top)
        heading:SetText(section.title)
        top = top + 27
        local columnSize = math.ceil(#section / 2)
        for index, skill in ipairs(section) do
            local anchor = index <= columnSize and "TOPLEFT" or "TOP"
            local left, rowTop = 16, top + ((index - 1) % columnSize) * rowHeight
            local family = skill[6]
            if family then
                AddSkillCell(anchor, left, rowTop, familyWidth, family)
                AddSkillCell(anchor, left + familyWidth, rowTop, separatorWidth, "-")
                left = left + familyWidth + separatorWidth
            end
            local name = AddSkillCell(anchor, left, rowTop, nameWidth)
            AddSkillCell(anchor, left + nameWidth, rowTop, separatorWidth, "-")
            local status = AddSkillCell(anchor, left + nameWidth + separatorWidth, rowTop, statusWidth)
            rows[skill] = {name = name, status = status}
        end
        top = top + columnSize * rowHeight + 13
    end
    panel:RegisterEvent("PLAYER_LOGIN")
    panel:SetScript("OnEvent", OnLogin)
    panel:SetScript("OnShow", Refresh)
    return panel
end
