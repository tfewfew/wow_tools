# wow_tools

泰坦时光服钓鱼状态指示插件和前台按键工具。

- `addon/wowDetector/`：游戏插件，默认关闭。红色=未钓鱼，绿色=钓鱼，黄色=普通背包空格为0，灰色=关闭或未知。
- `tools/wowAuto.bat`：双击启动工具，调用同目录的 `wowAuto.ps1`。
- `skills/wow-tools/SKILL.md`：维护说明及发布顺序。

## 使用

插件安装后，在游戏中输入 `/wowdetector on` 启动，`/wowdetector off` 关闭。面板提供启动/关闭及居中按钮；`/wowdetector unlock`、`lock` 控制拖动，`center` 居中，`status` 查询状态。旧命令 `/fishstate` 仍可使用。

将色块居中，再启动桌面 `wowAuto.bat`，倒计时内切回游戏。切回终端按 Ctrl+C 停止。脚本不主动切换窗口；后台时暂停，回到前台重新检测。

颜色检测周期随机300–600ms且相邻值不同；红色发送Ctrl+1，绿色等待随机8000–13000ms后发送Ctrl+2，再等待1000ms恢复检测。黄色会强制终止选中的游戏进程并结束脚本。背包判满按普通背包空格数计算，不计物品剩余堆叠容量。保持色块可见，取色无法识别时不操作。

## 修改与安装

始终先修改仓库、检查、提交并推送，再运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1
```

同步脚本核对当前分支的远端提交和工作区状态。游戏目标为 `_classic_titan_\Interface\AddOns\wowDetector`；桌面安装 `wowAuto.bat` 和 `wowAuto.ps1`。旧插件和覆盖前的桌面文件备份在 `.local-backups`，不进入 Git；旧桌面入口会转发到新版本。

首次改名后完全重启游戏，在插件列表启用 wowDetector；后续修改通常 `/reload` 即可。重载后需要再次手动启动检测。运行中的旧脚本必须停止并重新启动。
