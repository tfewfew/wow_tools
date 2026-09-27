# wow_tools

泰坦时光服钓鱼状态指示插件和前台按键工具。

- `addon/wow_tools/`：wow_tools 插件合集，包含 wowDetector 和 inner_graphic_config 两个子模块。wowDetector 默认关闭。红色=未钓鱼，绿色=钓鱼，黄色=普通背包空格为0，灰色=关闭或未知。
- [tools/wowAuto/](tools/wowAuto/README.md)：wowAuto 脚本及使用说明。
- `skills/wow-tools/SKILL.md`：维护说明及发布顺序。

## 使用

小地图旁的钓鱼图标是 wow_tools 统一入口，右键打开菜单，可分别打开/关闭 wowDetector 和 inner_graphic_config 界面；左键点击显示/隐藏检测面板，拖动可调整入口位置；面板显隐和入口位置会保存。也可用 `/wowdetector show`、`hide` 控制面板。显隐不改变检测开关；隐藏时色块一并隐藏，外部工具无法读取插件色块。`/wowdetector on` 会先显示面板再启动检测。

inner_graphic_config 从原本机 1.7.0 版本收编，保留原有全部画面参数设置和 `/igc`、`/inner_graphic_config` 命令。仅点击应用或勾选时修改游戏设置。`/wowtools` 也可打开子插件菜单。

插件安装后，点击“启动”或输入 `/wowdetector on`，自动将色块居中并锁定位置；点击“关闭”或输入 `/wowdetector off`，停止检测并解除锁定。关闭后可拖动面板。`/wowdetector unlock`、`lock` 控制关闭状态下的拖动，`center` 居中，`status` 查询状态。旧命令 `/fishstate` 仍可使用。

## 修改与安装

始终先修改仓库、检查、提交并推送，再运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1
```

同步脚本核对当前分支的远端提交和工作区状态，再更新游戏插件及工具安装副本。游戏目标为 `_classic_titan_\Interface\AddOns\wow_tools`。覆盖前的文件备份在 `.local-backups`，不进入 Git。

首次改名后完全重启游戏，在插件列表启用 wow_tools；后续修改通常 `/reload` 即可。重载后需要再次手动启动检测。

升级为 wow_tools 时，同步程序备份并移走旧 wowDetector、Inner_graphic_config 目录，避免重复加载。检测配置仍使用 wowDetectorDB；首次部署复制各账号已落盘的旧配置到 wow_tools.lua，已有新配置不覆盖。图形设置保留在游戏 CVar 中。
