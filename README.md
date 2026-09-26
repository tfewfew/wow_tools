# wow_tools

泰坦时光服钓鱼状态指示插件和前台按键工具。

- `addon/wowDetector/`：游戏插件，默认关闭。红色=未钓鱼，绿色=钓鱼，黄色=普通背包空格为0，灰色=关闭或未知。
- [tools/wowAuto/](tools/wowAuto/README.md)：wowAuto 脚本及使用说明。
- `skills/wow-tools/SKILL.md`：维护说明及发布顺序。

## 使用

插件安装后，点击“启动”或输入 `/wowdetector on`，自动将色块居中并锁定位置；点击“关闭”或输入 `/wowdetector off`，停止检测并解除锁定。关闭后可拖动面板。`/wowdetector unlock`、`lock` 控制关闭状态下的拖动，`center` 居中，`status` 查询状态。旧命令 `/fishstate` 仍可使用。

## 修改与安装

始终先修改仓库、检查、提交并推送，再运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1
```

同步脚本核对当前分支的远端提交和工作区状态，再更新游戏插件及工具安装副本。游戏目标为 `_classic_titan_\Interface\AddOns\wowDetector`。覆盖前的文件备份在 `.local-backups`，不进入 Git。

首次改名后完全重启游戏，在插件列表启用 wowDetector；后续修改通常 `/reload` 即可。重载后需要再次手动启动检测。
