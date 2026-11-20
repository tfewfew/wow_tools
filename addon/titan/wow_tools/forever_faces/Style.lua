local ns = WoWTools.foreverFaces
local style = {}
ns.style = style

-- The previous snapshot implementation triggered a protected-action denial
-- in game. Retain its settings for compatibility and expose its unavailable state.
style.pixelUnavailableReason = "像素化快照当前不可用。离屏快照调用已触发客户端受保护操作，当前实现已撤下。"
style.options = {
    { key="scope", label="调试范围", default="player", choices={{"player", "仅玩家头像"}, {"all", "全部已启用的头像"}}, help="选择哪些头像使用本页的模型与像素化参数。默认只应用于玩家头像。" },
    { key="source", label="模型来源", default="unit", choices={{"unit", "当前单位"}, {"display", "指定 DisplayID"}, {"file", "指定模型 FileID"}}, help="指定模型会替换调试范围内的头像外观。低模需要填写客户端已有的对应模型 ID。" },
    { key="displayID", label="DisplayID", default=0, minimum=0, maximum=2147483647, help="选择指定 DisplayID 时使用，大于 0。页面底部可查看当前模型 ID。" },
    { key="fileID", label="模型 FileID", default=0, minimum=0, maximum=2147483647, help="选择指定模型 FileID 时使用，大于 0。模型文件的镜头适配效果需要游戏内观察。" },
    { key="noMip", label="文件模型禁用 MipMap", default=false, help="只作用于指定模型 FileID，传入 SetModel 的 noMip 参数。" },
    { key="animation", label="动画", default="default", choices={{"default", "沿用头像动画"}, {"idle", "独立待机"}, {"paused", "暂停动画"}}, help="选择头像模型的默认动画、独立待机或暂停动画。" },
    { key="pixelEnabled", label="像素化快照（当前不可用）", default=false, unavailable=true, help="此调用路径已因客户端受保护操作而撤下。" },
    { key="resolution", label="采样边长（物理像素）", default=32, minimum=8, maximum=128, unavailable=true, help="原采样参数已保留，等待可用的像素化实现。" },
    { key="fps", label="快照更新帧率", default=10, minimum=1, maximum=30, unavailable=true, help="原帧率参数已保留，等待可用的像素化实现。" },
    { key="filter", label="纹理采样请求", default="NEAREST", unavailable=true, choices={{"NEAREST", "最近邻"}, {"LINEAR", "线性"}}, help="原采样方式已保留，等待可用的像素化实现。" },
}

function style.Config()
    local db = ns.DB()
    if type(db.style) ~= "table" then db.style = {} end
    local config = db.style
    config.pixelEnabled = false
    if style.validated == config then return config end
    for _, option in ipairs(style.options) do
        local value = config[option.key]
        if option.choices then
            local valid = false
            for _, choice in ipairs(option.choices) do
                if value == choice[1] then valid = true end
            end
            if not valid then value = option.default end
        elseif option.minimum then
            value = tonumber(value)
            if not value or value ~= value or value == math.huge or value == -math.huge then value = option.default end
            value = math.max(option.minimum, math.min(option.maximum, math.floor(value)))
        elseif type(value) ~= "boolean" then
            value = option.default
        end
        config[option.key] = value
    end
    style.validated = config
    return config
end

function ns.SetStyle(key, value)
    local config = style.Config()
    if key == "pixelEnabled" and value then return false, style.pixelUnavailableReason end
    if config[key] == value then return end
    local nextConfig = {}
    for name, current in pairs(config) do nextConfig[name] = current end
    nextConfig[key] = value
    ns.Set("style", nextConfig)
end

function style.Applies(unit)
    return style.Config().scope == "all" or unit == "player"
end

function style.ModelKey(unit)
    if not style.Applies(unit) then return "unit" end
    local config = style.Config()
    return table.concat({config.source, config.displayID, config.fileID, tostring(config.noMip), config.animation}, "/")
end

function style.Source(unit)
    return style.Applies(unit) and style.Config().source or "unit"
end

function style.Load(model, unit)
    local config = style.Config()
    local applies = style.Applies(unit)
    local source = style.Source(unit)
    local ok, result
    if source == "display" then
        if config.displayID == 0 then return false, "请填写大于 0 的 DisplayID" end
        ok, result = pcall(model.SetDisplayInfo, model, config.displayID)
    elseif source == "file" then
        if config.fileID == 0 then return false, "请填写大于 0 的模型 FileID" end
        ok, result = pcall(model.SetModel, model, config.fileID, config.noMip)
    else
        ok, result = pcall(model.SetUnit, model, unit, false)
    end
    if model.SetPaused then model:SetPaused(applies and config.animation == "paused") end
    if applies and config.animation == "idle" and model.SetAnimation then model:SetAnimation(0) end
    return ok, result
end

function style.Animate(entry)
    local config = style.Config()
    if style.Applies(entry.unit) and config.animation == "idle" then entry.model:SetAnimation(0) end
    if entry.model.SetPaused then
        entry.model:SetPaused(style.Applies(entry.unit) and config.animation == "paused")
    end
end


function style.Status()
    return style.pixelUnavailableReason
end
