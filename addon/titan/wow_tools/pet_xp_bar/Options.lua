local Addon = WoWTools.petXPBar
local Compat = Addon.Compat

local PURPLE = { r = 0.58, g = 0.24, b = 0.86 }
local BLUE = { r = 25 / 255, g = 125 / 255, b = 255 / 255 }

local DEFAULTS = {
    showXPBar = true,
    showPetLevel = true,
    alwaysShowXPBar = false,
    alwaysShowPetLevel = false,
    locked = false,
    xpTextMode = "percent",
}
Addon.DEFAULTS = DEFAULTS

local function CopyColor(color)
    return { r = color.r, g = color.g, b = color.b }
end

function Addon.InitializeDB()
    Addon.db = Addon.GetSettings().db

    for key, value in pairs(DEFAULTS) do
        if Addon.db[key] == nil then
            Addon.db[key] = value
        end
    end

    if Addon.db.xpTextMode ~= "percent" and Addon.db.xpTextMode ~= "value" and Addon.db.xpTextMode ~= "none" then
        Addon.db.xpTextMode = DEFAULTS.xpTextMode
    end

    if type(Addon.db.xpColor) ~= "table" then
        Addon.db.xpColor = CopyColor(Compat.isForever and PURPLE or BLUE)
    end
end

function Addon.BuildOptions(parent)
    local controls = {}
    local colorRadios = {}
    local textRadios = {}
    local customLabel, customSample

    local function ColorToHex(color)
        local r = math.floor((color.r or 0) * 255 + 0.5)
        local g = math.floor((color.g or 0) * 255 + 0.5)
        local b = math.floor((color.b or 0) * 255 + 0.5)
        return string.format("#%02X%02X%02X", r, g, b)
    end

    local function SameColor(a, b)
        return a and b and math.abs(a.r - b.r) < 0.001 and math.abs(a.g - b.g) < 0.001 and math.abs(a.b - b.b) < 0.001
    end

    local function Apply()
        if Addon.Refresh then Addon.Refresh() end
        if Addon.ApplyXPBarColor then Addon.ApplyXPBarColor() end
        if Addon.SetLocked then Addon.SetLocked(Addon.db.locked) end
    end

    local function RefreshControls()
        for key, check in pairs(controls) do
            check:SetChecked(Addon.db[key])
        end
        for key, radio in pairs(textRadios) do
            radio:SetChecked(key == Addon.db.xpTextMode)
        end
        local mode = Addon.db.xpColorMode
        if not mode then
            if SameColor(Addon.db.xpColor, PURPLE) then mode = "purple"
            elseif SameColor(Addon.db.xpColor, BLUE) then mode = "blue"
            else mode = "custom" end
        end
        for key, radio in pairs(colorRadios) do
            radio:SetChecked(key == mode)
        end
        if customSample then
            local color = Addon.db.xpColor
            customSample:SetColorTexture(color.r, color.g, color.b)
        end
        if customLabel then
            customLabel:SetText(mode == "custom" and ("自定义颜色（" .. ColorToHex(Addon.db.xpColor) .. "）") or "自定义颜色")
        end
    end
    Addon.RefreshControls = RefreshControls

    local function SetColor(color, mode)
        Addon.db.xpColor = CopyColor(color)
        if mode then Addon.db.xpColorMode = mode end
        RefreshControls()
        Apply()
    end

    local function ResetDefaults()
        for key, value in pairs(DEFAULTS) do
            Addon.db[key] = value
        end
        Addon.db.xpColor = CopyColor(Compat.isForever and PURPLE or BLUE)
        Addon.db.xpColorMode = Compat.isForever and "purple" or "blue"
        if Addon.ResetPosition then Addon.ResetPosition() end
        RefreshControls()
        Apply()
    end
    Addon.ResetDefaults = ResetDefaults

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -28, 0)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(math.max(1, parent:GetWidth() - 40), 512)
    scroll:SetScrollChild(panel)
    scroll:SetScript("OnSizeChanged", function(self, width) panel:SetWidth(math.max(1, width)) end)
    Addon.optionsPanel = panel
    panel.name = "宠物经验"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("宠物经验")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("猎人宠物经验条与等级显示")

    local function MakeCheckbox(label, key, y)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 16, y)
        local textRegion = check.Text or check.text
        if textRegion then textRegion:SetText(label) end
        controls[key] = check
        check:SetScript("OnShow", function(self) self:SetChecked(Addon.db[key]) end)
        check:SetScript("OnClick", function(self)
            Addon.db[key] = self:GetChecked() and true or false
            Apply()
        end)
        return check
    end

    MakeCheckbox("显示经验条", "showXPBar", -58)
    MakeCheckbox("显示宠物等级", "showPetLevel", -88)

    local textTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    textTitle:SetPoint("TOPLEFT", 260, -58)
    textTitle:SetText("经验条文字")

    local function MakeTextRadio(key, label, y)
        local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
        radio:SetPoint("TOPLEFT", 260, y)
        textRadios[key] = radio

        local textRegion = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        textRegion:SetPoint("LEFT", radio, "RIGHT", 8, 0)
        textRegion:SetText(label)

        radio:SetScript("OnClick", function()
            Addon.db.xpTextMode = key
            RefreshControls()
            Apply()
        end)
    end

    MakeTextRadio("percent", "百分比", -84)
    MakeTextRadio("value", "当前经验 / 所需经验", -114)
    MakeTextRadio("none", "隐藏文字", -144)

    local behaviorTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    behaviorTitle:SetPoint("TOPLEFT", 16, -126)
    behaviorTitle:SetText("显示规则")

    MakeCheckbox("始终显示经验条", "alwaysShowXPBar", -150)
    MakeCheckbox("始终显示宠物等级", "alwaysShowPetLevel", -180)

    local behaviorNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    behaviorNote:SetPoint("TOPLEFT", 42, -208)
    behaviorNote:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    behaviorNote:SetJustifyH("LEFT")
    behaviorNote:SetText("宠物无法获得经验时自动隐藏经验条，满级时自动隐藏等级。")

    local appearanceTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    appearanceTitle:SetPoint("TOPLEFT", 16, -244)
    appearanceTitle:SetText("经验条颜色")

    local function MakeButton(label, x, y, width, onClick)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", x, y)
        button:SetText(label)
        button:SetScript("OnClick", onClick)
        return button
    end

    local function MakeColorRadio(key, label, color, y)
        local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
        radio:SetPoint("TOPLEFT", 16, y)
        colorRadios[key] = radio

        local sample = panel:CreateTexture(nil, "ARTWORK")
        sample:SetSize(18, 18)
        sample:SetPoint("LEFT", radio, "RIGHT", 4, 0)
        sample:SetColorTexture(color.r, color.g, color.b)

        local textRegion = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        textRegion:SetPoint("LEFT", sample, "RIGHT", 8, 0)
        textRegion:SetText(label)

        radio:SetScript("OnClick", function()
            SetColor(color, key)
        end)
        return radio, textRegion
    end

    MakeColorRadio("purple", "无限服紫色", PURPLE, -268)
    MakeColorRadio("blue", "经典蓝色", BLUE, -298)

    local customRadio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
    customRadio:SetPoint("TOPLEFT", 16, -328)
    colorRadios.custom = customRadio

    customSample = panel:CreateTexture(nil, "ARTWORK")
    customSample:SetSize(18, 18)
    customSample:SetPoint("LEFT", customRadio, "RIGHT", 4, 0)
    customSample:SetColorTexture(1, 1, 1)

    customLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    customLabel:SetPoint("LEFT", customSample, "RIGHT", 8, 0)
    customLabel:SetText("自定义颜色")

    local function OpenColorPicker()
        local old = CopyColor(Addon.db.xpColor)
        local oldMode = Addon.db.xpColorMode

        local function changed()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            customSample:SetColorTexture(r, g, b)
            SetColor({ r = r, g = g, b = b }, "custom")
        end
        local function cancelled(previous)
            local restore = (type(previous) == "table" and previous.r) and previous or old
            customSample:SetColorTexture(restore.r, restore.g, restore.b)
            Addon.db.xpColorMode = oldMode
            SetColor(restore, oldMode)
        end

        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = old.r, g = old.g, b = old.b,
                swatchFunc = changed,
                cancelFunc = cancelled,
                hasOpacity = false,
            })
        else
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = old
            ColorPickerFrame.func = changed
            ColorPickerFrame.cancelFunc = cancelled
            ColorPickerFrame:SetColorRGB(old.r, old.g, old.b)
            ColorPickerFrame:Show()
        end
    end
    customRadio:SetScript("OnClick", OpenColorPicker)
    local positionTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    positionTitle:SetPoint("TOPLEFT", 16, -370)
    positionTitle:SetText("位置")

    MakeCheckbox("锁定位置", "locked", -392)
    MakeButton("重置位置", 42, -424, 112, function()
        if Addon.ResetPosition then Addon.ResetPosition() end
    end)

    MakeButton("恢复默认", 16, -470, 96, ResetDefaults)

    panel:SetScript("OnShow", function()
        RefreshControls()
    end)

    RefreshControls()
end
