local root = TEST_ROOT or "."
local flavor = TEST_FLAVOR or "forerver"
local directory = root .. "/addon/" .. flavor .. "/wow_tools/ls_toasts/"
local addon = {C = {}, D = {}, L = {}}
local frame = {}
local expectedLink = "item:123:0:0:0:0:0:456:0:60:0:0:0:0:0:0"
local otherLink = "item:123:0:0:0:0:0:789:0:60:0:0:0:0:0:0"
local targetBag = flavor == "forerver" and 5 or 4
local bagCalls, linkCalls, anchorCalls, comparisonCalls = 0, 0, 0, 0
local hasItem = true

NUM_BAG_SLOTS = 4
NUM_TOTAL_EQUIPPED_BAG_SLOTS = flavor == "forerver" and 5 or nil
C_Container = {
    GetContainerNumSlots = function(bag)
        assert(type(bag) == "number" and bag >= 0 and bag <= targetBag)
        return bag == targetBag and 2 or 0
    end,
    GetContainerItemLink = function(bag, slot)
        assert(bag == targetBag and type(slot) == "number")
        return "|cffffffff|H" .. (hasItem and slot == 2 and expectedLink or otherLink) .. "|h[Item]|h|r"
    end,
}
GameTooltip = {
    SetOwner = function(self, owner, anchor)
        assert(self == GameTooltip and owner == frame and anchor == "ANCHOR_NONE")
    end,
    ClearAllPoints = function(self) assert(self == GameTooltip) end,
    SetBagItem = function(self, bag, slot)
        assert(self == GameTooltip and bag == targetBag and slot == 2,
            "Bag tooltip must receive the matching full-link variant and native slot arguments")
        bagCalls = bagCalls + 1
    end,
    SetHyperlink = function(self, link)
        assert(self == GameTooltip and link == expectedLink)
        linkCalls = linkCalls + 1
    end,
    Show = function(self) assert(self == GameTooltip) end,
}
ContainerFrameItemButton_CalculateItemTooltipAnchors = function(owner, tooltip)
    assert(owner == frame and tooltip == GameTooltip)
    anchorCalls = anchorCalls + 1
end
GameTooltip_ShowCompareItem = function(tooltip)
    assert(tooltip == GameTooltip)
    comparisonCalls = comparisonCalls + 1
end
if flavor == "forerver" then
    TooltipUtil = {ShouldDoItemComparison = function(tooltip)
        assert(tooltip == GameTooltip)
        return true
    end}
    IsModifiedClick = function() error("Forever must use its native TooltipUtil comparison interface") end
else
    TooltipUtil = nil
    IsModifiedClick = function(action) assert(action == "COMPAREITEMS"); return false end
    GetCVarBool = function(name) assert(name == "alwaysCompareItems"); return true end
end

assert(loadfile(directory .. "core/components/tooltip.lua"))("wow_tools", addon)
assert(type(addon.Tooltip.ShowLootItem) == "function")
addon.Tooltip:ShowLootItem(frame, expectedLink)
hasItem = false
addon.Tooltip:ShowLootItem(frame, expectedLink)
assert(bagCalls == 1 and linkCalls == 1 and anchorCalls == 2 and comparisonCalls == 2,
    "Loot tooltip bag, hyperlink, anchor or client comparison interface was not bound")
print("PASS: " .. flavor .. " toast item tooltip bag-slot, full-link and native comparison interfaces.")
