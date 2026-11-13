local root = TEST_ROOT or "."
local flavor = TEST_FLAVOR or "forerver"
wowDetectorDB={lsToasts={db={profiles={Default={version=16001,font={size=17},
    anchors={{scale=1.2,point={p="BOTTOMRIGHT",rP="BOTTOMRIGHT",x=-100,y=200}}},
    types={loot_items={enabled=false,anchor=1,filters={[100]=true}}},
}}}}}
local chat = dofile(root.."/addon/tests/ForeverCompatibility.Tests.lua")
local mock = chat.toasts
local addon = WoWTools.lsToasts
local E, P, C = addon.E, addon.P, addon.C
local options = C.options.args.types.args
assert(addon.sourceVersion == "120105.05")
assert(addon.sourceCommit == "355774b11757b46ed3bb4c784ad7145f03e43871")
assert(addon.GAMEVERSION.TitanReforged == (flavor == "titan"))
assert(addon.GAMEVERSION.Forever == (flavor == "forerver"))
assert(_G.ls_Toasts[1] == E and C.db.raw == wowDetectorDB.lsToasts.db)
for _, system in ipairs({"achievement", "collection", "loot_currency", "loot_gold", "loot_item", "recipe", "store", "transmog"}) do
    assert(options[system], "Missing upstream system "..system)
end
assert(P:GetSkin("azerite") and P:GetSkin("default") and P:GetSkin("beautycase") and P:GetSkin("elv"))
assert(C.options.args.layouts and C.options.args.profiles and C.options.args.anchors)
assert(options.loot_item.args.vfx and options.loot_item.args.tooltip)
assert(C.db.profile.font.size==17 and C.db.profile.layouts.Modern.anchors[1].scale==1.2)
assert(C.db.profile.types.loot_item.enabled==false and C.db.profile.types.loot_item.filters[100])
assert(not C.db.profile.types.loot_items, "Legacy item settings were not migrated at the normal load entry")

-- The upstream migration retains the old anchor layout and item settings.
local legacy = {
    version = 1130202,
    font = {size = 17},
    anchors = {{scale = 1.2, point = {p = "BOTTOMRIGHT", rP = "BOTTOMRIGHT", x = -100, y = 200}}},
    types = {loot_item = {anchor = 1, enabled = false, filters = {[100] = true}}},
}
P:Modernize(legacy, "Existing", "profile")
assert(legacy.layouts.Modern.anchors[1].point.point == "BOTTOMRIGHT")
assert(legacy.layouts.Modern.anchors[1].point.x == -100)
assert(legacy.layouts.Modern.types.loot_item == 1 and legacy.types.loot_item.enabled == false)
assert(legacy.font.size == 17 and legacy.types.loot_item.filters[100])

P:FlushQueue()
local toast = E:GetToast("UPSTREAM_TEST")
toast._data.vfx = true
toast:Spawn(1, false)
assert(toast.AnimInFull:IsPlaying() and toast.AnimOut:IsPlaying())
assert(not toast.FadeIn and not toast.RestartFadeOut, "A previous local animation patch survived")
toast.scripts.OnEnter(toast)
assert(not toast.AnimOut:IsPlaying())
toast.scripts.OnLeave(toast)
assert(toast.AnimOut:IsPlaying())
toast:Release()
local reduced = E:GetToast("UPSTREAM_TEST")
reduced._data.vfx = false
reduced:Spawn(1, false)
assert(reduced.AnimInReduced:IsPlaying() and reduced.AnimInReduced.Anim1.duration == 0.15)
reduced:Release()

-- Drive the actual upstream loot handlers through their registered events.
mock.itemInfo[990001] = {name="模拟材料",quality=1,classID=7,subClassID=5}
mock.itemInfo[990002] = {name="旧分类",quality=1,classID=7,subClassID=0}
mock.itemInfo[990003] = {name="屏蔽材料",quality=1,classID=7,subClassID=5}
local item = C.db.profile.types.loot_item
item.enabled, item.material, item.threshold = true, true, 3
item.filters[990001], item.filters[990002], item.filters[990003] = nil, nil, false
P:DisableAllSystems()
P:EnableAllSystems()
mock.Fire("CHAT_MSG_LOOT", "你获得了物品：|Hitem:990001|h[模拟材料]|h。")
local received = P:GetActiveToasts(1)[1]
assert(received and received._data.item_id == 990001 and received._data.count == 1)
mock.Fire("CHAT_MSG_LOOT", "你获得了物品：|Hitem:990001|h[模拟材料]|hx2。")
assert(received._data.count == 3)
mock.Fire("CHAT_MSG_LOOT", "你获得了物品：|Hitem:990002|h[旧分类]|h。")
mock.Fire("CHAT_MSG_LOOT", "你获得了物品：|Hitem:990003|h[屏蔽材料]|h。")
assert(#P:GetActiveToasts(1) == 1, "Material classification or explicit block filter changed")
for _, frame in ipairs(mock.frames) do
    if frame.events.CHAT_MSG_LOOT then
        assert(not frame.events.BAG_UPDATE, "A previous local bag-scan patch survived")
    end
end
P:FlushQueue()
assert(#P:GetActiveToasts(1) == 0)
mock.money=mock.money+100
mock.Fire("PLAYER_MONEY")
assert(P:GetActiveToasts(1)[1]._data.count==100)
P:FlushQueue()
FormatLargeNumber=tostring
C_CurrencyInfo.GetCurrencyInfoFromLink=function() return {name="模拟货币",quality=1,iconFileID=123} end
mock.Fire("CURRENCY_DISPLAY_UPDATE",3402,nil,4)
assert(P:GetActiveToasts(1)[1]._data.link=="currency:3402")
assert(P:GetActiveToasts(1)[1]._data.count==4)
P:FlushQueue()

-- Preserve the upstream import/export namespace through the host entry point.
local serialized = {}
C_EncodingUtil = {
    SerializeCBOR = function(value)
        serialized[#serialized + 1] = addon:CopyTable(value)
        return "payload"..#serialized
    end,
    DeserializeCBOR = function(value)
        return addon:CopyTable(serialized[tonumber(value:match("%d+"))])
    end,
    CompressString = function(value) return value end,
    DecompressString = function(value) return value end,
    EncodeBase64 = function(value) return value end,
    DecodeBase64 = function(value) return value end,
}
C.db.profiles = C.db.raw.profiles
C.db.profile.font.size = 17
local exported = addon:Export("profile")
assert(exported:match("^lstoasts:profile:12010505:"))
local imported, profile = addon:Import(exported, true, "Imported")
assert(imported and profile.font.size == 17 and C.db.profiles.Imported == profile)
assert(addon:ParseImportString("invalid") == nil)
print("PASS: "..flavor.." latest upstream identity, host entry, systems/skins/layouts, legacy migration, original animations, chat loot/material/block filters and profile import/export. Offline APIs only.")
