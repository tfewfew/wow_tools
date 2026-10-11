---
name: wow-tools
description: 维护titan时光服、forerver无限服的独立wow_tools插件合集及wowAuto前台脚本，验证并提交推送后按客户端同步插件和桌面源码快捷方式。
---

# wow_tools

源码仓库：`C:\code\wow_tools`，远端 `origin`。插件源码分开归档在 `addon/titan/wow_tools/`（时光服）和 `addon/forerver/wow_tools/`（无限服），保留用户指定的forerver拼写；不要恢复旧的addon/wow_tools或让两服互相引用源码。图形工具在 `tools/wowAuto/`（wowAuto.ps1、wowAuto.Engine.ps1、wowAuto.Audio.cs、wowAuto.bat），使用说明在该目录 README.md。不要把游戏目录或桌面副本当作修改源。

## 修改与同步顺序

1. 检查 Git 状态、当前分支及远端，保留无关改动。在仓库修改源码及必要说明。
2. 检查PowerShell及Lua语法；修改内嵌C#时只编译，不运行主循环。验证受影响客户端：titan用addon/tests/LureDetection.Tests.lua，forerver用addon/tests/ForeverCompatibility.Tests.lua；两者Lua5.1模拟运行。同步配置用skills/wow-tools/tests/ClientProfiles.Tests.ps1验证。不要为测试发送真实按键或关闭游戏。
3. 将本次修改提交，并推送当前分支到 `origin`。用户已授权此流程，无需逐次索要许可。不强推。推送失败时保留本地提交并报告原因，不同步安装副本。
4. 推送成功后运行 `skills/wow-tools/scripts/sync-local.ps1`，默认Flavor=all分别同步两服。也可显式-Flavor titan/forerver；GameRoot覆盖必须同时选择一服，all通过TitanGameRoot/ForerverGameRoot各自覆盖。client-profiles.ps1提供独立源码和目标映射，写入前核对所有所选客户端可执行文件的3.80./1.60.版本前缀及源码TOC接口号，拒绝混用同一目录或写入零售版。它核对干净工作区和远端分支提交，再同步插件并校验文件哈希，通过install-desktop-shortcut.ps1更新桌面源码快捷方式并归档旧运行副本。
5. 报告提交、推送和同步结果，提醒用户停止旧脚本并重启桌面 `wowAuto` 快捷方式；插件变更需 `/reload`，改名首次安装可能需要完全重启游戏。

## 安装目标

- titan游戏：`C:\Program Files (x86)\World of Warcraft\_classic_titan_\Interface\AddOns\wow_tools`，客户端WowClassic.exe 3.80.2，接口38002。
- forerver游戏：`C:\Program Files (x86)\World of Warcraft\_cn_beta_\Interface\AddOns\wow_tools`，客户端Wow.exe 1.60.1.70338，接口16001。
- 桌面：通过 Windows Desktop 特殊文件夹解析，仅创建 `wowAuto.lnk`，直接指向源码 tools/wowAuto/wowAuto.bat，WorkingDirectory 设置为该源码目录；不复制运行文件到桌面。
- 同步脚本将旧 `FishingState`、`wowDetector`、`Inner_graphic_config` 插件移到仓库忽略目录 `.local-backups`；快捷方式验证成功后，将桌面旧 wowAuto 三个运行文件及 wow-foreground-loop 两个入口移入该次备份的 Desktop 子目录。只处理确切文件名，不广泛清理桌面；移动前检查绝对路径，源码目录需保留完整运行文件。
- 不提交本机备份、游戏配置、SavedVariables或外部依赖。tools/wowAuto/config.ini按用户要求纳入Git，属于工具共享配置，不受此条排除；保留用户在设置窗口保存的值，后续维护时检查其改动。备份按titan/forerver分子目录；SavedVariables迁移只在各自客户端内进行，不跨服复制。

## 行为约定

- titan版基于原2.1.1独立维护，当前2.1.2/接口38002。forerver版当前2.2.1/接口16001按无限服1.60.1.70338的Blizzard导出源码943764493e6b16d63ded3ab304150d1f05e58b57移植；以后跟随对应分支源码核对API，不能仅改TOC号。
- forerver在Init.lua后加载Compatibility.lua：ItemLocation主手槽16及C_Item.GetItemID/GetItemInfoInstant识别鱼竿，C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand)返回列表，只接受有效Temporary附魔，排除Permanent/Imbue；失败或受限/不完整数据为unknown。UnitChannelInfo的技能ID在第8项，UnitCastingInfo在第9项；先用issecretvalue排除受限返回再比较/输出，受限施法使主色块灰色。注册WEAPON_ENCHANT_CHANGED并每0.1秒刷新。菜单使用MenuUtil.CreateContextMenu；画面模块移动FramerateFrame整体，不再依赖FramerateLabel全局。未提供的CVar继续禁用，禁止加载时自动改变图形设置。forever测试覆盖全TOC加载，不发送游戏按键。
- wowAuto同时识别时光服_classic_titan_/WowClassic.exe 3.80.和无限服_cn_beta_/Wow.exe 1.60.，允许游戏根目录位于其他盘符，但产品目录名须匹配。GetClientFlavor同时核对可执行文件名、父目录与构建前缀；未知/无法读取/零售服不加入列表。每行Client保存Flavor、Label、ExecutablePath；启动、取色、焦点切换、发键及正常/超时退出均核对PID、StartTime、路径与客户端身份。C#方法接收启动Ticks和预期路径，不能退回只按Wow进程名操作。

- wow_tools 是唯一 TOC 插件，子目录 wowDetector 和 inner_graphic_config 分别保存模块；Init.lua 初始化 WoWTools.modules，Core.lua 统一小地图及右键菜单。图形模块来自本机 Inner_graphic_config 1.7.0，保留 /igc 和原有设置行为。同步先完整复制验证，再归档旧独立插件；首次复制账号旧 wowDetector.lua SavedVariables 为 wow_tools.lua，已有目标不覆盖。
- 小地图右键菜单分别切换两个子模块界面，/wowtools 打开菜单。小地图钓鱼图标左键打开面板并自动启动检测，再次点击停止检测并隐藏面板；右键菜单中的wowDetector及模块Show采用相同行为，面板关闭按钮停止检测并隐藏，拖动调整入口角度；panelHidden、minimapAngle 保存到 wowDetectorDB。show/hide命令仅控制显隐，不改变检测开关；隐藏时色块也隐藏；状态更新独立于面板可见性。show/hide 命令控制显隐，on 命令先显示面板。入口不依赖外部库。
- 泰坦时光服接口版本目前为 38002；wowDetector 面板创建时即隐藏，每次登录或重载重置 panelHidden=true，检测默认关闭，不恢复上次面板显示状态。小地图入口及 show/on 命令仍可打开。`/wowdetector` 是主命令，`/fishstate` 保留为兼容别名。
- 绿色表示钓鱼，红色表示非钓鱼，黄色表示随身普通背包空格为零，灰色表示关闭或数据未知。黄色优先于红绿。排除银行、材料及专用背包；不估算现有物品剩余堆叠容量。
- wowDetector 使用PLAYER_DEAD及UnitIsDeadOrGhost检测角色死亡/灵魂状态，优先停止监测、清空状态与计时、解除位置锁定并显示关闭状态；保留面板显隐，不改panelHidden。死亡时禁止启动，复活事件不得自动重启；进入世界及监测刷新补充检查。只重置插件，不宣称能直接停止外部wowAuto。
- “启动”按钮和 on 命令将色块中心对齐客户区中心、保存位置并锁定；关闭时解锁。无独立居中按钮，center 命令仍兼容。运行中不允许拖动或用 unlock 解锁；登录或重载默认关闭且解锁。
- wowAuto主界面及设置采用柔和灰度：背景RGB226/228/232、行/工具栏面RGB235/237/240、输入及状态框RGB230/232/235，深色文字；避免恢复大面积纯白。KeyItem.UiTests.ps1覆盖设置内输入框/实际KeyDown事件、草稿隔离、取消/校验失败/保存/重新打开及已配置按键的模拟下发；预览检查主界面和设置布局，不发送真实按键。
- wowAuto 的 autofish 标签页包含刷新进程、全部开始、全部停止按钮，按已识别的两服进程生成独立控制行，每行横向排列进程信息、开始/停止、使用钓鱼道具复选框、状态框，移除逐进程范围输入。PID后显示时光服/无限服及窗口位置。初始按钮锁定。刷新先停止所有任务并清空事件，再按PID和启动时间更新列表，保留存活行的道具勾选，等待范围属于版本配置，移除已退出行；复用PID不得继承状态或勾选。窗口宽度随新增列适配，屏幕容不下时列表允许滚动。
- 用户授权刷新扫描轮流切换游戏窗口到前台，约200ms后读取中心色，未识别最多重试到800ms。只有红/绿开放按钮，黄/灰/未知/切换失败保持锁定；刷新期间不允许自动按键或结束游戏。完成后尝试恢复原前台，任务需手动重新开始。
- 用户已授权运行时自动切换窗口。全部开始只将通过验证的行加入统一调度队列；只有调度目标在前台时发送按键。任务共享单调时钟，不能因切到后台取消收竿事件。
- 每行默认未启动。工具栏“设置”按钮打开两服统一等待范围编辑器，两服内部默认及当前INI均为300–600ms，音频模式用于匹配成功后的随机收竿延迟，取消音频时从变绿开始按同范围计时，实际启动值读取config.ini，步长1000ms，允许1–3600000整数且下限不大于上限。保存前验证两份范围，再以key=value原子写入脚本目录tools/wowAuto/config.ini；覆盖已有文件时File.Replace的无备份参数必须使用[System.Management.Automation.Language.NullString]::Value，不能直接传$null（Windows PowerShell 5.1会转换为空路径并报错）；等待范围及所有进程共用的FocusRetryIntervalMs持久化，config.ini须提交到现有origin远端。七个键为TitanMinimumMs/TitanMaximumMs/ForerverMinimumMs/ForerverMaximumMs/FocusRetryIntervalMs/TitanAudioThresholdPercent/ForerverAudioThresholdPercent；前五项为毫秒、后两项为百分比，兼容旧五键文件见音频约定；支持空行、;和#整行注释，键名不区分大小写，拒绝重复/缺失/未知键、分节及非法值。保存规范化重写七项，不自动运行Git。焦点重试默认30000ms，设置窗口支持1000–3600000整数、步长1000ms；已迁入原本JSON配置的两服范围和重试值，不再读写LOCALAPPDATA旧JSON。保存前一并验证所有字段，失败不得部分应用。设置按Flavor应用到所有同服活动任务的MinimumMs/MaximumMs，影响下次登记的等待，不重算已登记Deadline/Event.Due。取消/校验或保存失败不应用。重启读取配置，错误则保留默认并显示提示。设置弹窗期间暂停自动切换/发键和刷新扫描，保留队列，关闭后继续。单行停止清除本行事件，全部停止/刷新/关闭窗口清空所有任务与事件。使用非阻塞定时器保持按钮响应。
- 红色窗口按随机300–600ms周期持续抛竿键直到变绿；相邻周期不同。定时模式绿色登记随机毫秒收竿事件，立即轮转下一窗口。已到期收竿优先于下竿和窗口切换，按截止时间/登记顺序处理，但不得抢占收竿后可配置的前台保持阶段。
- 工具栏在全部停止后显示进程检测数量，提供全局收竿保持输入0–60000ms，默认100，0表示不保持；修改从下次成功收竿生效，不缩短当前保持。启动窗口按内容和行数适配并居中，尺寸限制在屏幕可用区域内，超出高度的行滚动查看。
- 使用钓鱼道具复选框位于各进程行，默认关闭，可在启动前选择或运行中单独修改；全部开始沿用各行选项。停止/重启该行、刷新保留同一PID+启动时间的勾选，新进程或重启工具默认不勾选。三个全局抛竿/收竿/道具按键录入统一放到设置窗口的快捷键分组，主工具栏不保留按键录入行并缩短高度。默认0/=/-（主键盘单键，VK48/187/189），支持主键盘-（VK189）和=（VK187），可录入Ctrl/Shift/Alt组合。New-KeyBinding生成映射；Set-KeyBinding只写入弹窗独立草稿，计时/门槛验证并保存成功后一次应用三个映射，取消/关闭/校验或保存失败不得应用草稿。重新打开设置显示当前分配，保存从下一次按键生效，按键沿用本次运行有效、重启恢复默认的行为，不扩展七项INI格式；设置窗口须明示。NativeInput.PressChord负责发送配置键并释放修饰键。
- wowDetector新增鱼饵小色块，中心固定为原中心检测点右侧32个物理屏幕像素、大小12x12物理像素。UI单位每物理像素为768/GetPhysicalScreenSize返回的实际画面高度/panel:GetEffectiveScale()（与Blizzard PixelUtil换算一致），不能只除UI缩放。DISPLAY_SIZE_CHANGED、UI_SCALE_CHANGED和监测中每0.1秒刷新都重新定位；尺寸或缩放无效时隐藏小点并设为未知，有效后恢复，主色块坐标不变。titan使用GetInventoryItemLink(player,16)及GetItemInfoInstant确认主手为武器类2、鱼竿子类20，再以GetWeaponEnchantInfo主手临时附魔及剩余毫秒判断：蓝色有效、紫色缺失/过期、灰色关闭/死亡/非鱼竿/未知。水下诱鱼器及其他有效临时鱼饵附魔均算有效，永久附魔不算；不依赖普通UnitAura；forerver使用上述Compatibility.lua的新版接口。状态命令包含附魔、开关/显隐、画面像素尺寸及小点定位信息，死亡关闭重置小点。LureDetection.Tests.lua按UI单位*有效缩放*实际高度/768还原物理像素，覆盖窗口尺寸和UI缩放组合，不能把有效缩放误当完整像素换算。
- 道具调度改为附魔检测，移除固定600000ms和启动时无条件使用。UseItem属于任务State，不属于全局Scheduler；Add-WowAutoTask通过UseItem参数初始化，Set-WowAutoItemEnabled按Key仅修改对应活动任务。各行勾选/启动立即登记本行Item检查，Get-WowAutoWork仅为UseItem=true且Ready/Casting的行安排检查，不抢占Wait/Cooldown。适配层仅为勾选行在Item及Poll取色时读取右侧32像素点，未勾选行不检测、不因鱼饵未知暂停且不发送道具键。Complete-WowAutoItemCheck处理：有效解除InitialItemPending并跳过使用；缺失+红色请求道具；缺失+绿色先完成现有钓鱼；未知阻止该行抛竿、每1000ms重查并释放ActiveKey。已到期收竿优先于道具检查，其他行继续。成功发送仍设置全局ItemHoldUntil=完成时刻+3000ms，ItemDue同期重查且InitialItemPending保持，需确认附魔有效才恢复抛竿；缺失时至少5000ms后再次使用，失败发送500ms后重试且不新增保持。3秒内所有抛竿/收竿/取色及刷新切换暂停，到期事件排队，UI和停止按钮响应；取消任一行勾选不缩短保持，只解除对应行的后续附魔检查限制。道具不计循环、不重置钓鱼事件，黄色及焦点/身份规则沿用。各行ItemStatus仅在本行勾选时显示并参与状态时间戳。ItemDetection.Tests.ps1、ItemDetection.UiTests.ps1、ProcessItems.UiTests.ps1、KeyItem.UiTests.ps1、InputAdapter.Tests.ps1及addon/tests/LureDetection.Tests.lua仅模拟验证，不发送真实按键。
- 成功发送收竿键并释放按键后设置全局 ReelHoldUntil=完成时刻+配置保持时间；调度队列及刷新扫描在此之前均不切换窗口，到期事件排队等待。保持UI响应，可停止任务，不使用阻塞睡眠。从同一完成时刻计时max(1000ms,配置保持时间)再入下竿队列，保持包含在冷却内；发送失败不新增保持时间。
- 统一队列存储任务会话引用，停止/重启不得执行旧事件。灰/未知暂不按键并让出队列。只在窗口被调度到前台时检测黄色，不承诺后台持续取色。实时状态以[HH:mm:ss]显示状态更新时的本机时间戳，未启动、刷新、运行和停止均显示；基础消息保存在StatusMessage或State.Status，避免重复添加时间前缀。每行通过StatusSnapshot跟踪基础消息、Mode、Deadline、FocusRetryAt，道具等待使用ItemHoldUntil标识新阶段；变化时才更新StatusTimestamp。单纯倒计时变化或UI定时刷新不得更新时间戳。StatusTimestamp.UiTests.ps1使用模拟时钟验证稳定状态及各类倒计时保留时间戳，新状态/新事件刷新。
- 运行时切换失败、800ms内无法取得焦点、检测或发送按键时失去焦点，不停止任务；通过FocusRetryAt=失败时刻+Scheduler.FocusRetryIntervalMs暂停对应行并显示秒级重试倒计时，保留Mode、收竿事件、道具计时及抛竿标记，释放ActiveKey，其他行继续。Get-WowAutoWork跳过该行所有普通事件，重试到期返回独立FocusRetry动作；每次重试先验证PID/StartTime及客户端路径/版本身份，恢复焦点后清除暂停继续原流程，失败后按当前配置重新计时。保存新间隔不重算已登记的FocusRetryAt；基础状态文字不写死30秒，行内倒计时仍根据原截止时间显示。到期收竿和道具仍先于焦点重试，重试先于普通抛竿，不能抢占收竿保持或道具3秒等待。进程退出、身份变化及其他执行异常仍停止该行；手动停止、全部停止、刷新及关闭清除重试，重启不得继承。刷新扫描失败行为保持锁定按钮、不自动启动。FocusRetry.Engine.Tests.ps1及FocusRetry.UiTests.ps1模拟验证边界、重复失败、恢复、事件保留、隔离、取消与身份校验。
- 成功收竿后设置CheckReelGreen；原冷却结束后的首次红/绿检测，绿先返回Jump发送单独空格（VK32，无修饰键），成功清除标记，下一轮询继续原强制抛竿流程；红清除标记并正常抛竿。灰/未知保留判断、黄色优先，失败可重试，每次收竿最多成功跳一次；不得跳过原保持及道具3秒等待。
- 成功收竿后设置任务 ForceNextCast，原冷却结束后首次红/绿均发送抛竿键；成功发送后通过 Complete-WowAutoCast 清除标记，恢复正常颜色轮询。发送失败保留标记；黄色处理和灰/未知不按键规则不变。新任务不继承标记，首次启动不强制抛竿。
- 成功收竿同时设置 AwaitingFishingTransition=true、SawIdle=false；新一轮必须先读到红色，再读到绿色才登记收竿事件，从确认绿色时计时。强制抛竿后残留绿色只按300–600ms轮询，不重复强制按键、不登记事件；检测到红色继续正常抛竿。上一轮红色不得沿用；首次启动绿色可直接进入等待的行为保留。
- 有效循环定义为已登记的收竿事件成功发送收竿键，一次事件只计一次；不等于确认钓获。计数存储在统一调度器的 CompletedCycles 中，按PID和启动时间对应的Key区分，停止/重启任务/刷新不清零；新游戏进程或重启工具从0计数。行内显示累计次数。
- 运行中黄色只有累计有效循环严格大于500（501起）才核对身份并通过Process.CloseMainWindow请求游戏正常退出。先停止该行、清空钓鱼事件并禁用开始；请求后登记独立pendingGameExits保护，30秒未退出才重新核对StartTime及客户端路径/版本身份并对原Process实例Kill一次。正常请求失败但已确认身份并尝试关闭时同样计时；身份改变取消保护，不误杀复用PID。保护检查在主UI定时器独立执行，不阻塞其他任务。进程正常退出取消保护，强制结束失败仅报告，不无限重试；单行停止、全部停止、刷新和工具关闭取消待执行超时保护。请求被接受不代表已退出，不提前设置Exited。次数不足仍只停该行；刷新扫描不请求退出。GracefulExit.Tests.ps1使用模拟进程验证30秒边界、提前退出、阈值、失败和隔离，不关闭真实游戏。不要在部署时点击开始触发真实操作。
- `tools/wowAuto/tests/Engine.Tests.ps1` 验证纯队列调度。PreviewPath 参数渲染初始窗口；源码中的 UiTest 参数执行 Layout.UiTests.ps1、Refresh.UiTests.ps1 和 Scheduler.UiTests.ps1，以模拟进程验证扫描、按钮、轮转和到期抢占，不调用真实切换/取色/按键/结束进程。

- 窗口位置以窗口中心相对主要所在显示器划分四象限；中心在屏幕中点宽高各10%范围内为居中，最小化/读取失败分别标识最小化/位置未知。ReadWindowPosition在同一DPI上下文读取窗口及显示器物理坐标，支持负坐标显示器；独立1000ms只读定时器更新Row.Position和进程标签，不切换窗口/取色/发键，不改变状态时间戳。ClientIdentity.Tests.ps1仅调用生产C#纯函数；ClientSettings.UiTests.ps1在UiTest内模拟两服队列、统一设置、计时不变、编辑暂停、位置更新、无限服焦点和退出保护。UiTest设置文件使用独立临时.ini路径并清理，校验源码config.ini哈希未改变，不能写用户真实配置；覆盖INI重复保存、注释/大小写/BOM、重复/缺失/未知键及非法范围、文件锁定时不部分应用。

## 音频咬钩检测及设置恢复

- wowAuto不提供录音、WAV导入/导出、试听或制样界面；ProcessCapture仅实时监听，在内存中保留短帧用于匹配，不保存音频。audio-features/titan.feature及forerver.feature保存经过校准的数值特征，按版本独立加载；缺失/无效时阻止对应行启动，不隐式退回纯峰值。保留config.ini原五项计时值，新增两项音频门槛见下面约定；原audio-samples目录继续忽略以保留本地旧样本，但运行时不读取。
- 用户已通知开始，无限服三分钟采集已完成：.local-backups/audio-calibration-3min-pending/forerver-raw.wav，44.1kHz PCM16单声道、7938000点/180秒，及音频采样时间轴、中心色块时间线。目录名保留pending但内容已完成；不得自动续录，每次新采集仍需用户通知。用户确认主要等引导结束再抛竿，部分背景时段缺少颜色标签，不能把候选视作已确认钓获。工具只录身份核对后的目标PID并观察色块，不发送按键、不切换窗口，wowAuto没有录制入口。原始录音/候选WAV/分析及临时工具均留本机不上传；只提交数值特征、实现及验证说明，不把样本变换当多轮实测，不将一服特征冒充另一服。
- 用户本次明确要求匹配门槛可设置，覆盖旧约定“INI只含五项”的限制：新增TitanAudioThresholdPercent/ForerverAudioThresholdPercent，两服默认86、50–100整数百分比、步长1；设置弹窗每服行加入音频门槛。原五项计时键保留，四项等待值按后续用户授权改为两服300–600ms，焦点重试值保留。两音频键同时省略时兼容旧五键文件、沿用当前门槛（启动86）且不重写；仅缺一项拒绝。保存统一验证七项、原子重写，保存失败/取消不部分应用。实际匹配使用设置门槛，.feature的Threshold仅推荐；启动及活跃TemplateMode监听按Flavor配置，ProcessCapture.SetMinimumSimilarity在锁内更新，保留候选/预热/音频会话/已有信号/队列；从下次比较生效。行内显示分数与门槛，不刷新状态时间戳。不因低门槛宣称准确率提升，不能将门槛变化伪称已经完成多轮校准。
- 模板模式通过原音量门槛后，比对24个整体对数频带（512点FFT）、8段×24频带的时序频谱及16段音量包络；三组各自归一化，权重35%/50%/15%，保留先后顺序。特征文件格式2/11025Hz/11025样本，包含SpectrumBands=24/TimeSlices=8/EnvelopeBins=16、门槛0.5–1及1–8组232维变体；拒绝格式1，不能将旧32维数据直接迁移。候选保留200ms历史并收集约一秒后续帧；对齐取开头600ms内最强10ms帧向前最多300ms寻找起点、保留80ms引入帧，完整一秒才比较，不静音补尾。候选先收集1.2秒（含200ms历史），若该固定起点的尾部不足，保留候选及其目标长度继续收集，最多1.6秒，不提前以零分拒绝缓慢起伏的声音。三个±256点时间偏差比较取最高分，约1–1.4秒判断延迟；仅通过后消耗本轮信号，拒绝150ms后继续监听。会话切换及道具等待清空旧候选，实时指标不更新时间戳。不宣称能区分其他玩家播放的同一音效或保证排除全部干扰。
- 当前forerver.feature已替换旧单片段为三分钟录音的共同特征：第1.706/68.444/124.547秒的三段起点对齐后，对232维整体频谱/时序频谱/包络分别求平均并归一化，单个Template；44.100/97.419/179.193秒三个其他轮次片段保留验证、不参与准备。仍Status=trial，推荐Threshold=0.90，config.ini实际门槛86%保持用户值。完整录音按钓鱼区间生产回放在86/90门槛下各接受一次，分数0.930455/0.922942/0.954749/0.958652/0.972035/0.970672；保留第二、第四段改变包边界/大小最低0.914497仍通过，五个抛竿初始区间及153–158秒其他声音区间无误接受，后者0.762079被拒绝。仅一次会话候选验证，不称跨场景准确率；相似度高的弱背景声仍由音量/基线及绿色后一秒预热筛除，不能省略这些门槛。Status允许trial/verified、省略按trial；状态框显示试用匹配，不因指标更新时间戳。时光服无实测特征，不套用无限服数据，其音频启动提示缺失，可取消音频使用定时模式。
- Audio.Template.Tests.ps1使用合成音频验证归一化、相同频谱换序/尾段缺失/短窗口拒绝/小幅对齐、迟到强峰的有界补帧/实时门槛、拒绝干扰后继续监听、去重/预热/重置及数值文件/变体/非法与旧格式数据；UiTest追加Audio.Features.UiTests.ps1验证没有录制UI/API、两服独立特征、缺失/无效门槛及时间戳。Audio.Capture.Smoke.ps1仅实时监听自身无声PowerShell进程，不录音、不采集游戏。实际长录音需等待用户通知。
- 两服独立的wowDetector/Audio.lua在检测模块前加载。仅从关闭切到开启时保存支持的音频CVar到wowDetectorDB.audioSnapshot，开启总声音/SFX/后台声音，总音量/SFX设为1，静音音乐/环境/对话/错误/宠物/表情。重复on不覆盖原值；hide不改变检测或音频。off、面板关闭、死亡、PLAYER_LOGOUT恢复；ADDON_LOADED补充恢复旧快照。恢复失败原值保留重试，禁止覆盖未恢复快照。不修改音频输出设备、Windows音量或图形设置。AudioSettings.Tests.lua用Lua5.1验证两服。
- wowAuto.Audio.cs通过系统.NET Framework Add-Type加载，使用Windows Build20348+的ActivateAudioInterfaceAsync/进程回环，仅捕获目标PID及子进程。背景线程核对PID/StartTime/路径，不回退系统音频；GUI启动及消费信号仍核对客户端身份。开始建立独立监听，启动完成前禁止抛竿；失败停止本行并报告；停止/刷新/退出释放监听。禁止给真实游戏发送按键或采集游戏音频来验证。
- 工具栏音频勾选默认开启，只有全部任务停止可更改，不写入config.ini。设置中的最小/最大等待改为音频匹配成功后的随机收竿延迟，当前两服均300–600ms；取消音频时仍从变绿开始按同范围计时。音频确认绿色后登记独立钓鱼会话/35秒无信号超时，此时不登记Reel。匹配成功按当前任务MinimumMs/MaximumMs闭区间随机取整数毫秒，以成功时刻加延迟登记Reel，移除原超时，AudioReelPending标记待收竿、停止本轮音频判断；重复信号不得重采延迟。等待不占用ActiveKey，其他窗口继续；到期沿用原优先级及保持规则，停止/刷新/重启清空，成功收竿或重置等待清除标记。运行中范围设置只影响下次匹配，已登记Deadline/Event.Due不重算。状态框区分收竿等待及无信号超时，倒计时不更新时间戳。前1秒屏蔽抛竿声音并建立基线，峰值>=0.06、>=基线+0.025且>=基线*3才进入候选；纯峰值模式立即触发，模板模式匹配通过才触发，每会话一次。不宣称识别声音归属。
- 音频信号按任务引用/会话隔离，进入原Reel优先队列，遵守ReelHoldUntil和ItemHoldUntil。道具3秒期间解除所有音频监听的判断/清空未处理噪声，之后重新预热。收竿前绿色才下发，红色取消重抛，灰/未知停本行，黄色沿用背包规则。无信号35秒重抛不计循环，收竿成功计数及后续跳跃/强制抛竿/红转绿不变。焦点暂停保留信号队列。峰值显示变化不更新时间戳。
- Audio.Detector.Tests.ps1只编译并测试合成数据/结构；Audio.Engine.Tests.ps1测试纯调度及匹配后随机/固定延迟、范围更新/已登记截止不变、等待不阻塞其他窗口/跨35秒无信号超时及取消；UiTest额外运行Audio.UiTests.ps1，覆盖两服延迟/运行中设置、倒计时标签与时间戳、到期前不发键/保持不可抢占，所有监听和游戏操作模拟。Audio.Capture.Smoke.ps1仅监听自身无声测试PowerShell进程，允许PCM转换的2个最低有效位噪声，验证本机接口初始化和身份拒绝，不监听游戏或发送输入。部署后请用户/reload并重启wowAuto；真实无限服声音准确率需后续实测。
