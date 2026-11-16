WoWTools.prr.RegisterSource(function(...)
-- list_header.lua -- a collapsible header like the zone headers of the quest
-- log: a dark bar with a bronze edge, the title on the left, plus/minus on the
-- right. Made from the same templates as QuestLogHeaderTemplate
-- (Blizzard_SharedXML/ListTemplates.xml): ListHeaderVisualTemplate draws it,
-- ListHeaderCodeTemplate makes it react to the mouse.

local ADDON, ns = ...
ns.UI = ns.UI or {}

local TEMPLATES = "ListHeaderVisualTemplate, ListHeaderCodeTemplate"
local FALLBACK_HEIGHT_PADDING = 4
local FALLBACK_BACKGROUND = { 0.2, 0.15, 0.08, 0.9 }

-- On a client without the templates: a plain bar with "+" / "-" on the right.
local function FallbackHeader(parent)
    local header = CreateFrame("Button", nil, parent)
    local background = header:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(FALLBACK_BACKGROUND[1], FALLBACK_BACKGROUND[2],
        FALLBACK_BACKGROUND[3], FALLBACK_BACKGROUND[4])

    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.title:SetPoint("LEFT", 8, 0)
    header.title:SetPoint("RIGHT", -24, 0)
    header.title:SetJustifyH("LEFT")
    header.sign = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header.sign:SetPoint("RIGHT", -8, FALLBACK_HEIGHT_PADDING / 2)

    function header:SetTitle(text)
        self.title:SetText(text)
    end

    function header:SetCollapsed(collapsed)
        if collapsed then
            self.sign:SetText("+")
        else
            self.sign:SetText("-")
        end
    end

    function header:SetOnClick(handler)
        self:SetScript("OnClick", handler)
    end

    return header
end

-- options: height. header:SetTitle(text), header:SetCollapsed(collapsed),
-- header:SetOnClick(handler(header)).
function ns.UI.ListHeader(parent, options)
    local ok, header = pcall(CreateFrame, "Button", nil, parent, TEMPLATES)
    local isTemplated = ok and header and header.SetHeaderText and header.UpdateCollapsedState
    if not isTemplated then
        header = FallbackHeader(parent)
        header:SetHeight(options.height)
        return header
    end

    header:SetHeight(options.height)
    header:RegisterForClicks("LeftButtonUp")

    function header:SetTitle(text)
        self:SetHeaderText(text)
    end

    function header:SetCollapsed(collapsed)
        self:UpdateCollapsedState(collapsed)
    end

    function header:SetOnClick(handler)
        -- a click on the plus/minus reaches the header by itself
        -- (propagateMouseInput="Both" in CollapseButtonTemplate)
        self:SetClickHandler(function(clicked)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            handler(clicked)
        end)
    end

    return header
end
end)
