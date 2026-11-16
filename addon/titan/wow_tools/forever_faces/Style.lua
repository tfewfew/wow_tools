local ns = WoWTools.foreverFaces
local style = { frames = {} }
ns.style = style

-- OffScreenFrame is documented by both clients. Capturing a model and the
-- sampler retained by ApplySnapshot remain experimental, with visible status.
style.options = {
    { key="scope", label="调试范围", default="player", choices={{"player", "仅玩家头像"}, {"all", "全部已启用的头像"}} },
    { key="source", label="模型来源", default="unit", choices={{"unit", "当前单位"}, {"display", "指定 DisplayID"}, {"file", "指定模型 FileID"}}, help="指定模型会替换调试范围内的头像外观。低模需要填写客户端已有的对应模型 ID。" },
    { key="displayID", label="DisplayID", default=0, minimum=0, maximum=2147483647, help="选择指定 DisplayID 时使用，大于 0。页面底部可查看当前模型 ID。" },
    { key="fileID", label="模型 FileID", default=0, minimum=0, maximum=2147483647, help="选择指定模型 FileID 时使用，大于 0。模型文件的镜头适配效果需要游戏内观察。" },
    { key="noMip", label="文件模型禁用 MipMap", default=false, help="只作用于指定模型 FileID，传入 SetModel 的 noMip 参数。" },
    { key="animation", label="动画", default="default", choices={{"default", "沿用头像动画"}, {"idle", "独立待机"}, {"paused", "暂停动画"}} },
    { key="pixelEnabled", label="启用像素化快照（实验）", default=false },
    { key="resolution", label="采样边长（物理像素）", default=32, minimum=8, maximum=128, help="范围 8–128，默认 32。较小值用于观察更粗的像素块，实际快照分辨率由客户端生成。" },
    { key="fps", label="快照更新帧率", default=10, minimum=1, maximum=30, help="范围 1–30，默认每秒 10 次。仅在像素化头像可见时更新。" },
    { key="filter", label="纹理采样请求", default="NEAREST", choices={{"NEAREST", "最近邻"}, {"LINEAR", "线性"}}, help="应用快照前设置纹理采样。客户端是否保留该采样方式，需要对照观察边缘效果。" },
}

function style.Config()
    local db = ns.DB()
    if type(db.style) ~= "table" then db.style = {} end
    local config = db.style
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

function style.Load(model, unit)
    local config = style.Config()
    local applies = style.Applies(unit)
    local source = applies and config.source or "unit"
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

local function Stop(entry)
    local capture = entry.capture
    if not capture then return end
    capture.frame:SetScript("OnUpdate", nil)
    capture.frame:Hide()
    capture.output:Hide()
    capture.active = false
    style.frames[entry] = nil
end

function style.Restore(entry)
    Stop(entry)
    if entry.model and entry.model:GetParent() ~= entry.host then
        entry.model:SetParent(entry.host)
    end
end

function style.Hide(entry)
    Stop(entry)
end

local function Failure(entry, message)
    entry.captureError = tostring(message)
    if InCombatLockdown() then
        ns.FlatPortrait(entry.texture)
        ns.DeferPortrait(entry)
        return
    end
    style.Restore(entry)
    ns.LayoutPortrait(entry.texture, entry)
    entry.model:SetAlpha(1)
end

local function Capture(entry, elapsed)
    local capture = entry.capture
    capture.elapsed = capture.elapsed + elapsed
    if capture.elapsed < 1 / style.Config().fps then return end
    capture.elapsed = 0
    if not entry.shown or not entry.texture:IsVisible() then Stop(entry); return end
    local ok, snapshot = pcall(capture.frame.TakeSnapshot, capture.frame)
    if not ok then Failure(entry, snapshot); return end
    if not snapshot then
        capture.misses = capture.misses + 1
        if capture.misses >= 5 then Failure(entry, "快照连续返回空值，点击重建后重试") end
        return
    end
    local applied, success = pcall(capture.frame.ApplySnapshot, capture.frame, capture.texture, snapshot)
    if not applied or not success then Failure(entry, applied and "快照应用失败" or success); return end
    capture.misses = 0
    capture.samples = capture.samples + 1
    capture.snapshot = snapshot
    capture.output:Show()
end

local function BuildCapture(entry)
    local ok, frame = pcall(CreateFrame, "OffScreenFrame", nil, UIParent)
    if not ok then entry.captureError = tostring(frame); return end
    if not (frame.TakeSnapshot and frame.ApplySnapshot and frame.SetMaxSnapshots) then
        frame:Hide()
        entry.captureError = "此客户端未提供完整的 OffScreenFrame 接口"
        return
    end
    frame:Hide()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
    frame:SetMaxSnapshots(1)
    local output = CreateFrame("Frame", nil, entry.host)
    output:Hide()
    local texture = output:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    entry.capture = { frame=frame, output=output, texture=texture, samples=0, misses=0, elapsed=0 }
end

local function Show(entry)
    local config = style.Config()
    if not config.pixelEnabled or not style.Applies(entry.unit) or entry.captureError then return end
    if entry.capture and entry.capture.active then return end
    if InCombatLockdown() and (not entry.capture or entry.model:GetParent() ~= entry.capture.frame) then
        entry.captureDeferred = true
        ns.DeferPortrait(entry)
        return
    end
    if not entry.capture then BuildCapture(entry) end
    local capture = entry.capture
    if not capture then return end
    local scale = UIParent:GetEffectiveScale()
    capture.frame:SetScale(1 / scale)
    capture.frame:SetSize(config.resolution, config.resolution)
    capture.output:SetFrameStrata(entry.model:GetFrameStrata())
    capture.output:SetFrameLevel(entry.model:GetFrameLevel())
    if entry.model:GetParent() == entry.host then
        capture.output:ClearAllPoints()
        capture.output:SetPoint("CENTER", entry.texture, "CENTER")
        capture.output:SetSize(entry.model:GetWidth(), entry.model:GetHeight())
    end
    -- SetTexture selects the requested sampler before the snapshot binds its
    -- image. The debug page makes retention of this sampler an explicit test.
    capture.texture:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMP", "CLAMP", config.filter)
    capture.output:Hide()
    capture.active = true
    style.frames[entry] = true
    entry.model:SetParent(capture.frame)
    entry.model:ClearAllPoints()
    entry.model:SetAllPoints(capture.frame)
    entry.model:SetFrameLevel(capture.frame:GetFrameLevel() + 1)
    capture.frame:Show()
    capture.elapsed, capture.misses = 0, 0
    entry.captureDeferred = nil
    capture.frame:SetScript("OnUpdate", function(_, elapsed) Capture(entry, elapsed) end)
end

function style.Show(entry)
    local ok, message = pcall(Show, entry)
    if not ok then Failure(entry, message) end
end

function style.Prepare(entry)
    -- Reconfiguration always starts from the normal model geometry.
    style.Restore(entry)
    entry.captureError = nil
    entry.captureDeferred = nil
end

function style.Status()
    local active, samples = 0, 0
    for entry in pairs(style.frames) do
        active = active + 1
        samples = samples + entry.capture.samples
    end
    return string.format("快照运行 %d 个头像，累计 %d 帧。\n采样方式为客户端请求值，实际像素边缘和模型捕获效果请在游戏内观察。", active, samples)
end
