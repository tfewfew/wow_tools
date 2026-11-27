WoWTools.raynnaBestiary.RegisterSource(function(...)
local _, Addon = ...
local chinese = {
    ["RAYNNA'S BESTIARY"] = "Raynna 怪物图鉴",
    ["RAYNNA'S BESTIARY / BROWSE"] = "Raynna 怪物图鉴 / 浏览",
    ["BESTIARY / TRACKER MONSTERS"] = "怪物图鉴 / 追踪怪物",
    ["Forever + Classic"] = "无限服与经典旧世参考",
    ["Forever sources + Classic fallback rates\nClassic % unverified for Forever; ? unknown"] = "无限服来源与经典旧世参考掉率\n经典掉率尚待无限服验证，? 为未知",
    ["Click to view item sources"] = "点击查看物品来源",
    ["No matching tracked monsters."] = "未找到匹配的追踪怪物。",
    ["Clear"] = "清除",
    ["Clear search and Tracker filter"] = "清除搜索和追踪筛选",
    ["Show all monsters. Your Tracker history is unchanged."] = "显示全部怪物，并保留追踪历史。",
    ["QuestieDB Forever metadata"] = "QuestieDB 无限服元数据",
    ["cMaNGOS Classic (not verified for Forever)"] = "cMaNGOS 经典旧世参考（尚待无限服验证）",
    ["Raynna's Bestiary"] = "Raynna 怪物图鉴",
    ["Settings save for this character."] = "设置按角色保存。",
    ["Alt-hover monsters"] = "Alt 指向怪物显示掉落",
    ["Alt-hover inventory items"] = "Alt 指向物品显示来源",
    ["Bestiary scale"] = "怪物图鉴缩放",
    ["Open bestiary"] = "打开怪物图鉴",
    ["Bestiary appearance"] = "怪物图鉴外观",
    ["Parchment background texture"] = "羊皮纸背景",
    ["Background opacity"] = "背景不透明度",
    ["Language"] = "语言",
    ["Reload to apply the selected language."] = "重载界面后应用所选语言。",
    ["Chinese NPC and quest names use QuestieDB translations when available. Missing translations keep their original names."] = "NPC 与任务名称优先使用 QuestieDB 的中文数据，缺少译名时显示原名。",
    ["Reload"] = "重载界面",
    ["Pin"] = "固定",
    ["Unpin"] = "取消固定",
    ["Browse"] = "浏览",
    ["Quest: "] = "任务 ",
    ["[Quest]"] = "[任务]",
    ["Quest item"] = "任务物品",
    ["Item sources"] = "物品来源",
    ["Reference databases"] = "参考数据库",
    ["Level "] = "等级 ",
    ["Lv "] = "等级 ",
    ["Forever reference"] = "无限服参考数据",
    ["Classic reference"] = "经典旧世参考数据",
    ["Preview"] = "预览",
    ["Sources: Classic DB / source metadata / Forever records\nCoverage varies; ? = unknown chance"] = "来源含经典旧世、来源元数据及无限服记录\n各库覆盖范围不同，? 表示掉率未知",
    ["Icy Veins Forever / 2026-11-13\nPartial snapshot; * conditional chance"] = "Icy Veins 无限服 / 2026-11-13\n部分数据快照，* 表示有条件掉率",
    ["cMaNGOS Classic 1.12 - not verified for Forever\n* Conditional drop chance"] = "cMaNGOS 经典旧世 1.12 参考数据\n无限服掉率待核实，* 表示有条件掉率",
    ["SOURCES  /  "] = "来源  /  ",
    ["POSSIBLE DROPS  /  "] = "可能掉落  /  ",
    ["Loading drops..."] = "正在加载掉落…",
    ["SKINNING  /  "] = "剥皮  /  ",
    ["No known source in the loaded databases.\nCoverage is incomplete for Forever."] = "已加载数据库中暂无已知来源。\n无限服数据仍有缺项。",
    ["No source data for this creature ID.\nYour personal loot log is not used here."] = "此怪物 ID 暂无来源数据。\n本页展示数据库中的参考掉落。",
    ["Source: "] = "数据来源 ",
    ["cMaNGOS Classic; locations: source metadata"] = "cMaNGOS 经典旧世，位置取自来源元数据",
    [" source - no drop roll"] = "来源",
    ["Quest-only drop: requires eligibility for its quest."] = "任务专属掉落，需要满足对应任务条件。",
    ["This chance depends on additional loot conditions."] = "此掉率取决于额外的掉落条件。",
    ["Starts quest: "] = "起始任务 ",
    ["Related quest: "] = "关联任务 ",
    ["Search NPC name or ID, then press Enter"] = "输入 NPC 名称或 ID，按回车搜索",
    ["Search"] = "搜索",
    ["All"] = "全部",
    ["Tracked"] = "已追踪",
    ["Recent"] = "最近查看",
    ["Target"] = "当前目标",
    [" NPCs / click one to view drops"] = " 个 NPC，点击查看掉落",
    ["No matching NPCs. Try another name or All."] = "未找到匹配 NPC，可更换名称或选择“全部”。",
    ["Target a creature to find it in the browser."] = "请选中一个怪物目标后查询。",
    ["Zone unavailable"] = "区域未知",
    ["Chance unknown"] = "掉率未知",
    [" (conditional)"] = "（有条件）",
    ["Quest"] = "任务",
    ["Vendor"] = "商人",
    ["Vendor sale"] = "商人出售",
    ["Efficient Games Forever vendor observations"] = "Efficient Games 无限服商人实测",
    ["Efficient Games earlier Forever vendor observations"] = "Efficient Games 无限服早期版本商人实测",
    ["DungeonsForeverProf Forever vendor reference"] = "DungeonsForeverProf 无限服商人参考",
    ["Dungeon trash"] = "副本小怪",
    ["Quest supply"] = "接任务时获得",
    ["Given when accepting this quest"] = "接受此任务时获得",
    ["World object"] = "场景物件",
    ["Object "] = "物件 ",
    ["Container"] = "容器",
    ["Forever DungeonJournal / NorgannonDB"] = "无限服 DungeonJournal / NorgannonDB",
    ["Show on map"] = "在地图上查看",
    ["Right-click to show on map"] = "右键在地图上查看",
    ["No recorded coordinates for this source."] = "该来源暂无坐标记录。",
    ["This location has no matching client map."] = "此位置没有匹配的客户端地图。",
    ["Open the map after combat."] = "请在脱战后打开地图。",
    ["Could not open the map. Coordinates: "] = "无法打开地图。坐标：",
    ["Nearest recorded spawn: "] = "最近的已记录刷新点：",
    ["Position unavailable; densest cluster: "] = "无法取得当前位置，显示记录最集中的地点：",
    [" / %d nearby records"] = " / %d 条附近记录",
    [" (pin unavailable)"] = "（无法放置标记）",
    [" (overlay unavailable)"] = "（无法绘制区域）",
    ["Known spawn area"] = "已记录的刷新区域",
    ["%d recorded spawn locations"] = "%d 个已记录的刷新点",
    ["Estimated area, not live monster positions."] = "此区域按刷新记录估算。",
    ["Use Clear below to remove these highlights."] = "点击下方的清除按钮移除高亮。",
    ["Estimated spawn areas | Clear"] = "估算刷新区域 | 清除",
    ["Clear spawn highlights"] = "清除刷新区域高亮",
    ["Remove the blue areas, NPC labels and pulse from this map. Your waypoint is kept."] = "清除蓝色区域、名称和脉冲标记，保留地图导航点。",
    ["Selected source"] = "已选来源",
    ["Skinning"] = "剥皮",
    ["Quest reward / source metadata"] = "任务奖励 / 来源元数据",
    ["Source metadata"] = "来源元数据",
    ["cMaNGOS Classic"] = "cMaNGOS 经典旧世",
    ["Wowhead Forever"] = "Wowhead 无限服",
    ["Icy Veins Forever (2026-11-13)"] = "Icy Veins 无限服（2026-11-13）",
    ["Lv 33 / City of Dalaran / Horde"] = "等级 33 / 达拉然城 / 部落",
    ["Unknown creature"] = "未知怪物",
    ["Creature "] = "怪物 ",
    ["Quest "] = "任务 ",
    ["Vendor "] = "商人 ",
    ["Item "] = "物品 ",
}
local nameCache = { Npc = {}, Quest = {} }

function Addon.InitializeLanguage()
    local language = Addon.db.language
    if language ~= "en" and language ~= "zh" then language = "zh" end
    Addon.db.language = language
    Addon.language = language
end

function Addon.Text(text, ...)
    local value = Addon.language ~= "en" and chinese[text] or text
    value = value or text
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end

local function HasChinese(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    return type(value) == "string" and value:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end

function Addon.EntityName(entity, id, fallback)
    local records = Addon.BundledMetadata and Addon.BundledMetadata[entity]
    local record = records and records[id]
    if Addon.language == "en" then return record and record.name or fallback end
    local cache = nameCache[entity]
    if HasChinese(fallback) then
        if cache and type(id) == "number" then cache[id] = fallback end
        return fallback
    end
    if not cache or type(id) ~= "number" then return fallback end
    if cache[id] == nil then
        cache[id] = false
        local provider = LibQuestieDB and LibQuestieDB[entity]
        if provider and type(provider.Get) == "function" then
            local ok, name = pcall(provider.Get, id, "name")
            if ok and HasChinese(name) then cache[id] = name end
        end
        if not cache[id] and entity == "Quest" and C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, name = pcall(C_QuestLog.GetTitleForQuestID, id)
            if ok and HasChinese(name) then cache[id] = name end
        end
    end
    return cache[id] or fallback
end

end)
