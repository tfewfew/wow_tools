---
name: wow-tools
description: 维护titan时光服、forerver无限服的独立wow_tools插件合集及wowAuto前台脚本，验证并提交推送后按客户端同步插件和桌面源码快捷方式。
---

# wow_tools

源码仓库：`C:\code\wow_tools`，远端 `origin`。插件源码分开归档在 `addon/titan/wow_tools/`（时光服）和 `addon/forerver/wow_tools/`（无限服），保留用户指定的forerver拼写；不要恢复旧的addon/wow_tools或让两服互相引用源码。图形工具在 `tools/wowAuto/`（wowAuto.ps1、wowAuto.Engine.ps1、wowAuto.bat），使用说明在该目录 README.md。不要把游戏目录或桌面副本当作修改源。

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
- 不提交本机备份、游戏配置、SavedVariables或外部依赖。备份按titan/forerver分子目录；SavedVariables迁移只在各自客户端内进行，不跨服复制。

## 行为约定

- titan版归档保留原2.1.1源码和TOC。forerver版2.2.0按无限服1.60.1.70338的Blizzard导出源码943764493e6b16d63ded3ab304150d1f05e58b57移植；以后跟随对应分支源码核对API，不能仅改TOC号。
- forerver在Init.lua后加载Compatibility.lua：ItemLocation主手槽16及C_Item.GetItemID/GetItemInfoInstant识别鱼竿，C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand)返回列表，只接受有效Temporary附魔，排除Permanent/Imbue；失败或受限/不完整数据为unknown。UnitChannelInfo的技能ID在第8项，UnitCastingInfo在第9项；先用issecretvalue排除受限返回再比较/输出，受限施法使主色块灰色。注册WEAPON_ENCHANT_CHANGED并每0.1秒刷新。菜单使用MenuUtil.CreateContextMenu；画面模块移动FramerateFrame整体，不再依赖FramerateLabel全局。未提供的CVar继续禁用，禁止加载时自动改变图形设置。forever测试覆盖全TOC加载，不发送游戏按键。
- wowAuto目前仍只识别WowClassic.exe；此次插件移植不代表外部工具支持无限服Wow.exe。后续若适配外部工具，必须核对客户端路径/版本避免误选零售版同名Wow.exe。

- wow_tools 是唯一 TOC 插件，子目录 wowDetector 和 inner_graphic_config 分别保存模块；Init.lua 初始化 WoWTools.modules，Core.lua 统一小地图及右键菜单。图形模块来自本机 Inner_graphic_config 1.7.0，保留 /igc 和原有设置行为。同步先完整复制验证，再归档旧独立插件；首次复制账号旧 wowDetector.lua SavedVariables 为 wow_tools.lua，已有目标不覆盖。
- 小地图右键菜单分别切换两个子模块界面，/wowtools 打开菜单。小地图钓鱼图标左键打开面板并自动启动检测，再次点击停止检测并隐藏面板；右键菜单中的wowDetector及模块Show采用相同行为，面板关闭按钮停止检测并隐藏，拖动调整入口角度；panelHidden、minimapAngle 保存到 wowDetectorDB。show/hide命令仅控制显隐，不改变检测开关；隐藏时色块也隐藏；状态更新独立于面板可见性。show/hide 命令控制显隐，on 命令先显示面板。入口不依赖外部库。
- 泰坦时光服接口版本目前为 38002；wowDetector 面板创建时即隐藏，每次登录或重载重置 panelHidden=true，检测默认关闭，不恢复上次面板显示状态。小地图入口及 show/on 命令仍可打开。`/wowdetector` 是主命令，`/fishstate` 保留为兼容别名。
- 绿色表示钓鱼，红色表示非钓鱼，黄色表示随身普通背包空格为零，灰色表示关闭或数据未知。黄色优先于红绿。排除银行、材料及专用背包；不估算现有物品剩余堆叠容量。
- wowDetector 使用PLAYER_DEAD及UnitIsDeadOrGhost检测角色死亡/灵魂状态，优先停止监测、清空状态与计时、解除位置锁定并显示关闭状态；保留面板显隐，不改panelHidden。死亡时禁止启动，复活事件不得自动重启；进入世界及监测刷新补充检查。只重置插件，不宣称能直接停止外部wowAuto。
- “启动”按钮和 on 命令将色块中心对齐客户区中心、保存位置并锁定；关闭时解锁。无独立居中按钮，center 命令仍兼容。运行中不允许拖动或用 unlock 解锁；登录或重载默认关闭且解锁。
- wowAuto 的 autofish 标签页包含刷新进程、全部开始、全部停止按钮，按 `WowClassic.exe` 进程生成独立控制行，每行横向排列范围、开始/停止、使用钓鱼道具复选框、状态框。初始按钮锁定。刷新先停止所有任务并清空事件，再按PID和启动时间更新列表，保留存活行的范围和道具勾选，移除已退出行；复用PID不得继承状态或勾选。窗口宽度随新增列适配，屏幕容不下时列表允许滚动。
- 用户授权刷新扫描轮流切换游戏窗口到前台，约200ms后读取中心色，未识别最多重试到800ms。只有红/绿开放按钮，黄/灰/未知/切换失败保持锁定；刷新期间不允许自动按键或结束游戏。完成后尝试恢复原前台，任务需手动重新开始。
- 用户已授权运行时自动切换窗口。全部开始只将通过验证的行加入统一调度队列；只有调度目标在前台时发送按键。任务共享单调时钟，不能因切到后台取消收竿事件。
- 每行默认未启动，ms范围默认为9000–13000，最小/最大输入框箭头步长1000ms，允许1–3600000整数且下限不大于上限，运行时锁定该行输入。单行停止清除本行事件，全部停止/刷新/关闭窗口清空所有任务与事件。使用非阻塞定时器保持按钮响应。
- 红色窗口按随机300–600ms周期持续抛竿键直到变绿；相邻周期不同。绿色登记随机毫秒收竿事件，立即轮转下一窗口。已到期收竿优先于下竿和窗口切换，按截止时间/登记顺序处理，但不得抢占收竿后可配置的前台保持阶段。
- 工具栏在全部停止后显示进程检测数量，提供全局收竿保持输入0–60000ms，默认100，0表示不保持；修改从下次成功收竿生效，不缩短当前保持。启动窗口按内容和行数适配并居中，尺寸限制在屏幕可用区域内，超出高度的行滚动查看。
- 使用钓鱼道具复选框位于各进程行，默认关闭，可在启动前选择或运行中单独修改；全部开始沿用各行选项。停止/重启该行、刷新保留同一PID+启动时间的勾选，新进程或重启工具默认不勾选。工具栏的下一行仍提供全局抛竿/收竿/道具按键录入，默认0/=/-（主键盘单键，VK48/187/189），支持主键盘-（VK189）和=（VK187），可录入Ctrl/Shift/Alt组合，修改从下一次按键生效，工具重启恢复默认。NativeInput.PressChord负责发送配置键并释放修饰键。
- wowDetector新增鱼饵小色块，中心固定为原中心检测点右侧32个物理屏幕像素、大小12x12物理像素。UI单位每物理像素为768/GetPhysicalScreenSize返回的实际画面高度/panel:GetEffectiveScale()（与Blizzard PixelUtil换算一致），不能只除UI缩放。DISPLAY_SIZE_CHANGED、UI_SCALE_CHANGED和监测中每0.1秒刷新都重新定位；尺寸或缩放无效时隐藏小点并设为未知，有效后恢复，主色块坐标不变。titan使用GetInventoryItemLink(player,16)及GetItemInfoInstant确认主手为武器类2、鱼竿子类20，再以GetWeaponEnchantInfo主手临时附魔及剩余毫秒判断：蓝色有效、紫色缺失/过期、灰色关闭/死亡/非鱼竿/未知。水下诱鱼器及其他有效临时鱼饵附魔均算有效，永久附魔不算；不依赖普通UnitAura；forerver使用上述Compatibility.lua的新版接口。状态命令包含附魔、开关/显隐、画面像素尺寸及小点定位信息，死亡关闭重置小点。LureDetection.Tests.lua按UI单位*有效缩放*实际高度/768还原物理像素，覆盖窗口尺寸和UI缩放组合，不能把有效缩放误当完整像素换算。
- 道具调度改为附魔检测，移除固定600000ms和启动时无条件使用。UseItem属于任务State，不属于全局Scheduler；Add-WowAutoTask通过UseItem参数初始化，Set-WowAutoItemEnabled按Key仅修改对应活动任务。各行勾选/启动立即登记本行Item检查，Get-WowAutoWork仅为UseItem=true且Ready/Casting的行安排检查，不抢占Wait/Cooldown。适配层仅为勾选行在Item及Poll取色时读取右侧32像素点，未勾选行不检测、不因鱼饵未知暂停且不发送道具键。Complete-WowAutoItemCheck处理：有效解除InitialItemPending并跳过使用；缺失+红色请求道具；缺失+绿色先完成现有钓鱼；未知阻止该行抛竿、每1000ms重查并释放ActiveKey。已到期收竿优先于道具检查，其他行继续。成功发送仍设置全局ItemHoldUntil=完成时刻+3000ms，ItemDue同期重查且InitialItemPending保持，需确认附魔有效才恢复抛竿；缺失时至少5000ms后再次使用，失败发送500ms后重试且不新增保持。3秒内所有抛竿/收竿/取色及刷新切换暂停，到期事件排队，UI和停止按钮响应；取消任一行勾选不缩短保持，只解除对应行的后续附魔检查限制。道具不计循环、不重置钓鱼事件，黄色及焦点/身份规则沿用。各行ItemStatus仅在本行勾选时显示并参与状态时间戳。ItemDetection.Tests.ps1、ItemDetection.UiTests.ps1、ProcessItems.UiTests.ps1、KeyItem.UiTests.ps1、InputAdapter.Tests.ps1及addon/tests/LureDetection.Tests.lua仅模拟验证，不发送真实按键。
- 成功发送收竿键并释放按键后设置全局 ReelHoldUntil=完成时刻+配置保持时间；调度队列及刷新扫描在此之前均不切换窗口，到期事件排队等待。保持UI响应，可停止任务，不使用阻塞睡眠。从同一完成时刻计时max(1000ms,配置保持时间)再入下竿队列，保持包含在冷却内；发送失败不新增保持时间。
- 统一队列存储任务会话引用，停止/重启不得执行旧事件。灰/未知暂不按键并让出队列。只在窗口被调度到前台时检测黄色，不承诺后台持续取色。实时状态以[HH:mm:ss]显示状态更新时的本机时间戳，未启动、刷新、运行和停止均显示；基础消息保存在StatusMessage或State.Status，避免重复添加时间前缀。每行通过StatusSnapshot跟踪基础消息、Mode、Deadline、FocusRetryAt，道具等待使用ItemHoldUntil标识新阶段；变化时才更新StatusTimestamp。单纯倒计时变化或UI定时刷新不得更新时间戳。StatusTimestamp.UiTests.ps1使用模拟时钟验证稳定状态及各类倒计时保留时间戳，新状态/新事件刷新。
- 运行时切换失败、800ms内无法取得焦点、检测或发送按键时失去焦点，不停止任务；通过FocusRetryAt=失败时刻+30000ms暂停对应行并显示秒级重试倒计时，保留Mode、收竿事件、道具计时及抛竿标记，释放ActiveKey，其他行继续。Get-WowAutoWork跳过该行所有普通事件，重试到期返回独立FocusRetry动作；每次重试先验证PID/StartTime/ProcessName，恢复焦点后清除暂停继续原流程，失败再等30秒。到期收竿和道具仍先于焦点重试，重试先于普通抛竿，不能抢占收竿保持或道具3秒等待。进程退出、身份变化及其他执行异常仍停止该行；手动停止、全部停止、刷新及关闭清除重试，重启不得继承。刷新扫描失败行为保持锁定按钮、不自动启动。FocusRetry.Engine.Tests.ps1及FocusRetry.UiTests.ps1模拟验证边界、重复失败、恢复、事件保留、隔离、取消与身份校验。
- 成功收竿后设置CheckReelGreen；原冷却结束后的首次红/绿检测，绿先返回Jump发送单独空格（VK32，无修饰键），成功清除标记，下一轮询继续原强制抛竿流程；红清除标记并正常抛竿。灰/未知保留判断、黄色优先，失败可重试，每次收竿最多成功跳一次；不得跳过原保持及道具3秒等待。
- 成功收竿后设置任务 ForceNextCast，原冷却结束后首次红/绿均发送抛竿键；成功发送后通过 Complete-WowAutoCast 清除标记，恢复正常颜色轮询。发送失败保留标记；黄色处理和灰/未知不按键规则不变。新任务不继承标记，首次启动不强制抛竿。
- 成功收竿同时设置 AwaitingFishingTransition=true、SawIdle=false；新一轮必须先读到红色，再读到绿色才登记收竿事件，从确认绿色时计时。强制抛竿后残留绿色只按300–600ms轮询，不重复强制按键、不登记事件；检测到红色继续正常抛竿。上一轮红色不得沿用；首次启动绿色可直接进入等待的行为保留。
- 有效循环定义为已登记的收竿事件成功发送收竿键，一次事件只计一次；不等于确认钓获。计数存储在统一调度器的 CompletedCycles 中，按PID和启动时间对应的Key区分，停止/重启任务/刷新不清零；新游戏进程或重启工具从0计数。行内显示累计次数。
- 运行中黄色只有累计有效循环严格大于500（501起）才核对身份并通过Process.CloseMainWindow请求游戏正常退出。先停止该行、清空钓鱼事件并禁用开始；请求后登记独立pendingGameExits保护，30秒未退出才重新核对StartTime/ProcessName并对原Process实例Kill一次。正常请求失败但已确认身份并尝试关闭时同样计时；身份改变取消保护，不误杀复用PID。保护检查在主UI定时器独立执行，不阻塞其他任务。进程正常退出取消保护，强制结束失败仅报告，不无限重试；单行停止、全部停止、刷新和工具关闭取消待执行超时保护。请求被接受不代表已退出，不提前设置Exited。次数不足仍只停该行；刷新扫描不请求退出。GracefulExit.Tests.ps1使用模拟进程验证30秒边界、提前退出、阈值、失败和隔离，不关闭真实游戏。不要在部署时点击开始触发真实操作。
- `tools/wowAuto/tests/Engine.Tests.ps1` 验证纯队列调度。PreviewPath 参数渲染初始窗口；源码中的 UiTest 参数执行 Layout.UiTests.ps1、Refresh.UiTests.ps1 和 Scheduler.UiTests.ps1，以模拟进程验证扫描、按钮、轮转和到期抢占，不调用真实切换/取色/按键/结束进程。
