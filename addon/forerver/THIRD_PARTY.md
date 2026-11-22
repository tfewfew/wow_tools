# 无限服第三方插件维护表

本表为无限服插件来源、版本、适配及更新日期的维护入口。更新日期使用 Asia/Hong_Kong 的本仓库最后一次插件源码或适配修改日期。列表与维护表的排版、元数据整理沿用原日期。大脚组件未提供独立版本号，列表标注采用的官方整合包版本。所有路径相对 `wow_tools/`。

修改表内版本或日期后运行 `skills/wow-tools/scripts/third_party_catalog.py --write`，生成游戏内目录。统一本地检查验证两者一致。

| 模块 | 插件 | 来源 | 当前版本 | 上游基线 | 上次更新 | 本地适配 | 上次核对依据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bigfoot_channel | 大脚聊天 | [大脚官方 forever](https://gitee.com/bigfoot-wow/forever) | 1.60.1.2（整合包） | 6b8e7466470cd2daf4c8c647eb8f97f141caafb6，整包和原文件指纹见 bigfoot_channel/SOURCE.json | 2026-11-16 | BF-01、BF-02、BF-03、BF-04 | 2026-11-17 官方 latest 仍为 1.60.1.2，manifest commit、整包 MD5 和 SHA256 与 SOURCE.json 一致，当前宿主、聊天及运行库适配继续适用 |
| ls_toasts | ls_Toasts | [ls-/ls_Toasts](https://github.com/ls-/ls_Toasts) | 120105.07 | 105214a4cc0f2d13a4c9deef57614f30cff79b33 | 2026-11-20 | LS-01、LS-02、LS-04、LS-05、LS-06 | 2026-11-20 核对 120105.06 到 120105.07 的源码差异，合并默认关闭的 Slug 字体渲染开关。宿主接入、客户端接口、拾取队列、弹窗预建及背包提示适配继续沿用 |
| forever_faces | Forever 3D Portraits | [sorrow8/forever-3d-portraits](https://github.com/sorrow8/forever-3d-portraits) | 1.0.11 | 20eaf8fd29b03ba3d91f73a90ccbaf39b49f2af4 | 2026-11-21 | FF-01、FF-02、FF-03、FF-04、FF-05 | 2026-11-21 核对 1.0.11 与本服模型接口，修正目标的目标异步确认和空模型重绑 |
| better_vendor_ui | Better Vendor UI | [Vaniron 官方发布包](https://www.curseforge.com/wow/addons/better-vendor-ui/files/9676130) | 1.3.2 | 上游未公布 Git commit，发布包 SHA256 和文件指纹见 better_vendor_ui/SOURCE.json | 2026-11-21 | BV-01、BV-02、BV-03 | 2026-11-21 核对正式包 9676130 的失效物品 ID、商人过滤、名单按钮与 Leatrix 相关差异，保留宿主、已学配方标记及中文设置 |
| pet_xp_bar | PetXPBarPlus | [DustinChecketts/PetXPBarPlus](https://github.com/DustinChecketts/PetXPBarPlus) | 1.3.1 | 0c5da2aef6b2b56e307a77e37151fe4675be6c82 | 2026-11-16 | PX-01、PX-02 | 2026-11-17 官方最新正式版仍为 v1.3.1，tag 解析出的完整 commit 与当前基线一致，宿主与本服接口适配继续适用 |
| raynna_bestiary | Raynna's Bestiary | [Raynna 官方发布包](https://www.curseforge.com/wow/addons/raynnas-beastiary/files/9725389) | 2.4.4 | 上游未公布该版本 Git commit，官方文件 9725389 的发布包 SHA256 及文件指纹见 raynna_bestiary/SOURCE.json | 2026-11-21 | RB-01、RB-02、RB-03、RB-05、RB-06 | 2026-11-21 采用 2.4.4 的参考数据、来源关系、刷新点地图及悬停恢复，保留本地双列和来源窗口 |
| prr | PRR | [izicawow 官方发布包](https://www.curseforge.com/wow/addons/prr/files/9629892) | 1.5.2 | 上游未公布 Git commit，发布包 SHA256 与文件指纹见 prr/SOURCE.json | 2026-11-22 | PR-01、PR-02、PR-03、PR-05、PR-06、PR-07、PR-08、PR-09、PR-10、PR-11、PR-12、PR-13、PR-14、PR-15 | 2026-11-22 为无限服原生训练师配方提示添加 PRR 熟练度等级，沿用官方 1.5.2 基线 |

## 当前本地适配

- LS-06 减少拾取通知的同步开销。两服 TOC 加载的 `systems/forever/loot_item.lua` 先查合并目标，再检查物品过滤和可用数据，通过后才取弹窗。`core/toast.lua` 登录后分次预建最多四个可复用弹窗。`core/components/tooltip.lua` 核对完整链接后复用背包格位，格位失效时重新定位，未命中缓存在 `BAG_UPDATE_DELAYED` 清除。继续使用本服的背包范围、原生锚点与装备比较。

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
- FF-05 目标的目标及焦点的目标按 IsUnitModelReadyForUI 等待单位数据，用 OnModelLoaded 或已填充的缓存模型文件确认加载，应用模型透明度和头像镜头。曾有文件号的模型确认丢失时先清除，再按现有节奏重新绑定当前单位。/ff debug 记录加载信号、模型可见性、模型透明度和 DisplayID。依据为 1.0.11 的异步加载分支及本服原生基线 3d8abb1da73acd38e412e24fb3f99454a6392346 的 TargetOfTargetMixin:Update、Unit.IsUnitModelReadyForUI、FrameAPICharacterModelBase.SetUnit 和 SimpleModelAPI.ClearModel、SetModelAlpha。
- BV-01 保留宿主接入。`better_vendor_ui/Bootstrap.lua` 与四个业务文件隔离命名空间、媒体、初始化及统一设置，配置为 `wowDetectorDB.betterVendorUI.db`。停用时跳过事件与运行控件，部署直接迁移 BetterVendorUIDB 并归档原目录。当前 1.3.2 发布包使用独立插件入口。
- BV-02 保留已学配方标记。`better_vendor_ui/BetterVendorUI.lua` 在完整与品质重绘中刷新图标去色及 136814 绿色勾，跟随学习和物品数据事件合并更新。旧 addon_fix Vendor 补丁已归档，维护收编实现。依据为 fd95272。
- BV-03 保留简体中文设置。`BetterVendorUI_Config.lua`、`BetterVendorUI_Options.lua` 及相关反馈统一中文标题、控件、确认、名单和提示，保留格式参数。依据为 12fc998。
- PX-01 保留宿主接入。`pet_xp_bar/Bootstrap.lua`、`PetXPBarPlus.lua`、`Options.lua` 使用 `WoWTools.petXPBar`、统一中文设置、账号 `wowDetectorDB.petXPBar.db` 和加载开关，保留 `/pxp`。停用时跳过运行框体、事件与计时器，部署直接迁移旧配置并归档独立插件。
- PX-02 保留无限服接口适配。`pet_xp_bar/Compat.lua` 使用本服 GetEffectivePlayerMaxLevel / GetMaxPlayerLevel，保留原生 GetPetExperience、经验与等级事件以及条目可见性处理。依据为 c70da89。
- RB-01 保留宿主接入。`raynna_bestiary/Bootstrap.lua`、`Integration.lua`、`files.xml` 与业务文件采用延迟 RegisterSource 初始化、独立命名空间和角色 `wowToolsCharacterSettings.raynnaBestiary.db`，停用时跳过业务源初始化，保留 `/rb` 与浏览器、提示及数据许可。当前安装基线仍使用独立插件存储及初始化。
- RB-02 保留设置与迁移接入。原设置控件嵌入统一页面，部署按角色直接迁移 RaynnaBestiaryDB 并归档原目录，收编源码移除旧配置导入入口。原安装版 1.1.0 与官方旧包逐文件指纹一致，历次升级按 SOURCE.json 中的发布包和原文件指纹核对。依据为 7c38572、e3a1ac8。
- RB-03 保留中英语言和中文名称接入。`raynna_bestiary/Localization.lua`、`Settings.lua`、`Bestiary.lua`、`Browser.lua`、`LootSources.lua` 增加默认中文及角色语言选择，界面文字使用语言资源，NPC 和任务名称按 ID 优先取 QuestieDB 中文或客户端名称，并按实体类型及 ID 缓存。依据为收编后的 f09b9c4。
- RB-05 物品来源列表加入独立剥皮记录。`SkinningReference.lua` 从既有 cMaNGOS Classic SQL blob 提取 924 个怪物的 SkinningLootId、774 个剥皮表及物品名称，生成器校验原始 Git blob，复用现有引用池与概率解析。`LootSources.lua` 以 `skinning:<npcID>` 保留独立来源和物品查询缓存，`Bestiary.lua` 显示剥皮标识、头像、等级、区域及参考掉率，`Localization.lua` 提供中英文文案。已知剥皮关联覆盖未区分拾取类型的元数据，实际尸体掉落记录继续单列。沿用独立剥皮数据基线，经典旧世覆盖和掉率尚待无限服验证，离线数据无持续轮询。
- RB-06 怪物掉落窗口按尸体掉落与剥皮并排显示。`LootSources.lua` 为怪物查询添加独立剥皮表，复用既有引用池概率解析与缓存，未分类元数据中的已知剥皮关系归入剥皮列。`Bestiary.lua` 按两列最大行数设置整体高度，各列分别排序与滚动，剥皮行保留物品提示、掉率及来源点击入口。未固定窗口按物理像素、UIParent 和窗口有效缩放计算整窗位置，优先指针右侧，右侧空间不足时置于左侧，必要时临时缩小以容纳整窗，保存缩放值继续保留。物品来源保持单列，经典旧世参考范围沿用 RB-05。
- PR-01 保留宿主接入。`prr/Bootstrap.lua`、`Integration.lua`、`files.xml` 与业务文件采用延迟 RegisterSource 初始化、独立命名空间、宿主 Ace3/LDB/DBIcon 和专用 JSON 库，配置为 `wowDetectorDB.prr.db`。停用时跳过业务事件、提示钩子与计时器，保留 `/prr` 及配方查询、规划。
- PR-02 保留设置与迁移接入。Ace 设置以 WoWToolsPRR 嵌入统一页面，部署按账号直接迁移 PRRDB 并归档原目录，收编源码移除旧配置导入入口。依据为 7c38572、e3a1ac8，发布包使用原独立入口及存储。
- PR-03 保留中文默认与补译。`prr/config/defaults.lua`、`core.lua`、`components/options_panel.lua`、`lang/en.lua`、`lang/zh.lua` 默认使用中文，首次将旧自动语言配置转为中文，保留用户明确指定的其他语言，中文优先列出并补齐标题。依据为收编后的 f09b9c4。
- PR-05 增加已学配方标记。`prr/components/recipe_row.lua` 在配方主图标和图纸图标上使用与 Better Vendor UI 一致的去色覆盖及 136814 绿色勾，勾图四边内缩 4px，每次填充行时按当前角色的已学状态更新。`utilities/game_data.lua` 按本服 NEW_RECIPE_LEARNED 的 recipeID 记录本角色已学配方，`events/items.lua` 在学习、技能及法术变化和专业窗口读取后沿用可见窗口合并刷新。原 1.5.2 的 RecipeRow.Fill 仅有品质与收藏显示，尚无该标记。
- PR-06 补齐缺失的专业学习等级。`database/recipe_details.lua` 由 `skills/wow-tools/scripts/build_prr_recipe_details.py` 从 MIT 的 LibProfessionDB 1.10.1 Forever 数据及 CC BY 4.0 的 Efficient Games 实测记录生成，固定发布包 SHA256、数据完整 commit 和输入文件指纹。2026-11-18 经 PR-09、PR-10、PR-11、PR-12 核对后，原 PRR 的 318 个缺项中 156 个采用无限服资料、162 个保留未知。`dataflows/recipe_index.lua` 在既有修正后补缺，显式用户修正及明确未知保持优先。原始上游包未含此数据接入。
- PR-07 显示配方学习地点。`utilities/recipe_sources.lua`、`components/recipe_row.lua`、`recipe_picker.lua` 与 `item_tooltip.lua` 复用 387 个配方与 142 位训练师的关联，行内摘要和悬停列表仅显示地点，已收录地图记录附百分比坐标。同一地点去重，摘要中的其他地点按处计数。位置按 NPC ID 缓存，缺少已收录位置时按 QuestieDB 的 zoneID 获取区域，仍缺失时显示“位置未收录”。PR-11 起运行时采用已核对的无限服观察与明确配方资料，缺失来源显示尚未收录。数据许可随模块附带，运行时采用离线表。2026-11-17 按用户要求调整为地点显示，并核对本服 C_Map.GetMapInfo / GetAreaInfo 与 QuestieDB 字段契约。

- PR-08 原生制作详情页显示配方熟练度阈值。`components/crafting_skill_range.lua` 在 ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox 左侧添加橙、黄、绿、灰等级，复用 RecipeIndex.Get 的当前修正及 SkillRange.Text 的格式和颜色，随原生 Init、面板显示与索引失效刷新。`events/professions.lua` 和 Integration.lua 分别覆盖延迟加载与已加载的专业界面，PRR 停用时沿用宿主加载开关。阈值缺项沿用现有未知语义，等级标签继承勾选框的缩放和显隐。按 Gethe/wow-ui-source forever 的 bebcb6bf309cf41b41bd74f8ca651e6a105b2676 核对本服 SchematicForm.GetRecipeInfo、Init 与 Camelot 勾选框底部锚点，接口检查覆盖加载次序、选中配方、左侧定位、用户修正和受限 ID。

- PR-09 校正学习起始等级与变黄等级的冲突。生成器核对 2,523 个配方，使用 Efficient Games 的 06b4cc7b814c1cb16ff56b746181c2c62944fbc9 实测记录，以及 Forever 1.60.1.70938 的 SkillLineAbility 与 ItemSparse 指纹，逐条记录原有 78 项冲突的来源和处理结果。25 项采用实测学习要求，其中粗制磨刀石与重磨刀石分别由 75/125 修正为 40/100。37 项缺乏本服依据的经典旧世补值恢复未知。16 项经图纸要求、训练师或本服资料确认，允许学习时已进入黄色、绿色或灰色。原生黄色与灰色阈值按 CSV 逐项校验，显式用户/内置修正维持优先，生成的基础修正通过既有索引应用到物品提示、规划和原生制作页。输入 URL、SHA256、旧数据基线及逐条审查记录保存到 RECIPE-SOURCES.json，接口检查覆盖完整有效库与修正优先级。

- PR-10 逐项审查未知学习要求和参考地点。以 c0d8162 的 208 个未知要求及 503 个配方的 5,126 条参考 NPC 关联为固定清单，对照本服五张客户端表、正式服与测试服训练师观察，以及 ForeverDB 的九个专业目录和 28 个 NPC 页面。ForeverDB 采用明确列出配方、训练师和费用且本服 ID、专业及黄灰阈值一致的记录，作为社区资料依据，输入快照摘录与页面指纹保存在 `skills/wow-tools/data/prr-learning-evidence.json`。品红染料补为 120，翠绿染料补为 215，速效毒药按本服自动获得记录补为 1。138 个配方的 389 条参考关联改用无限服资料，并为缺少坐标的对应 NPC 补充地点，已存在的实测坐标优先。余下 205 个等级和 4,737 条关联保存逐项缺证结果并沿用未知或参考显示。旧营火的测试服等级仅列为历史证据，图纸在当前 ItemSparse 缺失以及 MinSkillLineRank 为 1 均不足以确认当前学习要求。接口检查逐个核对审查清单、索引生效和参考标记。

- PR-11 修正硬甲皮及跨版本训练师来源。确认 ProfessionDB Forever/Sources.lua 的表头明确使用 TrinityCore Cata 与 AzerothCore Wrath 世界库，先前“经典旧世参考”的标记不准确。4,737 条未获本服佐证的关联从运行时撤下，逐项拒绝记录继续保留。只读本机 DungeonsForeverProfDB.prof.economy 中当前 1.60.1:70938 的 learningRequirements，按 CaptureTrainer 的 GetTrainerServiceSkillReq、GetTrainerServiceCost 及法术 ID 采集链核对，补齐夜色短裤／龟壳头盔 205、龟壳护腿／夜色长靴 210、熟化毛皮／毛皮护甲片／硬甲皮 225。硬甲皮 22331 学习地点改为辛特兰德拉克·石手 11097 和菲拉斯哈拉纳·铁皮 11098，对应明确教学列表及地图证据随学习摘录留存，等级来自本机实测，地点关联采用本服社区资料。其余六个同次扫描配方沿两位训练师的明确条目补录。完整 SavedVariables 保留在本机，仓库仅记录相关数值、构建及指纹。旧等级冲突审查同步更新为 32 项修正、30 项缺证、16 项确认。接口检查覆盖硬甲皮的物品入口、等级、材料、地点、原生制作页和跨版本关联撤回。

- PR-12 逐项复核 c16642d 的全部 198 个未知学习等级，含两个缺少颜色阈值的记录。本机当前训练师快照、70938 客户端教学链、物品和技能表逐项核对后，结合 Wowhead Forever 与 Azeroth DB 的明确配方要求及教学列表补齐 36 项，覆盖暗纹、黑色魔纹、专业制皮、秘银、致密石、变色治疗药水、砂纸和电池组。社区网页来源、返回文本或原始 NPC 页面指纹、同名配方及旧 Quick Facts 冲突、162 个保留未知的具体原因均存入 `questionMarkReview`。学习等级与本服黄灰阈值独立核对，7 个制皮配方的要求高于黄色值，保留其明确教学要求。补录教学关联与独立地图证据，当前实测坐标优先。电池组图纸 274049 的明确教学关系补入既有配方物品索引，沿用基础数据优先及绑定标记语义。砂纸的海加尔山 NPC 缺少已确认位置与当前可用性，保留待核对记录。原 78 项等级冲突现为 55 项修正与 23 项确认，4,695 条跨版本缺证关联继续从运行时撤下。接口检查覆盖全部审查条目、缺证语义、正常索引、地点与显式用户修正优先级。

- PR-13 学习地点按当前角色阵营过滤。`utilities/recipe_sources.lua` 在位置去重与计数前读取 UnitFactionGroup，部落显示部落与中立训练师，联盟显示联盟与中立训练师，行内摘要和所有配方悬停入口共用结果，全部被过滤时隐藏地点行。生成器为 142 位训练师补录阵营，固定 QuestieDB Forever 1.1.2、完整构建 commit、TOC 与字段及动态修正源码指纹，按 friendlyToFaction 收录联盟 45、部落 81 位，双阵营可访问训练师 16 位标记中立，其中梅罗什采用明确的木喉声望商人双阵营访问资料。来源与逐项阵营保存到 prr-learning-evidence.json 和 RECIPE-SOURCES.json。接口检查核对两阵营、保留中立、位置去重与过滤后数量、空结果、未知训练师、受限阵营及参考标记。

- PR-14 原生制作页配方行悬停显示熟练度。`components/crafting_skill_range.lua` 监听无限服原生 `Professions.RecipeListOnEnter`，校验配方行属于 `CraftingPage.RecipeList`，按悬停配方的 `recipeInfo.recipeID` 复用 `RecipeIndex.Get` 和 `SkillRange.Text`。原生截断名称提示已显示时在其下追加熟练度，完整名称有等级数据时显示名称与熟练度，原生 `OnLeave` 负责关闭。沿用 PRR 模块开关与 Profession UI 加载入口。事件参数、提示归属和关闭顺序依据 `bebcb6bf309cf41b41bd74f8ca651e6a105b2676` 的 `Blizzard_ProfessionsRecipeList.lua`。

- PR-15 原生训练师配方提示显示熟练度。`events/tooltip.lua` 在主 `GameTooltip` 处理 `GetTrainerService` 的法术数据时按 `data.id` 查询 `RecipeIndex.Get`，通过 `SkillRange.Text` 和 `tooltip.skill_range` 显示与制作页配方悬停一致的颜色及括号格式。按 Gethe/wow-ui-source forever 的 `3d8abb1da73acd38e412e24fb3f99454a6392346` 核对 `Blizzard_TrainerUI.xml` 的 `SetTrainerService` 入口及 `TooltipDataHandler.lua` 的回调和重建顺序。接口检查覆盖冰霜皮质披风法术 9198、无配方数据、普通法术提示和 PRR 停用。

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

## 2026-11-21 正式版更新核对

- Better Vendor UI 1.3.2（9676130）在 `BetterVendorUI.lua`、`BetterVendorUI_Config.lua` 和 `BetterVendorUI_Filters.lua` 修复失效物品 ID 重试、商人换货后过滤缓存、名单和 Leatrix 同步。官方 TOC 与初始化仍使用独立入口及保存表，保留 BV-01。官方商人重绘未挂接已学配方事件和标记，保留 BV-02。新增反馈翻译为中文，保留 BV-03。本地过滤缓存为缺少 `GetMerchantItemID` 的接口环境保留物品链接检查，类别缺失时重新读取。包指纹及原文件清单见 `better_vendor_ui/SOURCE.json`。
- Raynna’s Bestiary 2.4.4（9725389）用 `Metadata.lua` 更新 QuestieDB 快照至 1.1.3，引入 `DungeonReference.lua`、`ForeverSources.lua`、`ForeverPortraits.lua` 和位置、关系数据。复用 `ItemsMap.lua` / `SpawnOverlay.lua`，怪物窗口和物品来源行可查看已记录刷新区域，隐藏窗口后释放固定与悬停状态。上游 `Core.lua`、`ItemsCore.lua`、`Settings.lua` 和两个 TOC 使用独立保存表、配置迁移、命令与设置，RB-01 至 RB-03 继续使用宿主绑定和语言设置。上游 `LootSources.lua` 没有剥皮独立数据，`Bestiary.lua` 和 `ItemsUI.lua` 的来源列表没有尸体与剥皮双列，保留 RB-05、RB-06。沿用 2026-11-17 的配方入口范围，物品点击继续进入来源窗，PRR 提供配方查询。本次采用新版数据、地图和来源功能，并沿用宿主界面。上游 Codex 独立配置加载器、配方页和版本广播未接入。原包及文件指纹见 `raynna_bestiary/SOURCE.json`。
