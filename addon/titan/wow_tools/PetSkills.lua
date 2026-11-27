-- Titan 3.80.2.70522 uses pet family spells and pet talents.
-- Beast Training skill line 261 has no hunter teaching spells in SkillLineAbility.
WoWTools.modules.pet_skills = {
    BuildSettings = function(parent)
        local panel = CreateFrame("Frame", nil, parent)
        panel:SetAllPoints(parent)
        local message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        message:SetPoint("TOPLEFT", 16, -16)
        message:SetText("时光服没有可通过抓宠领悟的猎人宠物技能。")
        return panel
    end,
}
