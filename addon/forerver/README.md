# forerver

无限服的独立插件源码：`wow_tools/`，版本2.2.0，接口16001。目录拼写按用户约定为 `forerver`。安装后仍名为wow_tools，包含wowDetector和inner_graphic_config。

移植目标为本机 `_cn_beta_\Wow.exe` 1.60.1.70338；已核对相同构建的[Blizzard界面源码导出](https://github.com/Gethe/wow-ui-source/tree/943764493e6b16d63ded3ab304150d1f05e58b57)，不是只更换TOC号。

- wowDetector用 `C_Item.GetItemID(ItemLocation:CreateFromEquipmentSlot(16))` 和 `C_Item.GetItemInfoInstant` 识别主手鱼竿，使用 `C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand)` 返回的列表。只接受有效的 `Enum.ItemEnchantType.Temporary`，忽略Permanent和Imbue；无法读取的附魔状态为未知。状态命令补充原因。
- 引导法术ID读取UnitChannelInfo的第8项；普通施法ID读取UnitCastingInfo的第9项。API失败或返回受限值时显示未知/灰色，不将未知当未钓鱼，也不使用受限值计算或输出。
- 小地图右键和 `/wowtools` 使用 `MenuUtil.CreateContextMenu` 原生菜单；左键仍打开并启动监测，再次点击关闭并隐藏。
- inner_graphic_config保留图形选项，有效选项才开放控件，不在加载时修改CVar。帧率位置设置移动无限服的FramerateFrame整体；客户端不提供的选项显示不可用。
- 主色块仍居中，鱼饵点保持中心右侧32个物理像素、12×12像素；背包满、死亡关闭、默认隐藏和手动启动规则与titan一致。

安装目标：`C:\Program Files (x86)\World of Warcraft\_cn_beta_\Interface\AddOns\wow_tools`。先验证、提交并推送，再从仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1 -Flavor forerver
```

首次安装请重启无限服客户端，在插件列表启用wow_tools，然后点击小地图钓鱼图标或输入 `/wowdetector on`。用 `/wowdetector status` 查看检测结果，`/igc` 打开画面设置。两服的SavedVariables各自保存，不复制时光服账号设置到无限服。

`addon/tests/ForeverCompatibility.Tests.lua` 已覆盖全部TOC模块的模拟加载、新版附魔/施法API、永久附魔排除、受限/失败数据、背包/死亡、窗口调整、菜单和帧率位置。尚未以真实角色验证无限服运行效果；测试不发送按键或操作游戏。wowAuto当前只检测WowClassic.exe，无限服Wow.exe的外部按键调度尚未适配。

主要接口依据：[ItemDocumentation](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)、[UnitDocumentation](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)、[原生菜单指南](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_Menu/11_0_0_MenuImplementationGuide.lua)、[FramerateFrame](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_FramerateFrame/Mainline/FramerateFrame.xml)。
