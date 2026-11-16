# 时光服第三方插件维护表

本表为时光服插件来源、版本、适配及更新日期的维护入口。更新日期使用 Asia/Hong_Kong 的本仓库最后一次插件源码或适配修改日期。列表与维护表的排版、元数据整理沿用原日期。大脚安装副本未提供独立版本号，列表显示“未标版本”。所有路径相对 `wow_tools/`。

修改表内版本或日期后运行 `skills/wow-tools/scripts/third_party_catalog.py --write`，生成游戏内目录。统一本地检查验证两者一致。

| 模块 | 插件 | 来源 | 当前版本 | 上游基线 | 上次更新 | 本地适配 | 上次核对依据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bigfoot_channel | 大脚聊天 | 本机 BigFootChat、ChannelFilter、!!!Libs 安装副本，[大脚官网](https://bigfoot.178.com/) | 未标版本 | 安装副本未提供独立版本和 Git commit，仓库引入记录 0fc692a | 2026-11-13 | BF-01、BF-02 | 2026-11-16 核对当前收编源码及引入历史 |
| ls_toasts | ls_Toasts | [ls-/ls_Toasts](https://github.com/ls-/ls_Toasts) | 120105.05 | 355774b11757b46ed3bb4c784ad7145f03e43871 | 2026-11-14 | LS-01、LS-02、LS-03 | 2026-11-16 核对 Bootstrap、Integration、120105.05 引入与 3905341 性能修改 |
| better_vendor_ui | Better Vendor UI | [Vaniron 官方发布包](https://www.curseforge.com/wow/addons/better-vendor-ui/files/9436965) | 1.3.1 | 上游未公布 Git commit，发布包 SHA256 和文件指纹见 better_vendor_ui/SOURCE.json | 2026-11-14 | BV-01、BV-02、BV-03 | 2026-11-16 核对 Bootstrap、源码与 fd95272、12fc998 |
| pet_xp_bar | PetXPBarPlus | [DustinChecketts/PetXPBarPlus](https://github.com/DustinChecketts/PetXPBarPlus) | 1.3.1 | 0c5da2aef6b2b56e307a77e37151fe4675be6c82 | 2026-11-16 | PX-01、PX-02 | 2026-11-16 核对 Bootstrap、Compat 与 c70da89，本批同步停用提示的列表入口 |

## 当前本地适配

- BF-01 保留收编宿主接入。`bigfoot_channel/Bootstrap.lua`、`core.lua`、`frame.xml` 将命名空间、媒体、加载事件及 Ace 设置接入 wow_tools，账号配置为 `wowDetectorDB.bigfootChannel`。插件开关在加载时控制初始化，旧命令进入统一设置。当前安装基线仍需这些接入。
- BF-02 保留频道及原配置接入。`ChannelFilter.lua`、`WorldChannel.lua`、`Copy.lua` 使用宿主设置，部署脚本直接迁移 BigFootChat 与 ChannelFilter 配置并归档独立目录。时光服继续保留其他插件依赖的独立 BigFoot 与 !!!Libs，避免重复接管。依据为 0fc692a、a98c774。
- LS-01 保留宿主隔离。`ls_toasts/Bootstrap.lua`、`Integration.lua` 及 XML 使用独立命名空间、内嵌媒体、宿主 Ace3、SharedMedia、LibEditMode 及统一设置，保存到 `wowDetectorDB.lsToasts.db`，停用时跳过业务初始化。直接迁移旧配置，兼容 `loot_items` 与旧锚点。当前上游基线使用独立插件加载和存储。
- LS-02 保留时光服接口适配。`ls_toasts/Integration.lua` 使用 TitanReforged 身份及本服 `C_Item.GetDetailedItemLevelInfo`，其余客户端 API 按时光服契约核对。依据为 326a5b4。
- LS-03 保留空闲和布局开销调整。`ls_toasts/core` 数字动画按需创建及取消 ticker，仅整数变化时写文本，回收时清理引用。队列追加破坏顺序时才排序，布局与可见性仅在变化时写入。依据为上游引入后的 3905341，更新时逐项核对数字任务、排序和锚点处理链。
- BV-01 保留宿主接入。`better_vendor_ui/Bootstrap.lua` 与四个业务文件隔离命名空间、媒体、初始化及统一设置，配置为 `wowDetectorDB.betterVendorUI.db`。停用时跳过事件与运行控件，部署直接迁移 BetterVendorUIDB 并归档原目录。当前 1.3.1 发布包使用独立插件入口。
- BV-02 保留已学配方标记。`better_vendor_ui/BetterVendorUI.lua` 在完整与品质重绘中刷新图标去色及 136814 绿色勾，跟随学习和物品数据事件合并更新。旧 addon_fix Vendor 补丁已归档，维护收编实现。依据为 fd95272。
- BV-03 保留简体中文设置。`BetterVendorUI_Config.lua`、`BetterVendorUI_Options.lua` 及相关反馈统一中文标题、控件、确认、名单和提示，保留格式参数。依据为 12fc998。
- PX-01 保留宿主接入。`pet_xp_bar/Bootstrap.lua`、`PetXPBarPlus.lua`、`Options.lua` 使用 `WoWTools.petXPBar`、统一中文设置、账号 `wowDetectorDB.petXPBar.db` 和加载开关，保留 `/pxp`。停用时跳过运行框体、事件与计时器，部署直接迁移旧配置并归档独立插件。
- PX-02 保留时光服接口适配。`pet_xp_bar/Compat.lua` 使用本服 `GetMaxLevelForLatestExpansion`，经验条按本服 PetFrame、GetPetExperience 及 UNIT_PET_EXPERIENCE 接口加载，等级和经验事件刷新可见性。依据为 c70da89。

## 更新时的适配核对

先取得目标上游完整 commit 或发布包及其哈希，逐项比较以上适配对应的函数、调用入口、存储、事件和依赖。目标上游已完整实现的项目从当前适配清单移除，同批在本节记录吸收版本、commit 或包指纹、相关文件与核对日期。部分吸收时拆分项目，仅保留剩余差异。其余项目在更新源码后重新适配，核对本服 API、TOC、加载顺序及旧数据兼容性，再更新本表和游戏内目录。宿主接入也逐项复核。当前基线的核对记录继续作为本次采用版本的依据。
