WoWTools.raynnaBestiary.RegisterSource(function(...)
-- Shared resize-cursor and scrollbar widgets, plus integer display formatting.

local _, Addon = ...
local cursorOwner, resizeIndicator
local cursorTextureFolder = 'Interface\\AddOns\\wow_tools\\raynna_bestiary\\Media\\'

-- Resize pointer presentation
function Addon.ShowResizeCursor(handle, direction)
    if not SetCursorByMode or not Enum or not Enum.Cursormode then
        return
    end
    if not resizeIndicator then
        resizeIndicator = CreateFrame('Frame', 'RaynnaResizeIndicator', UIParent)
        resizeIndicator:SetFrameStrata('TOOLTIP')
        resizeIndicator:SetFrameLevel(1000)
        resizeIndicator:EnableMouse(false)
        resizeIndicator.icon = resizeIndicator:CreateTexture(nil, 'OVERLAY')
        resizeIndicator.icon:SetAllPoints()
        resizeIndicator:SetScript('OnUpdate', function(self)
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            self:SetSize(18 / scale, 18 / scale)
            SetCursorByMode(Enum.Cursormode.NoCursor)
            self:ClearAllPoints()
            self:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x / scale, y / scale)
        end)
    end
    cursorOwner = handle
    local shape = (direction == 'LEFT' or direction == 'RIGHT') and 'Horizontal'
        or (direction == 'TOP' or direction == 'BOTTOM') and 'Vertical'
        or (direction == 'TOPLEFT' or direction == 'BOTTOMRIGHT') and 'DiagonalDown'
        or 'DiagonalUp'
    resizeIndicator.icon:SetTexture(cursorTextureFolder .. shape .. '.tga')
    resizeIndicator:GetScript('OnUpdate')(resizeIndicator)
    resizeIndicator:Show()
end
function Addon.HideResizeCursor(handle)
    if cursorOwner ~= handle then
        return
    end
    cursorOwner = nil
    if resizeIndicator then
        resizeIndicator:Hide()
    end
    ResetCursor()
end

-- Number formatting
function Addon.Number(value)
    local n = tostring(math.floor(value or 0))
    local result = n:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return result:gsub('^,', '')
end

-- Reusable scrollbar construction
function Addon.Scrollbar(parent, changed)
    local scrollbar = CreateFrame('Frame', nil, parent)
    scrollbar:SetWidth(12)
    scrollbar:EnableMouse(true)
    scrollbar:EnableMouseWheel(true)
    local track = scrollbar:CreateTexture(nil, 'BACKGROUND')
    track:SetPoint('TOP')
    track:SetPoint('BOTTOM')
    track:SetWidth(3)
    track:SetColorTexture(0.28, 0.2, 0.08, 0.8)
    local thumb = CreateFrame('Frame', nil, scrollbar)
    scrollbar.thumb = thumb
    thumb:SetWidth(6)
    thumb:EnableMouse(true)
    local fill = thumb:CreateTexture(nil, 'ARTWORK')
    fill:SetAllPoints()
    fill:SetColorTexture(0.7, 0.51, 0.18, 0.95)
    thumb:SetScript('OnEnter', function()
        fill:SetColorTexture(1, 0.82, 0.25, 1)
    end)
    thumb:SetScript('OnLeave', function()
        fill:SetColorTexture(0.7, 0.51, 0.18, 0.95)
    end)
    function scrollbar:Update(total, page, offset, height)
        self.maximum = math.max(0, total - page)
        self.offset = offset
        self:SetHeight(height)
        self.thumbHeight = math.min(height, math.max(18, height * page / math.max(1, total)))
        thumb:SetHeight(self.thumbHeight)
        thumb:ClearAllPoints()
        thumb:SetPoint(
            'TOP',
            self,
            'TOP',
            0,
            -((height - self.thumbHeight) * offset / math.max(1, self.maximum))
        )
        self:SetShown(self.maximum > 0)
    end
    local function setScrollOffset(value)
        changed(math.max(0, math.min(scrollbar.maximum or 0, math.floor(value + 0.5))))
    end
    local function finishDragging()
        scrollbar.dragging = false
        thumb:SetScript('OnUpdate', nil)
    end
    thumb:SetScript('OnMouseDown', function(_, button)
        if button ~= 'LeftButton' then
            return
        end
        local _, startY = GetCursorPosition()
        local startOffset = scrollbar.offset
        scrollbar.dragging = true
        thumb:SetScript('OnUpdate', function()
            local _, y = GetCursorPosition()
            local travel = math.max(1, scrollbar:GetHeight() - scrollbar.thumbHeight)
            setScrollOffset(
                startOffset + (startY - y) / scrollbar:GetEffectiveScale() / travel * scrollbar.maximum
            )
            if not IsMouseButtonDown('LeftButton') then
                finishDragging()
            end
        end)
    end)
    thumb:SetScript('OnMouseUp', finishDragging)
    scrollbar:SetScript('OnHide', finishDragging)
    scrollbar:SetScript('OnMouseDown', function(_, button)
        if button ~= 'LeftButton' then
            return
        end
        local _, y = GetCursorPosition()
        local position = scrollbar:GetTop() - y / scrollbar:GetEffectiveScale() - scrollbar.thumbHeight / 2
        setScrollOffset(
            position / math.max(1, scrollbar:GetHeight() - scrollbar.thumbHeight) * scrollbar.maximum
        )
    end)
    scrollbar:SetScript('OnMouseWheel', function(_, delta)
        setScrollOffset(scrollbar.offset - delta)
    end)
    return scrollbar
end
end)
