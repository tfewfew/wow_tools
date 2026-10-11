# wow_tools

泰坦时光服、无限服的钓鱼状态指示与画面设置插件，以及 wowAuto 前台按键工具。

- [addon/titan/](addon/titan/README.md)：泰坦时光服插件，接口38002，独立源码在 `addon/titan/wow_tools/`。
- [addon/forerver/](addon/forerver/README.md)：无限服插件，接口16001，独立源码在 `addon/forerver/wow_tools/`。目录名按约定保留为 `forerver`。
- [tools/wowAuto/](tools/wowAuto/README.md)：wowAuto 脚本及使用说明。
- `skills/wow-tools/SKILL.md`：维护说明及发布顺序。

## 使用

两份插件都包含 wowDetector 和 inner_graphic_config，安装后的文件夹名均为 `wow_tools`。各自安装到对应客户端的 `Interface/AddOns/`，不要将两份同时放到一个客户端。wowDetector 默认关闭：红色=未钓鱼，绿色=钓鱼，黄色=普通背包空格为0，灰色=关闭或未知。两服 SavedVariables 分别存放在各自的 WTF 目录，不交叉复制。

无限服按本机1.60.1.70338移植：使用新版原生菜单、C_Item附魔列表和FramerateFrame；只将鱼竿的有效Temporary附魔作为鱼饵，排除永久附魔和Imbue。施法数据不可读时显示灰色，不猜测钓鱼状态。无限服版本说明和接口依据见其目录README。wowAuto 当前仍识别 `WowClassic.exe`，无限服的 `Wow.exe` 尚不属于工具检测目标。

小地图旁的钓鱼图标是 wow_tools 统一入口，右键打开菜单，可分别打开/关闭 wowDetector 和 inner_graphic_config 界面；左键点击打开面板并自动启动监测，再次点击关闭监测并隐藏面板，拖动可调整并保存入口位置。wowDetector 每次登录或重载默认隐藏且检测关闭，不恢复上次显示状态。也可用 `/wowdetector show`、`hide` 控制面板。面板“关闭”按钮停止监测并隐藏面板；仅 show/hide 命令保持单独控制显隐；隐藏时色块一并隐藏，外部工具无法读取插件色块。`/wowdetector on` 会先显示面板再启动检测。

inner_graphic_config 从原本机 1.7.0 版本收编，保留原有全部画面参数设置和 `/igc`、`/inner_graphic_config` 命令。仅点击应用或勾选时修改游戏设置。`/wowtools` 也可打开子插件菜单。

插件安装后，点击“启动”或输入 `/wowdetector on`，自动将色块居中并锁定位置；点击“关闭”或输入 `/wowdetector off`，停止检测并解除锁定。面板按钮关闭后会隐藏；使用 `/wowdetector off` 仅停止检测，可保留面板拖动。`/wowdetector unlock`、`lock` 控制关闭状态下的拖动，`center` 居中，`status` 查询状态。旧命令 `/fishstate` 仍可使用。

角色死亡时 wowDetector 自动停止监测、清空当前状态并解除位置锁定，显示关闭状态；面板保持原来的显示/隐藏状态；死亡或灵魂状态禁止启动检测，复活后需手动启动。通过死亡事件及时处理，并在检测刷新时检查存活状态。此行为控制插件本身，不向外部 wowAuto 发送停止命令。

监测面板增加鱼饵附魔检测小色块，固定在原中心检测点右侧32个物理屏幕像素，大小为12×12物理像素。按游戏画面实际高度和UI缩放换算，在窗口尺寸或UI缩放变化时重新定位，监测中的每0.1秒刷新也会补充校准。蓝色表示已装备鱼竿有尚未过期的临时附魔，紫色表示附魔缺失或已过期，灰色表示关闭、死亡、未装备鱼竿或数据未知。无法获取画面尺寸时隐藏鱼饵点，恢复后重新显示。时光服使用全局 `GetWeaponEnchantInfo`，无限服使用 `C_Item.GetWeaponEnchantInfo` 检测水下诱鱼器等鱼饵的临时附魔，鱼竿永久附魔不计入；已有其他有效临时鱼饵附魔也视为有效。`/wowdetector status` 可查看当前附魔判断、面板开关、画面像素尺寸和鱼饵点定位信息。时光服打开插件监测后，在 wowAuto 对应进程行勾选“使用钓鱼道具”即可根据此点补用，具体流程见工具说明。

`addon/tests/LureDetection.Tests.lua` 验证titan鱼竿附魔、缺失/有效/过期/未知、死亡关闭和32像素定位；`addon/tests/ForeverCompatibility.Tests.lua` 模拟无限服全插件加载、新版附魔列表、受限数据、钓鱼/背包/死亡、菜单和帧率框体。可在仓库根目录用Lua 5.1运行，不操作真实游戏。

## 修改与安装

始终先修改仓库、检查、提交并推送，再运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1
```

同步脚本核对当前分支的远端提交和工作区状态，默认分别将titan版安装到 `_classic_titan_\Interface\AddOns\wow_tools`，forerver版安装到 `_cn_beta_\Interface\AddOns\wow_tools`，并更新桌面源码快捷方式。写入前先核对两份源码TOC及游戏可执行文件版本，防止写入错误客户端。覆盖前的文件按客户端分别备份到 `.local-backups`，不进入Git。

仅同步一服时加 `-Flavor titan` 或 `-Flavor forerver`；更换安装目录时同时指定 `-Flavor` 和 `-GameRoot`。`-Flavor all` 可通过 `-TitanGameRoot`、`-ForerverGameRoot` 分别指定目录。两份源码独立维护，后续修改应明确对应版本并验证相关模拟测试。

首次改名后完全重启游戏，在插件列表启用 wow_tools；后续修改通常 `/reload` 即可。重载后需要再次手动启动检测。

升级为 wow_tools 时，同步程序备份并移走旧 wowDetector、Inner_graphic_config 目录，避免重复加载。检测配置仍使用 wowDetectorDB；首次部署复制各账号已落盘的旧配置到 wow_tools.lua，已有新配置不覆盖。图形设置保留在游戏 CVar 中。
