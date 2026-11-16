WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Character-specific options for Raynna's installed tracker and bestiary.
local _, Addon = ...
local panel
local refreshers = {}

local function label(text, x, y, heading)
    local textRegion =
        panel:CreateFontString(nil, 'OVERLAY', heading and 'GameFontNormalLarge' or 'GameFontHighlight')
    textRegion:SetPoint('TOPLEFT', x, y)
    textRegion:SetText(text)
    return textRegion
end

local function checkbox(text, x, y, get, set)
    local control = CreateFrame('CheckButton', nil, panel, 'UICheckButtonTemplate')
    control:SetSize(26, 26)
    control:SetPoint('TOPLEFT', x, y)
    label(text, x + 30, y - 6)
    local function refresh()
        control:SetChecked(get())
    end
    control:SetScript('OnClick', function(self)
        set(self:GetChecked() and true or false)
    end)
    refreshers[#refreshers + 1] = refresh
end

local function button(text, x, y, callback)
    local control = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
    control:SetPoint('TOPLEFT', x, y)
    control:SetSize(150, 24)
    control:SetText(text)
    control:SetScript('OnClick', callback)
end

local function percentage(text, y, get, set, minimum, maximum)
    label(text, 24, y - 5)
    local input = CreateFrame('EditBox', nil, panel, 'InputBoxTemplate')
    input:SetPoint('TOPLEFT', 245, y)
    input:SetSize(65, 24)
    input:SetAutoFocus(false)
    input:SetMaxLetters(5)
    local function refresh()
        input:SetText(math.floor(get() * 100 + 0.5) .. '%')
    end
    local function apply(value)
        if value then
            set(math.max(minimum, math.min(maximum, value)))
        end
        refresh()
    end
    input:SetScript('OnEnterPressed', function(self)
        apply(tonumber((self:GetText() or ''):match('^%s*(%d+)%s*%%?%s*$')))
        self:ClearFocus()
    end)
    input:SetScript('OnEscapePressed', function(self)
        refresh()
        self:ClearFocus()
    end)
    input:SetScript('OnEditFocusLost', refresh)
    for index, delta in ipairs({ -5, 5 }) do
        local control = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
        control:SetPoint('TOPLEFT', index == 1 and 212 or 318, y)
        control:SetSize(24, 24)
        control:SetText(delta < 0 and '-' or '+')
        control:SetScript('OnClick', function()
            apply(math.floor(get() * 100 + 0.5) + delta)
        end)
    end
    refreshers[#refreshers + 1] = refresh
end

function Addon.BuildOptions(host)
        panel = host
        label("Raynna's Bestiary", 24, -20, true)
        label('修改立即生效，并按角色保存。', 24, -50)
        checkbox('Alt 指向怪物显示掉落', 24, -85, function()
            return Addon.db.bestiary.npcHover ~= false
        end, function(value)
            Addon.db.bestiary.npcHover = value
        end)
        checkbox('Alt 指向物品显示来源', 280, -85, function()
            return Addon.db.bestiary.itemHover ~= false
        end, function(value)
            Addon.db.bestiary.itemHover = value
        end)
        percentage('怪物图鉴缩放', -130, function()
            return Addon.db.bestiary.scale or 1
        end, function(value)
            Addon.SetBestiaryScale(value / 100)
        end, 40, 180)
        button('打开怪物图鉴', 365, -130, function()
            SlashCmdList.RAYNNABESTIARY('')
        end)
        label('怪物图鉴外观', 24, -190, true)
        checkbox('羊皮纸背景', 24, -225, function()
            return Addon.db.appearance.paper ~= false
        end, function(value)
            Addon.SetAppearance('paper', value)
        end)
        percentage('背景不透明度', -270, function()
            return Addon.db.appearance.opacity or 0.97
        end, function(value)
            Addon.SetAppearance('opacity', value / 100)
        end, 20, 100)
        local function refresh()
            for _, callback in ipairs(refreshers) do
                callback()
            end
        end
        panel:SetScript('OnShow', refresh)
        return refresh
end
end)
