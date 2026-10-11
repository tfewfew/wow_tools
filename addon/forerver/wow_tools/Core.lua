local initialized = false
local function OpenMenu(owner)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        DEFAULT_CHAT_FRAME:AddMessage("wow_tools：菜单接口暂不可用，可使用 /wowdetector on 或 /igc。")
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("wow_tools（无限服）")
        for _, name in ipairs({ "wowDetector", "inner_graphic_config" }) do
            local module = WoWTools.modules[name]
            root:CreateCheckbox(name, module.IsShown, module.Toggle)
        end
    end)
end
local minimapButton = CreateFrame("Button", "wowToolsMinimapButton", Minimap)
minimapButton:SetSize(32, 32)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local minimapIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetSize(20, 20)
minimapIcon:SetPoint("CENTER")
minimapIcon:SetTexture("Interface\\Icons\\Trade_Fishing")
local minimapBorder = minimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetSize(54, 54)
minimapBorder:SetPoint("TOPLEFT")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function PositionMinimapButton()
    local angle = math.rad(wowDetectorDB.minimapAngle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    -- Follow the minimap edge; also support square minimaps.
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local edge = math.max(math.abs(x), math.abs(y))
        x, y = x / edge, y / edge
    end
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        x * (Minimap:GetWidth() / 2 + 6), y * (Minimap:GetHeight() / 2 + 6))
end

minimapButton:SetScript("OnClick", function(self, button)
    if not initialized then return end
    if button == "RightButton" then
        OpenMenu(self)
    else
        WoWTools.modules.wowDetector.Toggle()
    end
end)
minimapButton:SetScript("OnDragStart", function(self)
    if not initialized then return end
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local cx, cy = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        wowDetectorDB.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
        PositionMinimapButton()
    end)
end)
minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
minimapButton:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("wow_tools")
    GameTooltip:AddLine("左键：打开并启动监测 / 关闭并隐藏", 1, 1, 1)
    GameTooltip:AddLine("右键：打开子插件菜单", 1, 1, 1)
    GameTooltip:AddLine("右侧小色块：蓝色=鱼饵附魔有效，紫色=缺少附魔", 1, 1, 1)
    GameTooltip:AddLine("拖动：调整小地图入口位置", 1, 1, 1)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    if name ~= "wow_tools" then return end
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.minimapAngle) ~= "number" then wowDetectorDB.minimapAngle = 225 end
    initialized = true
    PositionMinimapButton()
end)
SLASH_WOWTOOLS1 = "/wowtools"
SlashCmdList.WOWTOOLS = function() OpenMenu(minimapButton) end
