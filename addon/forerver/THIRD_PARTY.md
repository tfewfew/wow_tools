# 无限服第三方插件维护表

本表为无限服插件来源、版本、适配及更新日期的维护入口。更新日期使用 Asia/Hong_Kong 的本仓库最后一次插件源码或适配修改日期。列表与维护表的排版、元数据整理沿用原日期。大脚安装副本未提供独立版本号，列表显示“未标版本”。所有路径相对 `wow_tools/`。

修改表内版本或日期后运行 `skills/wow-tools/scripts/third_party_catalog.py --write`，生成游戏内目录。统一本地检查验证两者一致。

| 模块 | 插件 | 来源 | 当前版本 | 上游基线 | 上次更新 | 本地适配 | 上次核对依据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bigfoot_channel | 大脚聊天 | 本机 BigFootChat、ChannelFilter、!!!Libs 安装副本，[大脚官网](https://bigfoot.178.com/) | 未标版本 | 安装副本未提供独立版本和 Git commit，仓库引入记录 4502573 | 2026-11-13 | BF-01、BF-02 | 2026-11-16 核对当前收编源码及引入历史 |
| ls_toasts | ls_Toasts | [ls-/ls_Toasts](https://github.com/ls-/ls_Toasts) | 120105.05 | 355774b11757b46ed3bb4c784ad7145f03e43871 | 2026-11-14 | LS-01、LS-02 | 2026-11-16 核对 Bootstrap、Integration、120105.05 引入与 3905341 性能修改 |
| forever_faces | Forever 3D Portraits | [sorrow8/forever-faces](https://github.com/sorrow8/forever-faces) | 1.0.9 | cbf2cd5b71f3e32b075af2001d7c726e41850240 | 2026-11-16 | FF-01、FF-02、FF-03、FF-04 | 2026-11-16 核对 Bootstrap、Portraits、UI、Style 及 forever 原生 CharacterModelBase、Model、OffScreenFrame 接口 |
| better_vendor_ui | Better Vendor UI | [Vaniron 官方发布包](https://www.curseforge.com/wow/addons/better-vendor-ui/files/9436965) | 1.3.1 | 上游未公布 Git commit，发布包 SHA256 和文件指纹见 better_vendor_ui/SOURCE.json | 2026-11-14 | BV-01、BV-02、BV-03 | 2026-11-16 核对 Bootstrap、源码与 fd95272、12fc998 |
| pet_xp_bar | PetXPBarPlus | [DustinChecketts/PetXPBarPlus](https://github.com/DustinChecketts/PetXPBarPlus) | 1.3.1 | 0c5da2aef6b2b56e307a77e37151fe4675be6c82 | 2026-11-16 | PX-01、PX-02 | 2026-11-16 核对 Bootstrap、Compat 与 c70da89，本批同步停用提示的列表入口 |
| raynna_bestiary | Raynna's Bestiary | [raynna/raynnabestiary](https://github.com/raynna/raynnabestiary) | 1.1.0 | 安装版 commit 未公开，公开 1.0.0 对照为 3fb133ade257280ec69908dcf19c312de2e96887，安装版指纹及差异见 raynna_bestiary/SOURCE.json | 2026-11-16 | RB-01、RB-02、RB-03、RB-04 | 2026-11-16 核对安装版指纹、宿主接入及 f09b9c4 中文与配方联动 |
| prr | PRR | [izicawow 官方发布包](https://www.curseforge.com/wow/addons/prr/files/9629892) | 1.5.2 | 上游未公布 Git commit，发布包 SHA256 与文件指纹见 prr/SOURCE.json | 2026-11-16 | PR-01、PR-02、PR-03、PR-04 | 2026-11-16 核对发布包指纹、宿主接入及 f09b9c4 中文与配方索引接口 |

## 当前本地适配

- BF-01 保留收编宿主接入。`bigfoot_channel/Bootstrap.lua`、`core.lua`、`frame.xml` 将命名空间、媒体、加载事件及 Ace 设置接入 wow_tools，账号配置为 `wowDetectorDB.bigfootChannel`。插件开关在加载时控制初始化，旧命令进入统一设置。当前安装基线仍需这些接入。
- BF-02 保留频道及原配置接入。`ChannelFilter.lua`、`WorldChannel.lua`、`Copy.lua` 使用宿主设置，部署脚本直接迁移 BigFootChat 与 ChannelFilter 配置，验证后归档原独立目录和无限服 !!!Libs，复用宿主内嵌 Ace3。依据为 4502573、34e091f、a98c774。
- LS-01 保留宿主隔离。`ls_toasts/Bootstrap.lua`、`Integration.lua` 及 XML 使用独立命名空间、内嵌媒体、宿主 Ace3、SharedMedia、LibEditMode 及统一设置，保存到 `wowDetectorDB.lsToasts.db`，停用时跳过业务初始化。直接迁移旧配置，兼容 `loot_items` 与旧锚点，保留本服身份。当前上游基线使用独立插件加载和存储。
- LS-02 保留空闲和布局开销调整。`ls_toasts/core` 数字动画按需创建及取消 ticker，仅整数变化时写文本，回收时清理引用。队列追加破坏顺序时才排序，布局与可见性仅在变化时写入。依据为上游引入后的 3905341，更新时逐项核对数字任务、排序和锚点处理链。
- FF-01 保留宿主接入。`forever_faces/Bootstrap.lua`、Core 与媒体路径使用 `WoWTools.foreverFaces`、宿主加载事件及 `wowDetectorDB.foreverFaces.db`，复用 LibStub/CallbackHandler 并内嵌 LDB/DBIcon。开关控制初始化，部署直接迁移 ForeverFacesDB 并归档独立目录。依据为 a98c774。
- FF-02 保留单位头像重绘挂接。`forever_faces/Portraits.lua` 在 SetPortraitTexture 及原生 UnitFramePortrait_Update 安全后钩子中按 frame.portrait / frame.unit 重新绑定，覆盖职业头像及 EasyFrames 重绘。登录、进世界、目标/焦点和配置变化后合并补查，保留受限值、战斗创建与原头像回退。依据为 f38b061。
- FF-03 保留统一设置卡片。`forever_faces/UI.lua` 将原控件嵌入共享 canvas，按宽度适配和滚动，语言切换重建，旧命令与小地图入口打开此页。依据为 cf97c5c。
- FF-04 增加“3D头像 → 像素风调试”，配置保存到 wowDetectorDB.foreverFaces.db.style。模型来源、DisplayID/FileID、动画、MipMap、快照开关、采样边长、帧率和采样请求支持即时应用，战斗中结构调整延后到脱战。离屏捕获与采样效果由游戏内验证，页面显示运行状态和失败原因，单列安装更新及加载开关的 Reload 要求。公开接口缺少强制 LOD，低模使用客户端已有模型 ID。
- BV-01 保留宿主接入。`better_vendor_ui/Bootstrap.lua` 与四个业务文件隔离命名空间、媒体、初始化及统一设置，配置为 `wowDetectorDB.betterVendorUI.db`。停用时跳过事件与运行控件，部署直接迁移 BetterVendorUIDB 并归档原目录。当前 1.3.1 发布包使用独立插件入口。
- BV-02 保留已学配方标记。`better_vendor_ui/BetterVendorUI.lua` 在完整与品质重绘中刷新图标去色及 136814 绿色勾，跟随学习和物品数据事件合并更新。旧 addon_fix Vendor 补丁已归档，维护收编实现。依据为 fd95272。
- BV-03 保留简体中文设置。`BetterVendorUI_Config.lua`、`BetterVendorUI_Options.lua` 及相关反馈统一中文标题、控件、确认、名单和提示，保留格式参数。依据为 12fc998。
- PX-01 保留宿主接入。`pet_xp_bar/Bootstrap.lua`、`PetXPBarPlus.lua`、`Options.lua` 使用 `WoWTools.petXPBar`、统一中文设置、账号 `wowDetectorDB.petXPBar.db` 和加载开关，保留 `/pxp`。停用时跳过运行框体、事件与计时器，部署直接迁移旧配置并归档独立插件。
- PX-02 保留无限服接口适配。`pet_xp_bar/Compat.lua` 使用本服 GetEffectivePlayerMaxLevel / GetMaxPlayerLevel，保留原生 GetPetExperience、经验与等级事件以及条目可见性处理。依据为 c70da89。
- RB-01 保留宿主接入。`raynna_bestiary/Bootstrap.lua`、`Integration.lua`、`files.xml` 与业务文件采用延迟 RegisterSource 初始化、独立命名空间和角色 `wowToolsCharacterSettings.raynnaBestiary.db`，停用时跳过业务源初始化，保留 `/rb` 与浏览器、提示及数据许可。当前安装基线仍使用独立插件存储及初始化。
- RB-02 保留设置与迁移接入。原设置控件嵌入统一页面，部署按角色直接迁移 RaynnaBestiaryDB 并归档原目录，收编源码移除旧配置导入入口。安装版 1.1.0 与公开 1.0.0 的 Browser 等差异单列在 SOURCE.json，更新时逐文件核对实际采用的安装基线。依据为 7c38572、e3a1ac8。
- RB-03 保留中英语言和中文名称接入。`raynna_bestiary/Localization.lua`、`Settings.lua`、`Bestiary.lua`、`Browser.lua`、`LootSources.lua` 增加默认中文及角色语言选择，界面文字使用语言资源，NPC 和任务名称按 ID 优先取 QuestieDB 中文或客户端名称，并按实体类型及 ID 缓存。依据为收编后的 f09b9c4。
- RB-04 保留 PRR 配方联动。`raynna_bestiary/RecipeView.lua`、`Bestiary.lua`、`Integration.lua` 在 Alt 物品弹窗提供“来源 / 配方”页签、滚动表格、原生配方提示和 PRR 停用反馈。配方信息使用宿主 `WoWTools.prr.GetItemRecipes`，随索引更新刷新可见页面。依据为 f09b9c4。
- PR-01 保留宿主接入。`prr/Bootstrap.lua`、`Integration.lua`、`files.xml` 与业务文件采用延迟 RegisterSource 初始化、独立命名空间、宿主 Ace3/LDB/DBIcon 和专用 JSON 库，配置为 `wowDetectorDB.prr.db`。停用时跳过业务事件、提示钩子与计时器，保留 `/prr` 及配方查询、规划。
- PR-02 保留设置与迁移接入。Ace 设置以 WoWToolsPRR 嵌入统一页面，部署按账号直接迁移 PRRDB 并归档原目录，收编源码移除旧配置导入入口。依据为 7c38572、e3a1ac8，发布包使用原独立入口及存储。
- PR-03 保留中文默认与补译。`prr/config/defaults.lua`、`core.lua`、`components/options_panel.lua`、`lang/en.lua`、`lang/zh.lua` 默认使用中文，首次将旧自动语言配置转为中文，保留用户明确指定的其他语言，中文优先列出并补齐标题。依据为收编后的 f09b9c4。
- PR-04 保留物品配方查询接口。`prr/ItemRecipes.lua`、`dataflows/recipe_index.lua` 复用材料、成品及图纸索引与用户扫描和修正，按物品 ID 缓存并以索引 revision 失效，提供图鉴消费的配方关系和数量。依据为 f09b9c4。

## 更新时的适配核对

先取得目标上游完整 commit 或发布包及其哈希，逐项比较以上适配对应的函数、调用入口、存储、事件和依赖。目标上游已完整实现的项目从当前适配清单移除，同批在本节记录吸收版本、commit 或包指纹、相关文件与核对日期。部分吸收时拆分项目，仅保留剩余差异。其余项目在更新源码后重新适配，核对本服 API、TOC、加载顺序及旧数据兼容性，再更新本表和游戏内目录。宿主接入也逐项复核。当前基线的核对记录继续作为本次采用版本的依据。
