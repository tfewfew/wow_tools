# 无限服第三方插件维护表

本表为无限服插件来源、版本、适配及更新日期的维护入口。更新日期使用 Asia/Hong_Kong 的本仓库最后一次插件源码或适配修改日期。列表与维护表的排版、元数据整理沿用原日期。大脚组件未提供独立版本号，列表标注采用的官方整合包版本。所有路径相对 `wow_tools/`。

修改表内版本或日期后运行 `skills/wow-tools/scripts/third_party_catalog.py --write`，生成游戏内目录。统一本地检查验证两者一致。

| 模块 | 插件 | 来源 | 当前版本 | 上游基线 | 上次更新 | 本地适配 | 上次核对依据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bigfoot_channel | 大脚聊天 | [大脚官方 forever](https://gitee.com/bigfoot-wow/forever) | 1.60.1.2（整合包） | 6b8e7466470cd2daf4c8c647eb8f97f141caafb6，整包和原文件指纹见 bigfoot_channel/SOURCE.json | 2026-11-16 | BF-01、BF-02、BF-03、BF-04 | 2026-11-17 官方 latest 仍为 1.60.1.2，manifest commit、整包 MD5 和 SHA256 与 SOURCE.json 一致，当前宿主、聊天及运行库适配继续适用 |
| ls_toasts | ls_Toasts | [ls-/ls_Toasts](https://github.com/ls-/ls_Toasts) | 120105.06 | 65bc1fcef7d4de5df471397e7b467385d46f89e6 | 2026-11-17 | LS-01、LS-02、LS-04、LS-05 | 2026-11-17 官方正式版基线一致，核对既有金币勿扰设置及本服背包提示接口，一次性关闭旧金币战斗排队，物品提示接入实时背包格、原生锚点与装备比较 |
| forever_faces | Forever 3D Portraits | [sorrow8/forever-3d-portraits](https://github.com/sorrow8/forever-3d-portraits) | 1.0.11 | 20eaf8fd29b03ba3d91f73a90ccbaf39b49f2af4 | 2026-11-16 | FF-01、FF-02、FF-03、FF-04 | 2026-11-17 官方最新正式版仍为 v1.0.11，tag 解析出的完整 commit 与当前基线一致，宿主、重绘挂接、统一设置和像素调试适配继续适用 |
| better_vendor_ui | Better Vendor UI | [Vaniron 官方发布包](https://www.curseforge.com/wow/addons/better-vendor-ui/files/9436965) | 1.3.1 | 上游未公布 Git commit，发布包 SHA256 和文件指纹见 better_vendor_ui/SOURCE.json | 2026-11-14 | BV-01、BV-02、BV-03 | 2026-11-17 官方文件 API 最新正式包仍为 1.3.1 / 9436965，重新下载包 SHA256 与 SOURCE.json 一致，三项适配继续适用 |
| pet_xp_bar | PetXPBarPlus | [DustinChecketts/PetXPBarPlus](https://github.com/DustinChecketts/PetXPBarPlus) | 1.3.1 | 0c5da2aef6b2b56e307a77e37151fe4675be6c82 | 2026-11-16 | PX-01、PX-02 | 2026-11-17 官方最新正式版仍为 v1.3.1，tag 解析出的完整 commit 与当前基线一致，宿主与本服接口适配继续适用 |
| raynna_bestiary | Raynna's Bestiary | [raynna/raynnabestiary](https://github.com/raynna/raynnabestiary) | 1.1.3 | 上游未公布该版本 Git commit，官方文件 9638877 的发布包 SHA256 及文件指纹见 raynna_bestiary/SOURCE.json | 2026-11-17 | RB-01、RB-02、RB-03、RB-05 | 2026-11-17 官方最新正式包仍为 1.1.3 / 9638877，重新下载包 SHA256 与 SOURCE.json 一致，沿用本日 RB-04 回退后的来源窗口及剥皮数据适配 |
| prr | PRR | [izicawow 官方发布包](https://www.curseforge.com/wow/addons/prr/files/9629892) | 1.5.2 | 上游未公布 Git commit，发布包 SHA256 与文件指纹见 prr/SOURCE.json | 2026-11-17 | PR-01、PR-02、PR-03、PR-05、PR-06、PR-07 | 2026-11-17 官方最新正式包仍为 1.5.2 / 9629892，重新下载包 SHA256 与 SOURCE.json 一致，继续保留已学标记、LibProfessionDB 等级修正及 Efficient Games 训练师数据，指纹见 prr/RECIPE-SOURCES.json |

## 当前本地适配

- BF-01 保留收编宿主接入。`bigfoot_channel/Bootstrap.lua`、`core.lua`、`frame.xml` 将命名空间、媒体、加载事件及 Ace 设置接入 wow_tools，账号配置为 `wowDetectorDB.bigfootChannel`。插件开关在加载时控制初始化，旧命令进入统一设置。当前安装基线仍需这些接入。
- BF-02 保留频道及原配置接入。`ChannelFilter.lua`、`WorldChannel.lua`、`Copy.lua` 使用宿主设置，部署脚本直接迁移 BigFootChat 与 ChannelFilter 配置，验证后归档原独立目录和无限服 !!!Libs，复用宿主内嵌 Ace3。依据为 4502573、34e091f、a98c774。
- LS-01 保留宿主隔离。`ls_toasts/Bootstrap.lua`、`Integration.lua` 及 XML 使用独立命名空间、内嵌媒体、宿主 Ace3、SharedMedia、LibEditMode 及统一设置，保存到 `wowDetectorDB.lsToasts.db`，停用时跳过业务初始化。直接迁移旧配置，兼容 `loot_items` 与旧锚点，保留本服身份。当前上游基线使用独立插件加载和存储。
- LS-02 保留空闲和布局开销调整。`ls_toasts/core` 数字动画按需创建及取消 ticker，仅整数变化时写文本，回收时清理引用。队列追加破坏顺序时才排序，布局与可见性仅在变化时写入。依据为上游引入后的 3905341，更新时逐项核对数字任务、排序和锚点处理链。
- LS-04 修正金币战斗勿扰配置。`ls_toasts/Bootstrap.lua` 在首次读取既有账号配置时将各配置档的 `types.loot_gold.dnd` 设为 false，以 `goldCombatQueueMigrated` 记录已处理，后续设置仍可由用户修改。新配置沿用上游默认关闭勿扰，金币仍按原生 `PLAYER_MONEY` 和 `GetMoney` 的实际余额差记录。用户保存的勿扰开关曾使战斗拾取进入队列并累计至脱战后显示。
- LS-05 物品悬停复用本服背包提示。`core/components/tooltip.lua` 以完整物品链接在全部已装备背包及材料袋定位当前格位，保留随机后缀、附魔和修正字段，通过 `GameTooltip:SetBagItem` 接入 !Pig 等背包提示挂接。物品不在背包时采用原始链接，锚点与装备比较分别复用本服 ContainerFrameItemButton_CalculateItemTooltipAnchors 和 TooltipUtil.ShouldDoItemComparison。`systems/forever/loot_item.lua` 提供原生 UpdateTooltip 回调，回收弹窗时清除回调。接口核对 forever 943764493e6b16d63ded3ab304150d1f05e58b57 的容器与 GameTooltip 源码。
- FF-01 保留宿主接入。`forever_faces/Bootstrap.lua`、Core 与媒体路径使用 `WoWTools.foreverFaces`、宿主加载事件及 `wowDetectorDB.foreverFaces.db`，复用 LibStub/CallbackHandler 并内嵌 LDB/DBIcon。开关控制初始化，部署直接迁移 ForeverFacesDB 并归档独立目录。依据为 a98c774。
- FF-02 保留单位头像重绘挂接。`forever_faces/Portraits.lua` 在 SetPortraitTexture 及原生 UnitFramePortrait_Update 安全后钩子中按 frame.portrait / frame.unit 重新绑定，覆盖职业头像及 EasyFrames 重绘。登录、进世界、目标/焦点和配置变化后合并补查，保留受限值、战斗创建与原头像回退。依据为 f38b061。
- FF-03 保留统一设置卡片。`forever_faces/UI.lua` 将原控件嵌入共享 canvas，按宽度适配和滚动，语言切换重建，旧命令与小地图入口打开此页。依据为 cf97c5c。
- FF-04 增加“3D头像 → 像素风调试”，配置保存到 wowDetectorDB.foreverFaces.db.style。模型来源、DisplayID/FileID、动画和 MipMap 支持即时应用，战斗中结构调整延后到脱战。2026-11-16 根据游戏内暴雪专用功能拦截撤下离屏快照调用链，像素化开关与采样参数显示为不可用并说明原因，已保存开启值归为关闭，采样参数保留。页面显示模型状态与 ID，单列安装更新及加载开关的 Reload 要求。公开接口缺少强制 LOD，低模使用客户端已有模型 ID。
  2026-11-16 修复提示直接挂接到各输入控件与按钮，布局后刷新原生滚动子区域。数值草稿在刷新时保留，回车、应用和焦点离开保存，Esc 恢复已保存值，重置清理草稿。
- BV-01 保留宿主接入。`better_vendor_ui/Bootstrap.lua` 与四个业务文件隔离命名空间、媒体、初始化及统一设置，配置为 `wowDetectorDB.betterVendorUI.db`。停用时跳过事件与运行控件，部署直接迁移 BetterVendorUIDB 并归档原目录。当前 1.3.1 发布包使用独立插件入口。
- BV-02 保留已学配方标记。`better_vendor_ui/BetterVendorUI.lua` 在完整与品质重绘中刷新图标去色及 136814 绿色勾，跟随学习和物品数据事件合并更新。旧 addon_fix Vendor 补丁已归档，维护收编实现。依据为 fd95272。
- BV-03 保留简体中文设置。`BetterVendorUI_Config.lua`、`BetterVendorUI_Options.lua` 及相关反馈统一中文标题、控件、确认、名单和提示，保留格式参数。依据为 12fc998。
- PX-01 保留宿主接入。`pet_xp_bar/Bootstrap.lua`、`PetXPBarPlus.lua`、`Options.lua` 使用 `WoWTools.petXPBar`、统一中文设置、账号 `wowDetectorDB.petXPBar.db` 和加载开关，保留 `/pxp`。停用时跳过运行框体、事件与计时器，部署直接迁移旧配置并归档独立插件。
- PX-02 保留无限服接口适配。`pet_xp_bar/Compat.lua` 使用本服 GetEffectivePlayerMaxLevel / GetMaxPlayerLevel，保留原生 GetPetExperience、经验与等级事件以及条目可见性处理。依据为 c70da89。
- RB-01 保留宿主接入。`raynna_bestiary/Bootstrap.lua`、`Integration.lua`、`files.xml` 与业务文件采用延迟 RegisterSource 初始化、独立命名空间和角色 `wowToolsCharacterSettings.raynnaBestiary.db`，停用时跳过业务源初始化，保留 `/rb` 与浏览器、提示及数据许可。当前安装基线仍使用独立插件存储及初始化。
- RB-02 保留设置与迁移接入。原设置控件嵌入统一页面，部署按角色直接迁移 RaynnaBestiaryDB 并归档原目录，收编源码移除旧配置导入入口。原安装版 1.1.0 与官方旧包逐文件指纹一致，本次采用官方 1.1.3 发布包，SOURCE.json 保存包和原文件指纹，更新时按此基线核对。依据为 7c38572、e3a1ac8。
- RB-03 保留中英语言和中文名称接入。`raynna_bestiary/Localization.lua`、`Settings.lua`、`Bestiary.lua`、`Browser.lua`、`LootSources.lua` 增加默认中文及角色语言选择，界面文字使用语言资源，NPC 和任务名称按 ID 优先取 QuestieDB 中文或客户端名称，并按实体类型及 ID 缓存。依据为收编后的 f09b9c4。
- RB-05 物品来源列表加入独立剥皮记录。`SkinningReference.lua` 从既有 cMaNGOS Classic SQL blob 提取 924 个怪物的 SkinningLootId、774 个剥皮表及物品名称，生成器校验原始 Git blob，复用现有引用池与概率解析。`LootSources.lua` 以 `skinning:<npcID>` 保留独立来源和物品查询缓存，`Bestiary.lua` 显示剥皮标识、头像、等级、区域及参考掉率，`Localization.lua` 提供中英文文案。已知剥皮关联覆盖未区分拾取类型的元数据，实际尸体掉落记录继续单列。沿用 1.1.3 上游基线，经典旧世覆盖和掉率尚待无限服验证，离线数据无持续轮询。
- PR-01 保留宿主接入。`prr/Bootstrap.lua`、`Integration.lua`、`files.xml` 与业务文件采用延迟 RegisterSource 初始化、独立命名空间、宿主 Ace3/LDB/DBIcon 和专用 JSON 库，配置为 `wowDetectorDB.prr.db`。停用时跳过业务事件、提示钩子与计时器，保留 `/prr` 及配方查询、规划。
- PR-02 保留设置与迁移接入。Ace 设置以 WoWToolsPRR 嵌入统一页面，部署按账号直接迁移 PRRDB 并归档原目录，收编源码移除旧配置导入入口。依据为 7c38572、e3a1ac8，发布包使用原独立入口及存储。
- PR-03 保留中文默认与补译。`prr/config/defaults.lua`、`core.lua`、`components/options_panel.lua`、`lang/en.lua`、`lang/zh.lua` 默认使用中文，首次将旧自动语言配置转为中文，保留用户明确指定的其他语言，中文优先列出并补齐标题。依据为收编后的 f09b9c4。
- PR-05 增加已学配方标记。`prr/components/recipe_row.lua` 在配方主图标和图纸图标上使用与 Better Vendor UI 一致的去色覆盖及 136814 绿色勾，勾图四边内缩 4px，每次填充行时按当前角色的已学状态更新。`utilities/game_data.lua` 按本服 NEW_RECIPE_LEARNED 的 recipeID 记录本角色已学配方，`events/items.lua` 在学习、技能及法术变化和专业窗口读取后沿用可见窗口合并刷新。原 1.5.2 的 RecipeRow.Fill 仅有品质与收藏显示，尚无该标记。
- PR-06 补齐缺失的专业学习等级。`database/recipe_details.lua` 由 `skills/wow-tools/scripts/build_prr_recipe_details.py` 从 MIT 的 LibProfessionDB 1.10.1 Forever 数据及 CC BY 4.0 的 Efficient Games 实测记录生成，固定发布包 SHA256、数据完整 commit 和输入文件指纹。原 PRR 修正后的 318 个缺项补齐 147 个，其中 87 个采用无限服数据、60 个采用带星号的经典旧世参考，171 个继续保留未知。`dataflows/recipe_index.lua` 在既有修正后补缺，用户明确标为未知及已知数值保持优先。原始上游包未含此数据接入。
- PR-07 显示具体教授配方的训练师。`utilities/recipe_sources.lua`、`components/recipe_row.lua`、`recipe_picker.lua` 与 `item_tooltip.lua` 为 553 个配方关联 195 位训练师，行内摘要和悬停列表采用“训练师姓名 / 所处位置”，实测地图记录附百分比坐标，缺少实测位置时按 QuestieDB 的 zoneID 获取区域，仍缺失时显示“位置未收录”。NPC 中文名和位置按 ID 缓存，缺译名时使用数据原名。无限服观察与经典旧世参考分别标注，上游截断的历史名单保留实际总数和收录数，缺失来源明确显示尚未收录。数据许可随模块附带，运行时采用离线表。2026-11-17 按用户要求调整格式并核对本服 C_Map.GetMapInfo / GetAreaInfo 与 QuestieDB 字段契约。

## 已回退适配

- 2026-11-17 按用户要求回退 RB-04 与 PR-04，删除 Raynna 配方页及其专用 PRR 关系查询接口，物品点击统一进入来源页。部署校验备份后归档旧 RecipeView.lua 与 ItemRecipes.lua。PRR 的原生物品配方窗口继续由其原索引提供数据。

## 更新时的适配核对

先取得目标上游完整 commit 或发布包及其哈希，逐项比较以上适配对应的函数、调用入口、存储、事件和依赖。目标上游已完整实现的项目从当前适配清单移除，同批在本节记录吸收版本、commit 或包指纹、相关文件与核对日期。部分吸收时拆分项目，仅保留剩余差异。其余项目在更新源码后重新适配，核对本服 API、TOC、加载顺序及旧数据兼容性，再更新本表和游戏内目录。宿主接入也逐项复核。当前基线的核对记录继续作为本次采用版本的依据。

## 2026-11-16 正式版更新核对

- 大脚按官方发布 manifest 的 commit、完整包 MD5、原始文件指纹核对。时光服聊天业务源与原采用安装副本在去除 BOM 和换行差异后相同。无限服新版 core.lua 的频道加入和消息值处理，以及 statReport.lua / frame.xml 的逐帧编辑框查找，由现有 BF-02 / BF-03 适配覆盖。
- BF-03 保留聊天受限值校验、频道名称与索引类型检查，使用宿主世界频道加入入口。战报发送时定位当前编辑框，移除逐帧查找编辑框的 OnUpdate 绑定。对应 core.lua、statReport.lua、frame.xml 和 WorldChannel.lua 的本地处理在本次目标上游仍需应用。
- BF-04 复用宿主 Ace3 与 LibStub，保留统一 Ace 配置容器和两服接口适配。时光服官方整合包中的 AceConfigDialog 为较早基线，采用现有宿主与无限服官方包同版本运行库并保留本地接口修改。各来源文件与包指纹记录在 SOURCE.json。
- ls_Toasts 采用 120105.06，新增默认皮肤 SLUG 字体标记。3D头像采用 1.0.11，吸收上游队伍动画、显示恢复、失败模型重试与原头像透明度处理，重新应用宿主挂接和像素风设置。现有独立适配的调用链继续适用，当前清单逐项保留。
- PetXPBarPlus 官方最新正式版为 1.3.1，采用的 tag commit 已匹配。Better Vendor UI 最新正式包仍为 1.3.1 / 9436965，下载 SHA256 与已采用发布包一致。其余模块按本服表内官方文件和指纹核对。
