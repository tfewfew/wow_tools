local ns = WoWTools.foreverFaces

local function Tooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.BuildStyleSettings(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(560, 900)
    panel.controls = {}
    local function Label(text, y, color)
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 16, y)
        label:SetWidth(528)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        if color then label:SetTextColor(1, 0.78, 0.3) end
        return label
    end
    Label("像素风调试", -16)
    Label("本页参数保存后即时应用，战斗中的模型结构调整在脱战后应用。", -46)
    Label("需要 Reload 的项目", -82, true)
    Label("安装本次更新后需 /reload。插件列表的加载开关需 Reload。", -108)
    Label("模型与采样说明", -148, true)
    Label("客户端公开接口缺少强制 LOD。可填写客户端已有的低模 DisplayID 或 FileID。\n像素化使用离屏快照，实际分辨率、3D 捕获和采样效果由游戏内调试确认。", -174)
    local y = -234
    for _, option in ipairs(ns.style.options) do
        local row = CreateFrame("Frame", nil, panel)
        row:SetPoint("TOPLEFT", 16, y)
        row:SetSize(528, 32)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT")
        label:SetWidth(270)
        label:SetJustifyH("LEFT")
        label:SetText(option.label)
        row:EnableMouse(true)
        Tooltip(row, option.label, option.help)
        local control
        if option.choices then
            control = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
            control:SetPoint("RIGHT")
            control:SetWidth(240)
            control:SetupMenu(function(_, root)
                for _, choice in ipairs(option.choices) do
                    root:CreateRadio(choice[2], function() return ns.style.Config()[option.key] == choice[1] end,
                        function() ns.SetStyle(option.key, choice[1]) end)
                end
            end)
        elseif option.minimum then
            control = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            control:SetPoint("RIGHT", -90, 0)
            control:SetSize(140, 24)
            control:SetAutoFocus(false)
            control:SetNumeric(true)
            control:SetMaxLetters(10)
            local save = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            save:SetPoint("RIGHT")
            save:SetSize(76, 24)
            save:SetText("应用")
            local function Apply()
                local value = tonumber(control:GetText())
                if not value or value < option.minimum or value > option.maximum or value ~= math.floor(value) then
                    ns.Print(option.label .. "请输入 " .. option.minimum .. "–" .. option.maximum .. " 的整数")
                    return
                end
                -- Notify refreshes the whole page synchronously. Commit this
                -- field before notifying and preserve every other draft.
                control.dirty = false
                ns.SetStyle(option.key, value)
                control:ClearFocus()
            end
            control:HookScript("OnTextChanged", function(self, userInput)
                if userInput then self.dirty = true end
            end)
            control:HookScript("OnEditFocusGained", function(self) self.editing = true end)
            control:HookScript("OnEditFocusLost", function(self)
                self.editing = false
                if self.dirty then Apply() end
            end)
            control:SetScript("OnEnterPressed", Apply)
            control:SetScript("OnEscapePressed", function(self)
                self.dirty = false
                self:ClearFocus()
                panel:Refresh()
            end)
            save:SetScript("OnClick", Apply)
            Tooltip(save, "应用" .. option.label, option.help)
            control.apply = save
        else
            control = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            control:SetPoint("RIGHT")
            control:SetSize(28, 28)
            control:SetScript("OnClick", function(self) ns.SetStyle(option.key, self:GetChecked() and true or false) end)
        end
        Tooltip(control, option.label, option.help)
        panel.controls[option.key] = control
        y = y - 40
    end
    local rebuild = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    rebuild:SetPoint("TOPLEFT", 16, y - 8)
    rebuild:SetSize(170, 26)
    rebuild:SetText("重载模型 / 重建快照")
    rebuild:SetScript("OnClick", function() ns.ReloadPortraitModels() end)
    Tooltip(rebuild, "重载模型 / 重建快照", "按当前保存的参数重新加载模型并重建快照，战斗中的结构调整等待脱战。")
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetPoint("LEFT", rebuild, "RIGHT", 12, 0)
    reset:SetSize(150, 26)
    reset:SetText("恢复调试默认值")
    reset:SetScript("OnClick", function()
        for _, control in pairs(panel.controls) do
            if control.apply then
                control.dirty = false
                control:ClearFocus()
            end
        end
        ns.Set("style", {})
    end)
    Tooltip(reset, "恢复调试默认值", "清除本页编辑草稿并恢复像素风调试的默认参数。")
    panel.status = Label("", y - 58)
    panel:SetHeight(-y + 190)
    local function UpdateStatus()
        panel.status:SetText(ns.PortraitStyleStatus())
        local height = -y + 74 + math.max(80, panel.status:GetStringHeight())
        if panel:GetHeight() ~= height then
            panel:SetHeight(height)
            if ns.LayoutSettingsCard then ns.LayoutSettingsCard() end
        end
    end
    function panel:Refresh()
        local config = ns.style.Config()
        for _, option in ipairs(ns.style.options) do
            local control = self.controls[option.key]
            if option.choices then
                for _, choice in ipairs(option.choices) do
                    if choice[1] == config[option.key] then control:SetDefaultText(choice[2]) end
                end
                control:GenerateMenu()
            elseif option.minimum then
                if not control.dirty and not control.editing then
                    control:SetText(tostring(config[option.key]))
                end
            else
                control:SetChecked(config[option.key])
            end
        end
        UpdateStatus()
    end
    panel:SetScript("OnShow", function(self) self:Refresh() end)
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then
            elapsed = 0
            UpdateStatus()
        end
    end)
    ns.OnChange(function() if panel:IsVisible() then panel:Refresh() end end)
    return panel
end
