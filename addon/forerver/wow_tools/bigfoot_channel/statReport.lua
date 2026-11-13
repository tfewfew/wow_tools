local _
local BFChat = LibStub("AceAddon-3.0"):GetAddon("WoWToolsBigFootChannel")
local L = LibStub("AceLocale-3.0"):GetLocale("WoWToolsBigFootChannel")
local MyData = {}
BFC_CurEB = ChatFrame1EditBox
local function StatReport_Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(StatReport_Preview, 1, 0.9, 0.4)
        DEFAULT_CHAT_FRAME:AddMessage(tostring(msg), 1, 0.9, 0.4)
    end
end
local function StatReport_ChatFrameEditBoxMSG(msg)
    -- Resolve the destination when inserting a report, including menu actions.
    for i = 1, NUM_CHAT_WINDOWS do
        local editBox = _G["ChatFrame" .. i .. "EditBox"]
        if editBox and editBox:GetAlpha() == 1 and editBox:IsShown() then
            BFC_CurEB = editBox
            break
        end
    end
    if BFC_CurEB and BFC_CurEB:IsShown() then
        BFC_CurEB:Insert(msg)
    else
        StatReport_Print(msg)
    end
end
local function StatReport_TalentData()
    local curT = C_SpecializationInfo.GetSpecialization()
    local tname, duties
    if curT then
        _, tname, _, _, duties = C_SpecializationInfo.GetSpecializationInfo(curT)
    end
    local TalentStat = duties and _G[duties]
    return tname, TalentStat
end
local function StatReport_GetCritChance()
    local rating
    local spellCrit, rangedCrit, meleeCrit
    local critChance
    local holySchool = 2
    local minCrit = GetSpellCritChance(holySchool)
    local spellCrit
    for i = (holySchool + 1), MAX_SPELL_SCHOOLS do
        spellCrit = GetSpellCritChance(i)
        minCrit = min(minCrit, spellCrit)
    end
    spellCrit = minCrit
    rangedCrit = GetRangedCritChance()
    meleeCrit = GetCritChance()
    if spellCrit >= rangedCrit and spellCrit >= meleeCrit then
        critChance = spellCrit
        rating = CR_CRIT_SPELL
    elseif rangedCrit >= meleeCrit then
        critChance = rangedCrit
        rating = CR_CRIT_RANGED
    else
        critChance = meleeCrit
        rating = CR_CRIT_MELEE
    end
    return GetCombatRating(rating) > 0 and format("%s(%.1f%%)", GetCombatRating(rating), critChance)
end
local function StatReport_UpdateMyData()
    MyData.Name = UnitName("player")
    MyData.LV = UnitLevel("player")
    MyData.CLASS, MyData.CLASS_EN = UnitClass("player")
    MyData.TKEY, MyData.TDATA = StatReport_TalentData()
    local sysLv, curLv = GetAverageItemLevel()
    if curLv then
        MyData.ILVL = format("%d(%d)", floor(sysLv), floor(curLv))
    end
    if MyData.LV then
        MyData.MST = format("%s(%.1f%%)", GetCombatRating(CR_MASTERY), GetMasteryEffect())
    end
    local artifactInfo = C_ArtifactUI
            and C_ArtifactUI.GetEquippedArtifactInfo
            and { C_ArtifactUI.GetEquippedArtifactInfo() }
        or {}
    if table.getn(artifactInfo) > 0 then
        local pointsSpent = artifactInfo[6]
        if pointsSpent <= 51 then
            MyData.AF = pointsSpent
        else
            MyData.AF = format("%d(%d)", pointsSpent, pointsSpent - 51)
        end
    end
    local azeriteItemLocation = C_AzeriteItem
        and C_AzeriteItem.FindActiveAzeriteItem
        and C_AzeriteItem.FindActiveAzeriteItem()
    local azeriteItemPowerLevel = azeriteItemLocation
            and not AzeriteUtil.IsAzeriteItemLocationBankBag(azeriteItemLocation)
            and C_AzeriteItem.GetPowerLevel(azeriteItemLocation)
        or 0
    if azeriteItemPowerLevel ~= 0 then
        MyData.AI = C_AzeriteItem.GetPowerLevel(azeriteItemLocation)
    end
    local cid = C_Covenants and C_Covenants.GetActiveCovenantID and C_Covenants.GetActiveCovenantID()
    if cid and cid > 0 then
        local lvl = C_CovenantSanctumUI.GetRenownLevel()
        if lvl and lvl >= 1 then
            MyData.Covenant = format("%s(" .. lvl .. ")", C_Covenants.GetCovenantData(cid).name)
        end
    end
    MyData.CRIT = StatReport_GetCritChance()
    MyData.HASTE = GetCombatRating(18) > 0 and format("%s(%.1f%%)", GetCombatRating(18), GetHaste())
    MyData.VSTLT = GetCombatRating(29) > 0
        and format("%s(%.1f%%)", GetCombatRating(29), GetCombatRatingBonus(29))
end
function createReportFrame()
    local reportButton = _G.BFCIconFrameReportButton
    if BFChatFrame_CheckNumber then
        reportButton:SetPoint("LEFT", _G.BFCIconFrameRollButton, "RIGHT", 1, 0)
    else
        reportButton:SetPoint("TOPLEFT", BFCChatFrame, "TOPLEFT", 295, -3)
    end
    if BFChat.db.profile.enableReportButton then
        reportButton:Show()
    end
    reportButton:SetScript("OnEnter", function(self)
        BigFoot_ShowNewbieTooltip(L["Report"])
    end)
    reportButton:SetScript("OnLeave", function(self)
        BigFoot_HideNewbieTooltip()
    end)
end
function BFCIconFrameReportButton_OnClick(self, button)
    if button == "LeftButton" then
        wipe(MyData)
        local ok = pcall(StatReport_UpdateMyData)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("bigfoot_channel：当前属性数据暂不可读。")
            return
        end
        local msg = BF_StatReport
        msg = msg .. MyData.CLASS
        msg = msg .. StatReport_Strings_COMMA
        if MyData.TKEY and MyData.TDATA then
            msg = msg .. StatReport_Strings_TALENT .. ":" .. MyData.TKEY .. "(" .. MyData.TDATA .. ")"
            msg = msg .. StatReport_Strings_COMMA
        end
        if MyData.ILVL then
            msg = msg .. StatReport_Strings_ILVL .. MyData.ILVL
        end
        if MyData.AF then
            msg = msg .. StatReport_Strings_COMMA
            msg = msg .. StatReport_Strings_AFT .. MyData.AF
        end
        if MyData.AI then
            msg = msg .. StatReport_Strings_COMMA
            msg = msg .. StatReport_Strings_AIT .. MyData.AI
        end
        if MyData.Covenant then
            msg = msg .. StatReport_Strings_COMMA
            msg = msg .. StatReport_Strings_Covenant .. MyData.Covenant
        end
        if MyData.MST then
            msg = msg .. StatReport_Strings_COMMA
            msg = msg .. StatReport_Strings_MST .. MyData.MST
        end
        if MyData.CRIT then
            msg = msg .. StatReport_Strings_COMMA
            msg = msg .. StatReport_Strings_CRIT .. MyData.CRIT
        end
        if MyData.HASTE then
            msg = msg .. StatReport_Strings_COMMA
            msg = msg .. StatReport_Strings_HASTE .. MyData.HASTE
        end
        if MyData.VSTLT then
            msg = msg .. StatReport_Strings_COMMA
            msg = msg .. StatReport_Strings_VSTLT .. MyData.VSTLT
        end
        msg = msg .. StatReport_Strings_END
        StatReport_ChatFrameEditBoxMSG(msg)
    end
end
