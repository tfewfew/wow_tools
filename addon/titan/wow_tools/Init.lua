WoWTools = { modules = {} }

-- Both detectors publish at the same client-center sampling point.
WoWTools.detectorAnchor = CreateFrame("Frame", nil, UIParent)
WoWTools.detectorAnchor:SetSize(1, 1)
WoWTools.detectorAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

function WoWTools.ActivateDetector(name)
    if WoWTools.MarkCharacterMonitored then WoWTools.MarkCharacterMonitored() end
    for _, other in ipairs({"wowDetector", "fight_detector"}) do
        local module = WoWTools.modules[other]
        if other ~= name and module and (module.IsEnabled() or module.IsShown()) then
            module.Hide()
        end
    end
end
