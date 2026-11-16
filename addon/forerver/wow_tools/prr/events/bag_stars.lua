WoWTools.prr.RegisterSource(function(...)
-- bag_stars.lua -- item buttons getting their item: put the favorite star on
-- them (components/bag_stars.lua).
--
-- * SetItemButtonTexture -- the global function BagBrother / Bagnon (bags and
--   bank) and many addons call for every item button;
-- * the game's own bags draw their buttons in ContainerFrame:UpdateItems
--   (through a method of the button, not the global function).

local ADDON, ns = ...

local BagStars = ns.Components.BagStars

if SetItemButtonTexture then
    hooksecurefunc("SetItemButtonTexture", function(button)
        BagStars.Decorate(button)
    end)
end

local function HookContainer(container)
    if not (container and container.UpdateItems and container.EnumerateValidItems) then return end
    hooksecurefunc(container, "UpdateItems", function(self)
        for _, button in self:EnumerateValidItems() do
            BagStars.Decorate(button)
        end
    end)
end

ns.Events.On("PLAYER_LOGIN", function()
    local containers = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    for _, container in ipairs(containers or {}) do
        HookContainer(container)
    end
    HookContainer(ContainerFrameCombinedBags)
end)
end)
