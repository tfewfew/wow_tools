-- Account-level switches take effect at the next UI load.
local manager = { entries = {}, active = {} }
WoWTools.thirdParty = manager
WoWTools.modules.third_party = manager

function manager.Register(key, label, openSettings)
    manager.entries[#manager.entries + 1] = { key = key, label = label, openSettings = openSettings }
end

local function Saved()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.thirdPartyAddons) ~= "table" then wowDetectorDB.thirdPartyAddons = {} end
    return wowDetectorDB.thirdPartyAddons
end

function manager.IsEnabled(key)
    return Saved()[key] ~= false
end

function manager.IsActive(key)
    if manager.active[key] == nil then manager.active[key] = manager.IsEnabled(key) end
    return manager.active[key]
end

function manager.SetEnabled(key, enabled)
    manager.IsActive(key)
    Saved()[key] = not not enabled
    manager.RefreshSettings()
end

manager.Register("bigfoot_channel", "大脚聊天", function() WoWTools.settings.Open("bigfoot_channel") end)
manager.Register("ls_toasts", "lsToast", function() WoWTools.settings.Open("ls_toasts") end)

function manager.RefreshSettings()
    local panel = manager.panel
    if not panel then return end
    for _, row in ipairs(panel.rows) do
        local key = row.entry.key
        local enabled, active = manager.IsEnabled(key), manager.IsActive(key)
        row.check:SetChecked(enabled)
        row.configure:SetEnabled(active)
        local status = active and "已启用" or "已停用"
        if enabled ~= active then status = enabled and "重载后启用" or "重载后停用" end
        row.status:SetText(status)
    end
    panel.reload:SetEnabled(not InCombatLockdown())
    panel.hint:SetText(InCombatLockdown() and "战斗结束后可重载界面。" or "勾选后自动保存，点击 Reload 后生效。")
end

function manager.BuildSettings(parent)
    if manager.panel then return manager.panel end
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.rows = {}
    manager.panel = panel

    local reload = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reload:SetSize(116, 26)
    reload:SetPoint("TOPLEFT", 16, -16)
    reload:SetText("Reload")
    reload:SetScript("OnClick", function()
        if not InCombatLockdown() then ReloadUI() end
    end)
    panel.reload = reload
    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", reload, "BOTTOMLEFT", 0, -12)
    hint:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    panel.hint = hint

    for index, entry in ipairs(manager.entries) do
        local row = CreateFrame("Frame", nil, panel)
        row.entry = entry
        row:SetPoint("TOPLEFT", 16, -88 - (index - 1) * 48)
        row:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
        row:SetHeight(32)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(28, 28)
        row.check:SetPoint("LEFT")
        row.label = row.check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.label:SetText(entry.label)
        row.check:SetScript("OnClick", function(self) manager.SetEnabled(entry.key, self:GetChecked()) end)
        row.configure = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.configure:SetSize(72, 24)
        row.configure:SetPoint("RIGHT")
        row.configure:SetText("设置")
        row.configure:SetScript("OnClick", function()
            if manager.IsActive(entry.key) then entry.openSettings() end
        end)
        row.status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.status:SetPoint("RIGHT", row.configure, "LEFT", -16, 0)
        panel.rows[#panel.rows + 1] = row
    end
    panel:SetScript("OnShow", manager.RefreshSettings)
    return panel
end
