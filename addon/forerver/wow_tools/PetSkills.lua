local module = {}
WoWTools.modules.pet_skills = module

-- Wild-learned families from https://www.wow-petopia.com/forever/abilities.php.
-- Max ranks use the 1.60.1.71139 client SpellEffect teaching links and skill line 261
-- (Sonic Blast uses a server-granted teaching spell outside that line).
local skills = {
    -- Chinese fallback, pet spell, hunter teaching spell, max rank, required pet level
    {"撕咬",       17261,   17268, 8, 56},
    {"爪击",        3009,    3666, 8, 56},
    {"畏缩",       16697,   16698, 6, 55},
    {"突进",       23110,   23112, 3, 50},
    {"俯冲",       23148,   23150, 3, 50},
    {"冲锋",       27685,   28343, 6, 60},
    {"挫志尖啸",   24579,   24582, 4, 56},
    {"肢解",     1264933, 1264972, 5, 60},
    {"尘雾之云", 1265904, 1265911, 5, 60},
    {"狂怒之嚎",   24597,   24599, 4, 56},
    {"闪电吐息",   25012,   25017, 6, 60},
    {"归我了！", 1265058, 1265064, 5, 50},
    {"钳夹",     1264742, 1264752, 5, 60},
    {"潜伏",       24453,   24455, 3, 50},
    {"野蛮撕扯", 1265069, 1265836, 5, 60},
    {"蝎毒",       24587,   24589, 4, 56},
    {"甲壳护盾",   26064,   26065, 1, 20},
    {"音爆",     1264482, 1264488, 5, 60},
    {"横扫",     1264502, 1264732, 5, 60},
    {"裂筋",     1265042, 1265048, 5, 60},
    {"雷霆践踏", 1264455, 1264456, 4, 60},
    {"欺诈者之舞", 1310612, 1310617, 1, 20},
    {"蛛网",     1265883, 1265892, 5, 60},
}

local bySpell = {}
for _, skill in ipairs(skills) do
    bySpell[skill[2]] = skill[3]
    bySpell[skill[3]] = skill[3]
end

local known, panel, message
local rows = {}

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
    for index, skill in ipairs(skills) do
        local row = rows[index]
        row:SetShown(hunter)
        if hunter then
            local teachSpell = skill[3]
            local learned = known and known[teachSpell] == true
                or Readable(C_SpellBook.IsSpellKnown(teachSpell, Enum.SpellBookSpellBank.Player))
            row:SetText(SkillName(skill) .. (learned and "-有" or "-无"))
        end
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

function module.BuildSettings(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    message:SetPoint("TOPLEFT", 16, -16)
    message:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    message:SetJustifyH("LEFT")
    local columnSize = math.ceil(#skills / 2)
    for index in ipairs(skills) do
        local row = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        local anchor = index <= columnSize and "TOPLEFT" or "TOP"
        row:SetPoint("TOPLEFT", panel, anchor, 16, -60 - ((index - 1) % columnSize) * 26)
        rows[index] = row
    end
    panel:RegisterEvent("PLAYER_LOGIN")
    panel:SetScript("OnEvent", OnLogin)
    panel:SetScript("OnShow", Refresh)
    return panel
end
