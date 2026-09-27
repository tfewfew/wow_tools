local ADDON = ...
local definitions = {
    {
        cvar = "ffxGlow",
        label = "全屏泛光效果",
        description = "控制画面中明亮区域的泛光效果。勾选开启，取消勾选关闭。",
    },
    { cvar = "particleDensity", label = "粒子密度（particleDensity）", numeric = true,
      description = "通用粒子密度：控制普通粒子发射器生成的粒子数量，影响火花、烟尘、雾气、环境粒子和部分法术效果。\n数值越高：效果更稠密、连续，粒子模拟和透明叠加开销增加。\n数值越低：画面更稀疏，可减少粒子开销。50 为当前建议的折中值。\n它不决定哪些法术显示，也不改变粒子纹理的分辨率。" },
    { cvar = "particleMTDensity", label = "粒子密度（particleMTDensity）", numeric = true,
      description = "Multi-Tex（多纹理）粒子密度：控制使用多张纹理或多层混合的复杂粒子效果数量；MT 指 Multi-Tex，不是多线程。\n数值越高：复杂法术、烟雾和光效的层次更饱满，透明混合与 GPU 填充开销增加。\n数值越低：减少这类复杂粒子，对大量叠加特效的场景更友好。33 比 50 更偏向性能。\n它与 particleDensity 同时生效；素材未使用多纹理粒子时，调整此项不会改变该效果。" },
    { cvar = "ffxAntiAliasingMode", label = "后处理抗锯齿模式", numeric = true, maximum = 4,
      meanings = { [0] = "关闭", [1] = "FXAA 低", [2] = "FXAA 高", [3] = "CMAA", [4] = "CMAA2" },
      description = "0：关闭；1：FXAA 低；2：FXAA 高；3：CMAA；4：CMAA2。下面的 CMAA2 参数在模式 4 下使用。" },
    { cvar = "cmaa2Quality", label = "CMAA2 质量（cmaa2Quality）", numeric = true, maximum = 3,
      meanings = { [0] = "低", [1] = "中", [2] = "高", [3] = "超高" },
      description = "CMAA2 算法档位（依据 Intel 参考源码）：\n0 低：边缘阈值 0.15，主要处理对比明显的边缘，减少弱边缘处理。\n1 中：阈值 0.10，纳入更多中等对比边缘，增加平滑覆盖。\n2 高：阈值 0.07，进一步处理较弱边缘；参考算法默认档位。\n3 超高：阈值 0.05，对弱边缘最敏感，覆盖最广。\n更高档位可能增加处理开销；编号不是采样倍数，也不是锐化强度。" },
    { cvar = "cmaa2ExtraSharpness", label = "CMAA2 额外锐利处理", numeric = true, maximum = 1,
      meanings = { [0] = "关闭", [1] = "开启" },
      description = "0 关闭：使用常规 CMAA2 平滑策略，优先消除锯齿。\n1 开启：更保守地识别、混合边缘，保留文字、细线和轮廓的清晰度；部分锯齿可能保留得更多。\n这是 CMAA2 内部的细节保留开关，不是额外叠加的全屏锐化滤镜。作用依据 Intel CMAA2 参考源码。" },
    { cvar = "volumeFogDisableLightScattering", label = "体积雾光照散射（volumeFogDisableLightScattering）", inverted = true,
      description = "控制点光源在体积雾中的散射效果。开启后，灯光穿过雾气时会形成可见的光晕和光束；关闭可减少相关渲染开销。" },
    { cvar = "volumeFogUse16BitTexture", label = "16 位体积雾纹理（volumeFogUse16BitTexture）",
      description = "开启后使用 16 位体积雾纹理，雾的明暗和颜色渐变更平滑，可减少色带；显存和带宽开销高于 8 位纹理。修改后需要执行 /console gxRestart 或重启游戏。" },
    { cvar = "volumeFogDisableShadows", label = "体积雾阴影（volumeFogDisableShadows）", inverted = true,
      description = "控制体积雾对阴影遮挡的表现。开启后，阴影区域会相应减少雾中的光照和散射，使光束层次更准确；关闭可减少相关渲染开销。" },
    { cvar = "volumeFogDisableNoise", label = "体积雾噪声（volumeFogDisableNoise）", inverted = true,
      description = "控制体积雾使用的噪声扰动。开启后可打散规则采样，减少明显分层和过于均匀的雾感；关闭后雾面可能更平整。" },
    { cvar = "gxMTVolFog", label = "体积雾并行渲染（gxMTVolFog）",
      description = "控制体积雾渲染任务是否并行执行。开启通常能更好地利用多核处理器；它只改变渲染任务的执行方式，不直接改变体积雾画质。" },
    { cvar = "graphicsLiquidDetail", label = "总体液体档位（graphicsLiquidDetail）", numeric = true, maximum = 3,
      meanings = { [0] = "低", [1] = "较低", [2] = "中", [3] = "高" },
      description = "游戏图形设置中的普通液体总档位：0 低、1 较低、2 中、3 高。应用此项时，客户端会按预设联动水面、波纹和反射参数；需要逐项微调时，应在设置总档位后再修改下面的独立参数。" },
    { cvar = "waterDetail", label = "水面细节（waterDetail）", numeric = true, maximum = 3,
      meanings = { [0] = "低", [1] = "较低", [2] = "中", [3] = "高" },
      description = "控制水、岩浆等液体表面的着色与几何细节档位。0 至 3 由低到高；更高档位保留更完整的液体表面效果，也会增加 GPU 开销。" },
    { cvar = "rippleDetail", label = "波纹细节（rippleDetail）", numeric = true, maximum = 3,
      meanings = { [0] = "低", [1] = "较低", [2] = "中", [3] = "高" },
      description = "控制液体表面的波纹模拟与细节档位。0 至 3 由低到高；提高后波纹层次更丰富，对液体表面渲染的开销也更高。" },
    { cvar = "reflectionMode", label = "液体反射内容（reflectionMode）", numeric = true, maximum = 3,
      meanings = { [0] = "屏幕空间", [1] = "天空", [2] = "天空和地形", [3] = "天空、地形和建筑" },
      description = "客户端定义的反射内容：\n0 屏幕空间：使用画面中已有内容形成反射。\n1 天空：反射天空。\n2 天空和地形：增加地形反射。\n3 天空、地形和 WMO 建筑：反射内容最完整，渲染开销最高。" },
    { cvar = "reflectionDownscale", label = "反射降采样（reflectionDownscale）", numeric = true, maximum = 4,
      meanings = { [0] = "不降采样", [1] = "降采样 1 级", [2] = "降采样 2 级", [3] = "降采样 3 级", [4] = "降采样 4 级" },
      description = "控制反射缓冲区的降采样档位，客户端接受 0 至 4。0 保留最高反射分辨率；数值越高，反射使用的内部分辨率越低，性能开销越小，倒影会更模糊。" },
    { cvar = "gxMTRefraction", label = "折射通道并行渲染（gxMTRefraction）",
      description = "控制透明材质和液体使用的折射渲染通道是否并行执行。开启通常能更好地利用多核处理器；它只改变渲染任务的执行方式，不直接改变液体画质。" },
    { cvar = "raidGraphicsLiquidDetail", label = "团队总体液体档位（raidGraphicsLiquidDetail）", numeric = true, maximum = 3,
      meanings = { [0] = "低", [1] = "较低", [2] = "中", [3] = "高" },
      description = "启用团队图形设置时使用的液体总档位：0 低、1 较低、2 中、3 高。应用后会按团队预设联动下方水面、波纹和反射参数。" },
    { cvar = "RAIDWaterDetail", label = "团队水面细节（RAIDWaterDetail）", numeric = true, maximum = 3,
      meanings = { [0] = "低", [1] = "较低", [2] = "中", [3] = "高" },
      description = "启用团队图形设置时使用的水面细节档位。0 至 3 由低到高；控制水、岩浆等液体表面的着色与几何细节。" },
    { cvar = "RAIDrippleDetail", label = "团队波纹细节（RAIDrippleDetail）", numeric = true, maximum = 3,
      meanings = { [0] = "低", [1] = "较低", [2] = "中", [3] = "高" },
      description = "启用团队图形设置时使用的波纹细节档位。0 至 3 由低到高；控制液体表面的波纹模拟与细节。" },
    { cvar = "RAIDreflectionMode", label = "团队液体反射内容（RAIDreflectionMode）", numeric = true, maximum = 3,
      meanings = { [0] = "屏幕空间", [1] = "天空", [2] = "天空和地形", [3] = "天空、地形和建筑" },
      description = "启用团队图形设置时使用的反射内容：0 屏幕空间；1 天空；2 天空和地形；3 天空、地形和 WMO 建筑。档位越高，参与反射的场景内容越多。" },
    { cvar = "RAIDreflectionDownscale", label = "团队反射降采样（RAIDreflectionDownscale）", numeric = true, maximum = 4,
      meanings = { [0] = "不降采样", [1] = "降采样 1 级", [2] = "降采样 2 级", [3] = "降采样 3 级", [4] = "降采样 4 级" },
      description = "启用团队图形设置时使用的反射降采样档位，范围 0 至 4。数值越高，反射内部渲染分辨率越低，性能开销越小。" },
    { key = "frameratePosition", label = "帧率显示位置", action = true, defaultX = 0, defaultY = 180,
      description = "锨点固定为屏幕底部居中。X 控制左右偏移：正数向右，负数向左；Y 控制上下偏移：正数向上，负数向下。默认填入 X=0、Y=180。" },
}
local distanceCVars, raidDistanceCVars = {}, {}
local distanceDefinitions = {
    { "farclip", "远裁剪面距离", "世界远裁剪面；决定地形和远景最远可渲染距离。", true },
    { "nearclip", "近裁剪面距离", "摄像机附近裁剪面；比它更靠近镜头的几何体不渲染。" },
    { "horizonStart", "地平线起始距离", "远景地平线过渡开始的距离。", true },
    { "horizonClip", "地平线结束距离", "远景地平线过渡结束的距离。", true },
    { "terrainLodDist", "地形 LOD 距离", "地形切换细节等级的距离；较大值使高细节地形保留得更远。", true },
    { "TerrainLodDiv", "地形 LOD 除数", "地形 LOD 计算使用的底层除数，与地形 LOD 距离共同决定过渡。", true },
    { "wmoLODDist", "建筑 WMO LOD 距离", "建筑、洞穴等 WMO 世界模型切换细节等级的距离。", true },
    { "wmoLodDistScale", "WMO LOD 距离倍率", "对 WMO LOD 距离施加倍率，调整建筑远处细节的保留范围。" },
    { "wmoDoodadDist", "WMO 附属物加载距离", "建筑内外附属摆设和小物件的加载距离。" },
    { "wmoPortalFadeScale", "WMO 传送门淡出倍率", "调整 WMO 内外分区传送门的视觉淡出距离倍率。" },
    { "wmoPortalInteriorFade", "WMO 室内传送门淡出", "控制 WMO 室内分区过渡使用的淡出参数。" },
    { "doodadLodScale", "场景小物件 LOD 倍率", "树木、岩石、建筑附属物等 doodad 的 LOD 距离倍率；较大值保留更远的细节。", true },
    { "entityLodDist", "实体 LOD 距离", "角色、生物和其他实体模型的 LOD 距离。", true },
    { "entityLodOffset", "实体 LOD 偏移", "向实体 LOD 切换距离加入额外偏移。" },
    { "entityShadowFadeScale", "实体阴影淡出倍率", "调整角色和实体阴影随距离淡出的范围。", true },
    { "lodObjectCullDist", "LOD 物件剪除距离", "LOD 物件开始依据屏幕尺寸判定剪除的最小距离。", true },
    { "lodObjectCullSize", "LOD 物件剪除尺寸", "LOD 物件的屏幕尺寸剪除阈值；较大值会更早剪除远处小物件。", true },
    { "lodObjectMinSize", "LOD 物件最小尺寸", "LOD 物件继续显示的最小屏幕尺寸阈值。", true },
    { "lodObjectFadeScale", "LOD 物件淡出倍率", "调整 LOD 物件被剪除前的淡出过渡范围。", true },
    { "lodObjectSizeScale", "LOD 物件尺寸倍率", "统一缩放对象用于剪除判定的屏幕尺寸。" },
    { "groundEffectDist", "地表细节距离", "草丛、小石子等地表细节的显示距离。", true },
    { "groundEffectFade", "地表细节淡出距离", "地表细节在远处逐渐淡出的过渡参数。", true },
    { "maxLightDist", "灯光最大渲染距离", "点光源等灯光效果可被渲染的最大距离。" },
    { "preloadStreamingDistTerrain", "流式地形预加载距离", "移动时提前流式读取地形的距离；影响弹出、IO 和内存，不直接增加裁剪距离。" },
    { "preloadStreamingDistObject", "流式物件预加载距离", "移动时提前流式读取场景物件的距离。" },
    { "preloadLoadingDistTerrain", "载入地形预加载距离", "载入场景时预先读取地形的距离。" },
    { "preloadLoadingDistObject", "载入物件预加载距离", "载入场景时预先读取场景物件的距离。" },
    { "dynamicLod", "动态 LOD", "根据运行状况动态调整细节等级。开启后，实际远景细节可会随性能负载变化。", false, true },
}
for _, spec in ipairs(distanceDefinitions) do
    local cvar, label, description, raid, boolean = spec[1], spec[2], spec[3], spec[4], spec[5]
    local definition = { cvar = cvar, label = label .. "（" .. cvar .. "）", description = description }
    if not boolean then definition.numeric, definition.decimal = true, true end
    definitions[#definitions + 1] = definition
    distanceCVars[cvar] = true
    if raid then
        local raidCVar = "RAID" .. cvar
        local raidDefinition = { cvar = raidCVar, label = "团队 " .. label .. "（" .. raidCVar .. "）",
            description = "启用团队图形设置时使用。" .. description }
        if not boolean then raidDefinition.numeric, raidDefinition.decimal = true, true end
        definitions[#definitions + 1] = raidDefinition
        raidDistanceCVars[raidCVar] = true
    end
end
local controls = {}
local allDistanceCVars = {}
for cvar in pairs(distanceCVars) do allDistanceCVars[cvar] = true end
for cvar in pairs(raidDistanceCVars) do allDistanceCVars[cvar] = true end
local liquidCVars = {
    graphicsLiquidDetail = true,
    waterDetail = true,
    rippleDetail = true,
    reflectionMode = true,
    reflectionDownscale = true,
    gxMTRefraction = true,
}
local raidLiquidCVars = {
    raidGraphicsLiquidDetail = true,
    RAIDWaterDetail = true,
    RAIDrippleDetail = true,
    RAIDreflectionMode = true,
    RAIDreflectionDownscale = true,
}
local allLiquidCVars = {}
for cvar in pairs(liquidCVars) do allLiquidCVars[cvar] = true end
for cvar in pairs(raidLiquidCVars) do allLiquidCVars[cvar] = true end
local categories = {
    { name = "泛光", cvars = { ffxGlow = true } },
    { name = "粒子", cvars = { particleDensity = true, particleMTDensity = true } },
    { name = "CMAA", cvars = { ffxAntiAliasingMode = true, cmaa2Quality = true, cmaa2ExtraSharpness = true } },
    { name = "体积雾", cvars = {
        volumeFogDisableLightScattering = true,
        volumeFogUse16BitTexture = true,
        volumeFogDisableShadows = true,
        volumeFogDisableNoise = true,
        gxMTVolFog = true,
    } },
    { name = "距离", cvars = allDistanceCVars, subgroups = {
        { name = "普通距离", cvars = distanceCVars },
        { name = "团队距离", cvars = raidDistanceCVars },
    } },
    { name = "液体", cvars = allLiquidCVars, subgroups = {
        { name = "普通液体", cvars = liquidCVars },
        { name = "团队液体", cvars = raidLiquidCVars },
    } },
    { name = "界面", cvars = { frameratePosition = true } },
}
local function SmallDescription(text)
    local font, size, flags = text:GetFont()
    if font then text:SetFont(font, math.max(9, (size or 12) - 2) - 2, flags) end
end

local function ReadValue(name)
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    if not getter then return nil end
    local ok, value = pcall(getter, name)
    if ok then return tonumber(value) end
end

local function Refresh(force)
    for _, control in ipairs(controls) do
        if control.definition.action then
            local label = FramerateLabel
            if not label then
                if force or not control.dirty then
                    control.inputX:SetText(tostring(control.definition.defaultX))
                    control.inputY:SetText(tostring(control.definition.defaultY))
                    control.dirty = false
                end
                control.apply:SetEnabled(false)
                control.status:SetText("当前客户端未提供帧率标签")
            else
                control.apply:SetEnabled(true)
                local point, relativeTo, relativePoint, x, y = label:GetPoint(1)
                x, y = x or control.definition.defaultX, y or control.definition.defaultY
                if force or not control.dirty then
                    control.inputX:SetText(tostring(x))
                    control.inputY:SetText(tostring(y))
                    control.dirty = false
                end
                control.status:SetText("当前：" .. tostring(point or "无") .. "  X=" .. tostring(x) .. "  Y=" .. tostring(y))
            end
        else
        local value = ReadValue(control.definition.cvar)
        if control.definition.numeric then
            if force or not control.dirty then
                control.input:SetText(value ~= nil and tostring(value) or "")
                control.dirty = false
            end
            control.input:SetEnabled(value ~= nil)
            control.apply:SetEnabled(value ~= nil)
        else
            local checked = value ~= nil and value ~= 0
            if value ~= nil and control.definition.inverted then checked = value == 0 end
            control:SetChecked(checked)
            control:SetEnabled(value ~= nil)
        end
        if value == nil then
            control.status:SetText("当前客户端未提供此选项")
        else
            control.status:SetText(control.definition.numeric and ("当前值：" .. tostring(value)) or "")
            if control.definition.meanings and control.definition.meanings[value] then
                control.status:SetText("当前值：" .. tostring(value) .. "（" .. control.definition.meanings[value] .. "）")
            end
        end
        end
    end
end

local function ApplyFrameratePosition(control)
    if not FramerateLabel then
        Refresh()
        return
    end
    local rawX = control.inputX:GetText():match("^%s*(.-)%s*$")
    local rawY = control.inputY:GetText():match("^%s*(.-)%s*$")
    if not rawX:match("^-?%d+$") or not rawY:match("^-?%d+$") then
        control.status:SetText("请输入整数坐标")
        return
    end
    local x, y = tonumber(rawX), tonumber(rawY)
    control.dirty = false
    control.inputX:ClearFocus()
    control.inputY:ClearFocus()
    local ok = pcall(function()
        FramerateLabel:ClearAllPoints()
        FramerateLabel:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
    end)
    Refresh()
    if not ok then
        control.status:SetText("应用失败")
    end
end

local function Apply(control)
    local desired
    if control.definition.numeric then
        local raw = control.input:GetText():match("^%s*(.-)%s*$")
        local number = tonumber(raw)
        local valid = control.definition.decimal
            and (raw:match("^%d+%.?%d*$") or raw:match("^%d*%.%d+$"))
            or raw:match("^%d+$")
        if not valid or not number or number == math.huge then
            control.status:SetText(control.definition.decimal and "请输入非负数值。" or "请输入非负整数。")
            return
        end
        if control.definition.maximum and number > control.definition.maximum then
            control.status:SetText("请输入 0 到 " .. control.definition.maximum .. " 之间的整数。")
            return
        end
        desired = tostring(number)
        control.dirty = false
        control.input:ClearFocus()
    else
        local checked = control:GetChecked()
        if control.definition.inverted then
            desired = checked and "0" or "1"
        else
            desired = checked and "1" or "0"
        end
    end
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    local ok = setter and pcall(setter, control.definition.cvar, desired)
    Refresh()
    if not ok or ReadValue(control.definition.cvar) ~= tonumber(desired) then
        print("|cffffcc00Inner_graphic_config：|r设置未生效，已重新读取游戏当前值。")
    end
end

local function BuildControls(parent)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -24)
    title:SetText("内部画面设置")
    local subtitle = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    subtitle:SetText("直接读取并修改游戏当前设置。")
    SmallDescription(subtitle)
    local refresh = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    refresh:SetSize(90, 24)
    refresh:SetPoint("TOPRIGHT", -20, -20)
    refresh:SetText("刷新全部")
    refresh:SetScript("OnClick", function() Refresh(true) end)
    local pages, tabs, layouts, subTabsByCategory, activeSubgroups = {}, {}, {}, {}, {}
    local tabGroup = CreateRadioButtonGroup()
    local function SelectTab(selected)
        tabGroup:SelectAtIndex(selected)
        for i, page in ipairs(pages) do
            if i == selected then
                page:Show()
                layouts[i]()
            else
                page:Hide()
            end
            if subTabsByCategory[i] then
                for _, subTab in ipairs(subTabsByCategory[i]) do
                    if i == selected then subTab:Show() else subTab:Hide() end
                end
            end
        end
        Refresh()
    end
    local tabStep = math.floor(456 / #categories)
    local tabWidth = math.min(72, tabStep - 3)
    for categoryIndex, category in ipairs(categories) do
    local tabIndex = categoryIndex
    local tab = CreateFrame("Button", nil, parent, "MinimalTabTemplate")
    tab:SetSize(tabWidth, 33)
    tab:SetPoint("TOPLEFT", 20 + (categoryIndex - 1) * tabStep, -70)
    tab.Text:SetText(category.name)
    tabGroup:AddButton(tab)
    tab:SetScript("OnClick", function() SelectTab(tabIndex) end)
    tabs[categoryIndex] = tab
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, category.subgroups and -150 or -112)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(420, 1)
    scroll:SetScrollChild(list)
    pages[categoryIndex] = scroll
    local entries = {}
    local function Layout()
        local offset = 0
        for _, entry in ipairs(entries) do
            local subgroup = category.subgroups and category.subgroups[activeSubgroups[categoryIndex] or 1]
            local visible = not subgroup or subgroup.cvars[entry.key]
            if visible then
                entry.widget:Show()
                entry.widget:ClearAllPoints()
                entry.widget:SetPoint("TOPLEFT", entry.x, -offset)
                local height = entry.topHeight + entry.help:GetStringHeight()
                if entry.widget.definition.numeric or entry.widget.definition.action then entry.widget:SetHeight(height) end
                offset = offset + height + 24
            else
                entry.widget:Hide()
            end
        end
        list:SetHeight(math.max(1, offset))
    end
    layouts[categoryIndex] = Layout
    if category.subgroups then
        activeSubgroups[categoryIndex] = 1
        subTabsByCategory[categoryIndex] = {}
        local subgroupTabs = CreateRadioButtonGroup()
        for subgroupIndex, subgroup in ipairs(category.subgroups) do
            local selectedSubgroup = subgroupIndex
            local subTab = CreateFrame("Button", nil, parent, "MinimalTabTemplate")
            subTab:SetSize(104, 33)
            subTab:SetPoint("TOPLEFT", 20 + (subgroupIndex - 1) * 108, -108)
            subTab.Text:SetText(subgroup.name)
            subgroupTabs:AddButton(subTab)
            subTab:SetScript("OnClick", function()
                activeSubgroups[categoryIndex] = selectedSubgroup
                subgroupTabs:SelectAtIndex(selectedSubgroup)
                Layout()
                Refresh()
            end)
            subTabsByCategory[categoryIndex][#subTabsByCategory[categoryIndex] + 1] = subTab
        end
        subgroupTabs:SelectAtIndex(1)
    end
    for index, definition in ipairs(definitions) do
        if category.cvars[definition.cvar or definition.key] then
        if definition.action then
            local row = CreateFrame("Frame", nil, list)
            row:SetSize(410, 1)
            row.definition = definition
            row.dirty = false
            local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            label:SetPoint("TOPLEFT")
            label:SetText(definition.label)
            local xLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            xLabel:SetPoint("TOPLEFT", 0, -26)
            xLabel:SetText("X")
            row.inputX = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.inputX:SetSize(76, 24)
            row.inputX:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)
            row.inputX:SetAutoFocus(false)
            row.inputX:SetMaxLetters(8)
            local yLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            yLabel:SetPoint("LEFT", row.inputX, "RIGHT", 16, 0)
            yLabel:SetText("Y")
            row.inputY = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.inputY:SetSize(76, 24)
            row.inputY:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)
            row.inputY:SetAutoFocus(false)
            row.inputY:SetMaxLetters(8)
            local function MarkDirty(_, userInput)
                if userInput then row.dirty = true end
            end
            row.inputX:SetScript("OnTextChanged", MarkDirty)
            row.inputY:SetScript("OnTextChanged", MarkDirty)
            row.inputX:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            row.inputY:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            row.apply = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.apply:SetSize(92, 24)
            row.apply:SetPoint("LEFT", row.inputY, "RIGHT", 14, 0)
            row.apply:SetText("应用位置")
            row.apply:SetScript("OnClick", function() ApplyFrameratePosition(row) end)
            row.status = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            row.status:SetPoint("TOPLEFT", 0, -54)
            local help = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            help:SetPoint("TOPLEFT", 0, -74)
            help:SetWidth(398)
            help:SetJustifyH("LEFT")
            help:SetText(definition.description)
            SmallDescription(help)
            entries[#entries + 1] = { widget = row, help = help, topHeight = 74, x = 8, key = definition.cvar or definition.key }
            controls[#controls + 1] = row
        elseif definition.numeric then
            local row = CreateFrame("Frame", nil, list)
            row:SetSize(410, 1)
            row.definition = definition
            row.dirty = false
            local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            label:SetPoint("TOPLEFT")
            label:SetText(definition.label)
            row.input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.input:SetSize(140, 24)
            row.input:SetPoint("TOPLEFT", 6, -20)
            row.input:SetAutoFocus(false)
            row.input:SetNumeric(true)
            row.input:SetMaxLetters(10)
            row.input:SetScript("OnTextChanged", function(_, userInput)
                if userInput then row.dirty = true end
            end)
            row.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            row.apply = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.apply:SetSize(72, 24)
            row.apply:SetPoint("LEFT", row.input, "RIGHT", 14, 0)
            row.apply:SetText("应用")
            row.apply:SetScript("OnClick", function() Apply(row) end)
            row.status = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            row.status:SetPoint("LEFT", row.apply, "RIGHT", 10, 0)
            row.status:SetWidth(166)
            row.status:SetJustifyH("LEFT")
            local help = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            help:SetPoint("TOPLEFT", row.input, "BOTTOMLEFT", -6, -5)
            help:SetWidth(398)
            help:SetJustifyH("LEFT")
            help:SetText(definition.description)
            SmallDescription(help)
            entries[#entries + 1] = { widget = row, help = help, topHeight = 49, x = 8, key = definition.cvar or definition.key }
            controls[#controls + 1] = row
        else
        local check = CreateFrame("CheckButton", nil, list, "UICheckButtonTemplate")
        check:SetSize(28, 28)
        check.definition = definition
        local label = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        label:SetText(definition.label)
        local description = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        description:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, 0)
        description:SetWidth(350)
        description:SetJustifyH("LEFT")
        description:SetText(definition.description)
        SmallDescription(description)
        check.status = check:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        check.status:SetPoint("LEFT", label, "RIGHT", 10, 0)
        check:SetScript("OnClick", Apply)
        entries[#entries + 1] = { widget = check, help = description, topHeight = 28, x = 4, key = definition.cvar or definition.key }
        controls[#controls + 1] = check
        end
        end
    end
    end
    SelectTab(1)
    parent:SetScript("OnShow", function()
        for _, layout in ipairs(layouts) do layout() end
        Refresh(true)
    end)
end

local window = CreateFrame("Frame", "InnerGraphicConfigWindow", UIParent, "BasicFrameTemplateWithInset")
window:SetSize(500, 560)
window:SetPoint("CENTER")
window:SetFrameStrata("DIALOG")
window:SetClampedToScreen(true)
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", function(self) self:StartMoving() end)
window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
window.TitleText:SetText("wow_tools - inner_graphic_config")
window:Hide()
local content = CreateFrame("Frame", nil, window)
content:SetPoint("TOPLEFT", 0, -16)
content:SetPoint("BOTTOMRIGHT")
BuildControls(content)
window:SetScript("OnShow", function() Refresh(true) end)
UISpecialFrames[#UISpecialFrames + 1] = "InnerGraphicConfigWindow"

SLASH_INNERGRAPHICCONFIG1 = "/igc"
SLASH_INNERGRAPHICCONFIG2 = "/inner_graphic_config"
SlashCmdList.INNERGRAPHICCONFIG = function()
    if window:IsShown() then window:Hide() else window:Show() end
end

local panel = CreateFrame("Frame", nil, UIParent)
panel.name = "wow_tools - inner_graphic_config"
panel:Hide()
BuildControls(panel)
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

local events = CreateFrame("Frame")
events:RegisterEvent("CVAR_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function() Refresh() end)
-- Some classic CVars do not emit CVAR_UPDATE. Poll only while a UI is visible.
local elapsedTime = 0
events:SetScript("OnUpdate", function(_, elapsed)
    if not window:IsShown() and not panel:IsShown() then
        elapsedTime = 0
        return
    end
    elapsedTime = elapsedTime + elapsed
    if elapsedTime >= 0.5 then
        elapsedTime = 0
        Refresh()
    end
end)

WoWTools.modules.inner_graphic_config = {
    Toggle = SlashCmdList.INNERGRAPHICCONFIG,
    Show = function() window:Show() end,
    IsShown = function() return window:IsShown() end,
}
