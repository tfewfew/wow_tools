# wowAuto C#

Windows 桌面程序和命令行客户端。桌面程序包含钓鱼、战斗、抓宠、放号、购物、角色轮转和角色创建。时光服与无限服共用桌面程序，各自核对客户端身份、角色记录和插件状态协议。

## 构建与启动

需要 .NET 10 SDK 和 Windows 10 2004 或更新版本。角色轮转使用 Windows 简体中文 OCR 语言功能。角色创建使用原 RapidOCR 和 ONNX Runtime，运行环境见下文。游戏进程音频需要支持进程回环采集的系统版本。

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\publish.ps1
.\publish\Desktop\WowAuto.exe
.\publish\Cli\wowauto-cli.exe help
~~~

桌面发布目录中的 AudioFeatures 是运行所需的音频特征。实际设置和日志保存在 %LOCALAPPDATA%\wowAuto.CSharp。可用 WowAuto.exe --data-root DIR 指定独立位置。原脚本的设置可以按需导入，导入后的保存位置仍在 C# 版数据目录。

首次克隆和发布步骤见[仓库 README](../../README.md#首次克隆后生成-wowauto-exe)。

~~~powershell
.\publish\Cli\wowauto-cli.exe config import ..\wowAuto
~~~

导入读取原脚本的钓鱼 INI、子战网任务、战斗与抓宠配置、游戏目录和轮转间隔、队列优先级、角色创建设置。如果旧截图热键已被占用，导入会保留 C# 程序当前热键并在回执中显示被跳过的字段。旧三槽位计划和进程账号绑定属于历史数据。角色名单以当前子战网配置和客户端插件保存的角色记录为准。试听文件 titan-01-match.wav、titan-02-match.wav 和 forerver-01-match.wav 可放在数据目录的 audio-samples 或发布目录的 AudioSamples。游戏插件内保存的商品清单和宠物名称继续在游戏里设置。

## 角色创建 OCR

WowAuto.exe 通过 UTF-8 JSON Lines 管理 RapidOCR 后台。构建把旧版 OCR 图像处理、按钮预览和重试策略原样打包进发布目录下的 CharacterOcr。截图、窗口激活和点击在 C# 操作线程处理。导出的预览保留原图尺寸。

启动时优先使用 WOWAUTO_CHARACTER_PYTHON 指定的解释器，然后查找发布目录内 CharacterOcr/.runtime 的解释器。在仓库里运行时，也可以直接使用旧脚本已有的 Python 环境。独立发布目录可以用附带的安装脚本准备专用环境，安装目标在该目录下。

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\publish\Desktop\CharacterOcr\install-runtime.ps1
~~~

角色创建运行中可通过 `config set` 更新 `CharacterCreate.IntervalSeconds`、`CharacterCreate.AutoStop` 和 `CharacterCreate.DryRun`。后台下次读取状态时采用新设置，并更新 `status get` 中的配置版本。修改间隔时从本轮已用时间继续计算。试运行启用后，C# 也会在实际点击前复核开关。

## CLI

WowAuto.exe 在当前 Windows 用户会话建立命名管道。启动桌面程序后即可从同一会话连接。程序重启后可重新订阅。命令加上 --json 输出结构化回执，包含请求 ID、状态和结果。异步命令返回 accepted，使用 --wait 等待实际结果，也可用 request get ID 查询。退出码 0 表示完成或受理，1 表示操作失败，2 表示连接或通信失败，130 表示取消。

| 用途 | 命令 |
| --- | --- |
| 枚举或更新进程 | process list、process refresh、process scan |
| 查询或订阅状态 | status get [--pid PID]、status watch [--pid PID]、status log [--lines N] |
| 查询配置 | config list、config get [PATH] |
| 保存或临时修改 | config set PATH VALUE、config patch --set PATH=VALUE、config import DIR。set 和 patch 支持 --runtime，写入支持 --revision |
| 读取角色资料 | account list [--flavor titan\|forerver] |
| 启动任务 | task start --pid PID 或 --all。默认角色轮转，指定 --mode fish、fight、tame、rest 或 shop 时直接开始 |
| 停止、换角或换任务 | task stop --pid PID 或 --all、task switch --pid PID --role NAME 或 --mode MODE |
| 查改运行中的任务 | task get --pid PID [PATH]、task update --pid PID --set PATH=VALUE，可重复 --set。支持 --use-item、--role 或 --mode |
| 下发单次业务动作 | action list、action send NAME --pid PID [--wait] |
| 角色创建 | character create --pid PID、character preview --pid PID 或 --image PATH，可用 --output PNG 保存预览、character stop |
| 音频和截图 | audio preview FLAVOR ID、audio stop、screenshot select |
| 游戏退出倒计时 | shutdown set SECONDS、shutdown cancel |
| 桌面程序 | runtime close、runtime restart |

进程级任务和动作命令可额外指定 --start-ticks，供脚本复核 PID 对应的进程。process refresh 更新列表。process scan 停止任务、开启相应检测并核对有效色块。单次业务动作由当前任务核对阶段，操作线程在执行前复核插件状态和窗口。

~~~powershell
wowauto-cli config get Periods.FishMs --json
wowauto-cli config patch --set Fish.Titan.MinimumMs=500 --set Fish.Titan.MaximumMs=1200
wowauto-cli config set Periods.FishMs 150 --runtime
wowauto-cli config set /Fight/Profiles/titan:3 '{"OpeningKey":"F5","CombatKey":"F6","RecoveryKey":"F8"}'
wowauto-cli task start --pid 1234 --mode rest --wait
wowauto-cli task update --pid 1234 --set Rest.DurationSeconds=900 --wait
wowauto-cli status watch --pid 1234 --json
~~~

配置路径支持点号和 JSON Pointer 两种格式。含点号的动态键使用 JSON Pointer，例如 /Priorities/Fish.Reel。关联系统参数可以一次 patch。已保存值、当前生效值和进程的配置版本分别可查。--runtime 的值在本次桌面实例结束时清除。task update 的覆盖值属于该任务，使用 --wait 可确认任务线程采用了新版本。

检测周期、购物时间和放号时长在后续检测中更新。放号基于已累计的有效在线时间计算剩余时长。按键、抓宠步骤、操作时间及优先级用于下一条适用动作。在途操作使用其提交时的参数快照。轮转角色按下一次选角时的配置选择。视图包含任务阶段、采样时间、绝对单调时钟截止、计数、队列和动作回执。

钓鱼成功收竿才新增一次循环。周期跳跃在收竿后的保持和冷却结束后执行。改变循环间隔、重启任务、收竿失败和无咬钩超时都须等后续成功收竿才获得跳跃资格。

## 验证

本地验证覆盖 .NET 编译、管道协议、配置读取与校验、版本回执，以及仓库的两服语法、语义和接口兼容性检查。框选、真实游戏输入和时序、OCR 识别效果、音频命中以及退出流程由实际使用验证。
