local BFChat = LibStub("AceAddon-3.0"):GetAddon("WoWToolsBigFootChannel")
local L = LibStub("AceLocale-3.0"):GetLocale("WoWToolsBigFootChannel")
local previews = {}

function createRaidersFrame()
    local button = BFCIconFrameRaidersButton
    local enabled = BFChat.db.profile.enableRaidersButton and BFChat:GetModuleEnabled("ICONFRAME")
    button:SetShown(enabled and Raid_List[GetZoneText()] ~= nil)
    if enabled then
        button:RegisterEvent("ZONE_CHANGED")
        button:RegisterEvent("ZONE_CHANGED_INDOORS")
        button:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    else
        button:UnregisterAllEvents()
    end
end

function raidersFrame_Init()
    local button = BFCIconFrameRaidersButton
    button:SetPoint("LEFT", BFCIconFrameReportButton, "RIGHT", 1, 0)
    button:SetScript("OnEnter", function()
        BigFoot_ShowNewbieTooltip(L["Raiders"])
    end)
    button:SetScript("OnLeave", BigFoot_HideNewbieTooltip)
    button:SetScript("OnEvent", createRaidersFrame)
    button:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, menu)
            menu:CreateTitle(L["Raiders"])
            for _, boss in ipairs(Raid_List[GetZoneText()] or {}) do
                menu:CreateButton(boss.name, function()
                    previews[#previews + 1] = boss
                    DEFAULT_CHAT_FRAME:AddMessage(
                        boss.name
                            .. " "
                            .. boss.raiders
                            .. " |cff00b4ff|Hwowtoolsraider:"
                            .. #previews
                            .. "|h[发送攻略]|h|r",
                        1,
                        0.9,
                        0.4
                    )
                end)
            end
        end)
    end)
    createRaidersFrame()
end

local function SendPreview(link)
    local index = tonumber(link:match("^wowtoolsraider:(%d+)$"))
    local boss = previews[index]
    if not boss then
        return
    end
    local destination = "SAY"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        destination = "INSTANCE_CHAT"
    elseif IsInRaid() then
        destination = "RAID"
    elseif IsInGroup() then
        destination = "PARTY"
    end
    C_ChatInfo.SendChatMessage(BFRAIDER_AD .. boss.name, destination)
    C_ChatInfo.SendChatMessage(boss.raiders, destination)
end

function BFCIconFrameRaidersButton_OnLoad()
    local original = ItemRefTooltip.SetHyperlink
    ItemRefTooltip.SetHyperlink = function(self, link, ...)
        if
            type(link) == "string"
            and not (issecretvalue and issecretvalue(link))
            and link:match("^wowtoolsraider:")
        then
            return
        end
        return original(self, link, ...)
    end
    hooksecurefunc("SetItemRef", function(link)
        if type(link) == "string" and not (issecretvalue and issecretvalue(link)) then
            SendPreview(link)
        end
    end)
end
