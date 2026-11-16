WoWTools.prr.RegisterSource(function(...)
-- scroll_area.lua -- a scrolling area with the game's scroll bar: put frames
-- into area.content, then tell the area how tall they are.

local ADDON, ns = ...
ns.UI = ns.UI or {}

-- the modern scroll frame (MinimalScrollBar, as in the game settings), then the old one
local SCROLL_TEMPLATES = { "ScrollFrameTemplate", "UIPanelScrollFrameTemplate" }

-- the scroll bar sits right of the area: leave this much space for it
ns.UI.SCROLL_AREA_BAR_SPACE = 24

local function CreateScrollFrame(parent)
    for _, template in ipairs(SCROLL_TEMPLATES) do
        local ok, scrollFrame = pcall(CreateFrame, "ScrollFrame", nil, parent, template)
        if ok and scrollFrame then
            return scrollFrame
        end
    end
    return CreateFrame("ScrollFrame", nil, parent)
end

-- area.content -- the frame to fill, as wide as the area;
-- area:SetContentHeight(height, keepPosition) -- after filling it.
function ns.UI.ScrollArea(parent)
    local area = CreateScrollFrame(parent)
    local content = CreateFrame("Frame", nil, area)
    content:SetSize(1, 1)
    area:SetScrollChild(content)
    area.content = content

    area:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
    end)

    -- keepPosition -- the same content redrawn: do not jump to the top
    function area:SetContentHeight(height, keepPosition)
        content:SetWidth(self:GetWidth())
        content:SetHeight(math.max(height, 1))
        if not keepPosition then
            self:SetVerticalScroll(0)
        end
    end

    return area
end
end)
