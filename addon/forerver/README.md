# forerver

无限服的独立插件源码：`wow_tools/`，版本2.2.2，接口16001。目录拼写按用户约定为 `forerver`。安装后仍名为wow_tools，包含wowDetector和inner_graphic_config。

移植目标为本机 `_cn_beta_\Wow.exe` 1.60.1.70338；已核对相同构建的[Blizzard界面源码导出](https://github.com/Gethe/wow-ui-source/tree/943764493e6b16d63ded3ab304150d1f05e58b57)，不是只更换TOC号。

- wowDetector用 `C_Item.GetItemID(ItemLocation:CreateFromEquipmentSlot(16))` 和 `C_Item.GetItemInfoInstant` 识别主手鱼竿，使用 `C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand)` 返回的列表。只接受有效的 `Enum.ItemEnchantType.Temporary`，忽略Permanent和Imbue；无法读取的附魔状态为未知。状态命令补充原因。
- 2.2.2绿色条件与时光服2.1.3相同：玩家正在钓鱼引导，且 `UnitGUID("softinteract")` 有目标、`UnitIsInteractable("softinteract")` 为真。抛竿施法中、没有钓鱼引导或目标消失时显示红色；引导中没有目标时显示“等待交互”。引导法术ID读取UnitChannelInfo第8项，不再将普通施法直接视为钓鱼。引导或交互API失败、缺失或返回受限值时显示未知/灰色，不比较或输出受限值；背包满仍优先为黄色。
- 监听 `PLAYER_SOFT_INTERACT_CHANGED` 并每0.1秒补充刷新，不缓存上一轮的成功状态。测试前在游戏设置中启用“交互键”；插件不修改 `softTargetInteract`。`/wowdetector status` 输出交互判断、名称、GUID及此CVar值。客户端当前选择的交互软目标不一定是自己的鱼漂，不代表咬钩，也不能用来完整扫描附近对象，仍需真实角色测试。
- 小地图右键和 `/wowtools` 使用 `MenuUtil.CreateContextMenu` 原生菜单；左键仍打开并启动监测，再次点击关闭并隐藏。
- inner_graphic_config保留图形选项，有效选项才开放控件，不在加载时修改CVar。帧率位置设置移动无限服的FramerateFrame整体；客户端不提供的选项显示不可用。
- 主色块仍居中，鱼饵点保持中心右侧32个物理像素、12×12像素；背包满、死亡关闭、默认隐藏和手动启动规则与titan一致。
- 开启检测时保存当前可读取的音频CVar，开启后台效果音、总音量/效果音最大，静音音乐/环境/对话等；关闭、死亡、登出/重载恢复原值。重复开启不覆盖快照，单独hide仍保持检测及音频配置。输出设备不改变，外部wowAuto按PID采集声音。

安装目标：`C:\Program Files (x86)\World of Warcraft\_cn_beta_\Interface\AddOns\wow_tools`。先验证、提交并推送，再从仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1 -Flavor forerver
```

首次安装请重启无限服客户端，在插件列表启用wow_tools，然后点击小地图钓鱼图标或输入 `/wowdetector on`。用 `/wowdetector status` 查看检测结果，`/igc` 打开画面设置。两服的SavedVariables各自保存，不复制时光服账号设置到无限服。

`addon/tests/ForeverCompatibility.Tests.lua` 已覆盖全部TOC模块的模拟加载、钓鱼引导与交互目标组合、目标出现/消失/不可交互、事件/轮询、受限事件参数及诊断、新版附魔API、永久附魔排除、受限/失败数据、背包/死亡、窗口调整、菜单和帧率位置。尚未以真实角色验证新增交互检测的运行效果；测试不发送按键或操作游戏。wowAuto已支持无限服Wow.exe，按_cn_beta_目录及1.60.构建识别；与时光服进程共用队列，等待范围按版本统一配置，使用说明见tools/wowAuto/README.md。

主要接口依据：[ItemDocumentation](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)、[UnitDocumentation](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)、[原生菜单指南](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_Menu/11_0_0_MenuImplementationGuide.lua)、[FramerateFrame](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_FramerateFrame/Mainline/FramerateFrame.xml)。

2.2.3增加本客户端独立维护的 `fight_detector/fight_detector.lua`（PC界面标注“永恒服 / 无限服”）：小地图右键启动 / 关闭、按职业设置测距伤害法术，读取战斗和软交互尸体的拾取 / 剥皮提示，以独立色块协议供autoFight使用。所有接口读取使用pcall并先排除受限值；不可读时暂停指令。配置保存到独立 `fightDetectorDB`，不改变wowDetector、音频及画面模块。按本次用户要求未执行验证；使用流程见工具README。

2.2.4：fight_detector由插件驱动开怪 / 正常战斗主色，并增加中心上方64px、右侧88px的独立恢复色块（蓝=无需恢复、紫=非战斗恢复、橙=战斗紧急恢复、灰=未知）。面板按本职业配置生命值进入 / 退出阈值，默认非战斗80% / 95%、战斗紧急30% / 50%；法力恢复可选，默认关闭。四向移动暂不确定自动规则，仅提供手动单次状态请求。PC需同时更新协议v2并重启；插件需/reload。详见工具README，本次仍未执行验证。
