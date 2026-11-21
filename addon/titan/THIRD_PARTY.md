# 时光服第三方插件维护表

本表为时光服插件来源、版本、适配及更新日期的维护入口。更新日期使用 Asia/Hong_Kong 的本仓库最后一次插件源码或适配修改日期。列表与维护表的排版、元数据整理沿用原日期。大脚组件未提供独立版本号，列表标注采用的官方整合包版本。所有路径相对 `wow_tools/`。

修改表内版本或日期后运行 `skills/wow-tools/scripts/third_party_catalog.py --write`，生成游戏内目录。统一本地检查验证两者一致。

| 模块 | 插件 | 来源 | 当前版本 | 上游基线 | 上次更新 | 本地适配 | 上次核对依据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bigfoot_channel | 大脚聊天 | [大脚官方 classic_titan](https://gitee.com/bigfoot-wow/classic_titan) | 3.80.2.276（整合包） | caae1533a5331d666c7b78d44544b6285c1a3424，整包和原文件指纹见 bigfoot_channel/SOURCE.json | 2026-11-16 | BF-01、BF-02、BF-03、BF-04 | 2026-11-16 官方 manifest、整包 MD5 及组件指纹核对完成，按最新包复核并保留宿主与聊天适配 |
| ls_toasts | ls_Toasts | [ls-/ls_Toasts](https://github.com/ls-/ls_Toasts) | 120105.07 | 105214a4cc0f2d13a4c9deef57614f30cff79b33 | 2026-11-20 | LS-01、LS-02、LS-03、LS-04、LS-05、LS-06 | 2026-11-20 核对 120105.06 到 120105.07 的源码差异，合并默认关闭的 Slug 字体渲染开关。宿主接入、客户端接口、拾取队列、弹窗预建及背包提示适配继续沿用 |
| forever_faces | Forever 3D Portraits | [sorrow8/forever-3d-portraits](https://github.com/sorrow8/forever-3d-portraits) | 1.0.11 | 20eaf8fd29b03ba3d91f73a90ccbaf39b49f2af4 | 2026-11-21 | FF-01、FF-02、FF-03 | 2026-11-21 核对 1.0.11 与本服模型接口，修正目标的目标异步确认和空模型重绑 |
| better_vendor_ui | Better Vendor UI | [Vaniron 官方发布包](https://www.curseforge.com/wow/addons/better-vendor-ui/files/9676130) | 1.3.2 | 上游未公布 Git commit，发布包 SHA256 和文件指纹见 better_vendor_ui/SOURCE.json | 2026-11-21 | BV-01、BV-02、BV-03 | 2026-11-21 核对正式包 9676130 的失效物品 ID、商人过滤、名单按钮与 Leatrix 相关差异，保留宿主、已学配方标记及中文设置 |
| pet_xp_bar | PetXPBarPlus | [DustinChecketts/PetXPBarPlus](https://github.com/DustinChecketts/PetXPBarPlus) | 1.3.1 | 0c5da2aef6b2b56e307a77e37151fe4675be6c82 | 2026-11-16 | PX-01、PX-02 | 2026-11-16 官方最新正式版仍为 v1.3.1，tag 指向已采用完整 commit；宿主与本服接口适配继续适用 |

## 当前本地适配

- LS-06 减少拾取通知的同步开销。两服 TOC 加载的 `systems/forever/loot_item.lua` 先查合并目标，再检查物品过滤和可用数据，通过后才取弹窗。`core/toast.lua` 登录后分次预建最多四个可复用弹窗。`core/components/tooltip.lua` 核对完整链接后复用背包格位，格位失效时重新定位，未命中缓存在 `BAG_UPDATE_DELAYED` 清除。继续使用本服的背包范围、原生锚点与装备比较。

- FF-01 接入时光服独立的命名空间、TOC、统一设置、加载开关、账号配置、LDB/DBIcon 和原生单位头像挂接。使用本服 SetUnit(unit, blend)，等级圆环沿用本服原生处理。部署直接迁移 ForeverFacesDB 并归档独立插件目录。
- FF-02 增加“3D头像 → 像素风调试”，配置保存到 wowDetectorDB.foreverFaces.db.style。模型来源、DisplayID/FileID、动画和 MipMap 支持即时应用，战斗中结构调整延后到脱战。2026-11-16 根据游戏内暴雪专用功能拦截撤下离屏快照调用链，像素化开关与采样参数显示为不可用并说明原因，已保存开启值归为关闭，采样参数保留。页面显示模型状态与 ID，单列安装更新及加载开关的 Reload 要求。公开接口缺少强制 LOD，低模使用客户端已有模型 ID。
  2026-11-16 修复提示直接挂接到各输入控件与按钮，布局后刷新原生滚动子区域。数值草稿在刷新时保留，回车、应用和焦点离开保存，Esc 恢复已保存值，重置清理草稿。
- FF-03 目标的目标及焦点的目标按 IsUnitModelReadyForUI 等待单位数据，用 OnModelLoaded 或已填充的缓存模型文件确认加载，应用模型透明度和头像镜头。曾有文件号的模型确认丢失时先清除，再按现有节奏重新绑定当前单位。/ff debug 记录加载信号、模型可见性、模型透明度和 DisplayID。依据为 1.0.11 的异步加载分支及本服原生基线 7014c309a25338905c41dc3799a93f9719ebb533 的 TargetOfTargetMixin:Update、Unit.IsUnitModelReadyForUI、FrameAPICharacterModelBase.SetUnit 和 SimpleModelAPI.ClearModel、SetModelAlpha。
- BF-01 保留收编宿主接入。`bigfoot_channel/Bootstrap.lua`、`core.lua`、`frame.xml` 将命名空间、媒体、加载事件及 Ace 设置接入 wow_tools，账号配置为 `wowDetectorDB.bigfootChannel`。插件开关在加载时控制初始化，旧命令进入统一设置。当前安装基线仍需这些接入。
- BF-02 保留频道及原配置接入。`ChannelFilter.lua`、`WorldChannel.lua`、`Copy.lua` 使用宿主设置，部署脚本直接迁移 BigFootChat 与 ChannelFilter 配置并归档独立目录。时光服继续保留其他插件依赖的独立 BigFoot 与 !!!Libs，避免重复接管。依据为 0fc692a、a98c774。
- LS-01 保留宿主隔离。`ls_toasts/Bootstrap.lua`、`Integration.lua` 及 XML 使用独立命名空间、内嵌媒体、宿主 Ace3、SharedMedia、LibEditMode 及统一设置，保存到 `wowDetectorDB.lsToasts.db`，停用时跳过业务初始化。直接迁移旧配置，兼容 `loot_items` 与旧锚点。当前上游基线使用独立插件加载和存储。
- LS-02 保留时光服接口适配。`ls_toasts/Integration.lua` 使用 TitanReforged 身份及本服 `C_Item.GetDetailedItemLevelInfo`，其余客户端 API 按时光服契约核对。依据为 326a5b4。
- LS-03 保留空闲和布局开销调整。`ls_toasts/core` 数字动画按需创建及取消 ticker，仅整数变化时写文本，回收时清理引用。队列追加破坏顺序时才排序，布局与可见性仅在变化时写入。依据为上游引入后的 3905341，更新时逐项核对数字任务、排序和锚点处理链。
- LS-04 修正金币战斗勿扰配置。`ls_toasts/Bootstrap.lua` 在首次读取既有账号配置时将各配置档的 `types.loot_gold.dnd` 设为 false，以 `goldCombatQueueMigrated` 记录已处理，后续设置仍可由用户修改。新配置沿用上游默认关闭勿扰，金币仍按原生 `PLAYER_MONEY` 和 `GetMoney` 的实际余额差记录。用户保存的勿扰开关曾使战斗拾取进入队列并累计至脱战后显示。
- LS-05 物品悬停复用本服背包提示。`core/components/tooltip.lua` 以完整物品链接在普通背包 0–4 定位当前格位，保留随机后缀、附魔和修正字段，通过 `GameTooltip:SetBagItem` 接入背包提示及其他插件挂接。物品不在背包时采用原始链接，锚点与装备比较分别复用本服 ContainerFrameItemButton_CalculateItemTooltipAnchors 和 COMPAREITEMS / alwaysCompareItems 条件。`systems/forever/loot_item.lua` 提供原生 UpdateTooltip 回调，回收弹窗时清除回调。接口核对 classic_titan 7014c309a25338905c41dc3799a93f9719ebb533 的 Classic/ContainerFrame_Shared.lua。
- BV-01 保留宿主接入。`better_vendor_ui/Bootstrap.lua` 与四个业务文件隔离命名空间、媒体、初始化及统一设置，配置为 `wowDetectorDB.betterVendorUI.db`。停用时跳过事件与运行控件，部署直接迁移 BetterVendorUIDB 并归档原目录。当前 1.3.2 发布包使用独立插件入口。
- BV-02 保留已学配方标记。`better_vendor_ui/BetterVendorUI.lua` 在完整与品质重绘中刷新图标去色及 136814 绿色勾，跟随学习和物品数据事件合并更新。旧 addon_fix Vendor 补丁已归档，维护收编实现。依据为 fd95272。
- BV-03 保留简体中文设置。`BetterVendorUI_Config.lua`、`BetterVendorUI_Options.lua` 及相关反馈统一中文标题、控件、确认、名单和提示，保留格式参数。依据为 12fc998。
- PX-01 保留宿主接入。`pet_xp_bar/Bootstrap.lua`、`PetXPBarPlus.lua`、`Options.lua` 使用 `WoWTools.petXPBar`、统一中文设置、账号 `wowDetectorDB.petXPBar.db` 和加载开关，保留 `/pxp`。停用时跳过运行框体、事件与计时器，部署直接迁移旧配置并归档独立插件。
- PX-02 保留时光服接口适配。`pet_xp_bar/Compat.lua` 使用本服 `GetMaxLevelForLatestExpansion`，经验条按本服 PetFrame、GetPetExperience 及 UNIT_PET_EXPERIENCE 接口加载，等级和经验事件刷新可见性。依据为 c70da89。

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
