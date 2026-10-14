---
name: wow-tools
description: 维护titan时光服、forerver无限服的独立wow_tools插件合集及wowAuto前台脚本，验证并提交推送后按客户端同步插件和桌面源码快捷方式。
---

# wow_tools

源码仓库：`C:\code\wow_tools`，远端 `origin`。插件源码分开归档在 `addon/titan/wow_tools/`（时光服）和 `addon/forerver/wow_tools/`（无限服），保留用户指定的forerver拼写；不要恢复旧的addon/wow_tools或让两服互相引用源码。图形工具在 `tools/wowAuto/`（wowAuto.ps1、wowAuto.Engine.ps1、wowAuto.Audio.cs、wowAuto.Recordings.ps1、wowAuto.Unified.ps1、wowAuto.bat及autoFight各模块），使用说明在该目录 README.md。不要把游戏目录或桌面副本当作修改源。

## 修改与同步顺序

1. 检查 Git 状态、当前分支及远端，保留无关改动。在仓库修改源码及必要说明。
2. 检查PowerShell及Lua语法；修改内嵌C#时只编译，不运行主循环。验证受影响客户端：titan用addon/tests/LureDetection.Tests.lua，forerver用addon/tests/ForeverCompatibility.Tests.lua；两者Lua5.1模拟运行。同步配置用skills/wow-tools/tests/ClientProfiles.Tests.ps1验证。不要为测试发送真实按键或关闭游戏。
3. 每次修改完成都必须创建 Git 提交并推送当前分支到 `origin`，包括代码、配置、文档和维护约定；不能只修改本地或只同步副本。用户已授权此流程，无需逐次索要许可。不强推。推送失败时保留本地提交并报告原因，不同步安装副本，修复后重试。
4. 推送成功后运行 `skills/wow-tools/scripts/sync-local.ps1`，默认Flavor=all分别同步两服。也可显式-Flavor titan/forerver；GameRoot覆盖必须同时选择一服，all通过TitanGameRoot/ForerverGameRoot各自覆盖。client-profiles.ps1提供独立源码和目标映射，写入前核对所有所选客户端可执行文件的3.80./1.60.版本前缀及源码TOC接口号，拒绝混用同一目录或写入零售版。它核对干净工作区和远端分支提交，再同步插件并校验文件哈希，通过install-desktop-shortcut.ps1更新桌面源码快捷方式并归档旧运行副本。
5. 报告提交、推送和同步结果，提醒用户停止旧脚本并重启桌面 `wowAuto` 快捷方式；插件变更需 `/reload`，改名首次安装可能需要完全重启游戏。

## 安装目标

- titan游戏：`C:\Program Files (x86)\World of Warcraft\_classic_titan_\Interface\AddOns\wow_tools`，客户端WowClassic.exe 3.80.2，接口38002。
- forerver游戏：`C:\Program Files (x86)\World of Warcraft\_cn_beta_\Interface\AddOns\wow_tools`，客户端Wow.exe 1.60.1.70338，接口16001。
- 桌面：通过 Windows Desktop 特殊文件夹解析，仅创建 `wowAuto.lnk`，直接指向源码 tools/wowAuto/wowAuto.bat，WorkingDirectory 设置为该源码目录；不复制运行文件到桌面。
- 同步脚本将旧 `FishingState`、`wowDetector`、`Inner_graphic_config` 插件移到仓库忽略目录 `.local-backups`；快捷方式验证成功后，将桌面旧 wowAuto 三个运行文件及 wow-foreground-loop 两个入口移入该次备份的 Desktop 子目录。只处理确切文件名，不广泛清理桌面；移动前检查绝对路径，源码目录需保留完整运行文件。
- 不提交本机备份、游戏配置、SavedVariables或外部依赖。tools/wowAuto/config.ini按用户要求纳入Git，属于工具共享配置，不受此条排除；保留用户在设置窗口保存的值，后续维护时检查其改动。备份按titan/forerver分子目录；SavedVariables迁移只在各自客户端内进行，不跨服复制。

## 行为约定

- titan版基于原2.1.1独立维护，当前2.1.23/接口38002。forerver版当前2.2.22/接口16001按无限服1.60.1.70338的Blizzard导出源码943764493e6b16d63ded3ab304150d1f05e58b57移植；以后跟随对应分支源码核对API，不能仅改TOC号。
- forerver在Init.lua后加载Compatibility.lua：ItemLocation主手槽16及C_Item.GetItemID/GetItemInfoInstant识别鱼竿，C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand)返回列表，只接受有效Temporary附魔，排除Permanent/Imbue；失败或受限/不完整数据为unknown。UnitChannelInfo的技能ID在第8项，绿色只认钓鱼引导；先用issecretvalue排除受限返回再比较/输出，受限引导使主色块灰色。注册WEAPON_ENCHANT_CHANGED并每0.1秒刷新。菜单使用MenuUtil.CreateContextMenu；画面模块移动FramerateFrame整体，不再依赖FramerateLabel全局。未提供的CVar继续禁用，禁止加载时自动改变图形设置。forever测试覆盖全TOC加载，不发送游戏按键。
- wowAuto同时识别时光服_classic_titan_/WowClassic.exe 3.80.和无限服_cn_beta_/Wow.exe 1.60.，允许游戏根目录位于其他盘符，但产品目录名须匹配。GetClientFlavor同时核对可执行文件名、父目录与构建前缀；未知/无法读取/零售服不加入列表。每行Client保存Flavor、Label、ExecutablePath；启动、取色、焦点切换、发键及正常/超时退出均核对PID、StartTime、路径与客户端身份。C#方法接收启动Ticks和预期路径，不能退回只按Wow进程名操作。

- wow_tools 是唯一 TOC 插件，子目录 wowDetector 和 inner_graphic_config 分别保存模块；Init.lua 初始化 WoWTools.modules，Core.lua 统一小地图及右键菜单。图形模块来自本机 Inner_graphic_config 1.7.0，保留 /igc 和原有设置行为。同步先完整复制验证，再归档旧独立插件；首次复制账号旧 wowDetector.lua SavedVariables 为 wow_tools.lua，已有目标不覆盖。
- 小地图右键菜单分别切换两个子模块界面，/wowtools 打开菜单。小地图钓鱼图标左键打开面板并自动启动检测，再次点击停止检测并隐藏面板；右键菜单中的wowDetector及模块Show采用相同行为，面板关闭按钮停止检测并隐藏，拖动调整入口角度；panelHidden、minimapAngle 保存到 wowDetectorDB。show/hide命令仅控制显隐，不改变检测开关；隐藏时色块也隐藏；状态更新独立于面板可见性。show/hide 命令控制显隐，on 命令先显示面板。入口不依赖外部库。
- 泰坦时光服接口版本目前为 38002；wowDetector 面板创建时即隐藏，每次登录或重载重置 panelHidden=true，检测默认关闭，不恢复上次面板显示状态。小地图入口及 show/on 命令仍可打开。`/wowdetector` 是主命令，`/fishstate` 保留为兼容别名。
- 绿色表示钓鱼，红色表示非钓鱼，黄色表示随身普通背包空格为零，灰色表示关闭或数据未知。黄色优先于红绿。排除银行、材料及专用背包；不估算现有物品剩余堆叠容量。
- titan 2.1.3及forerver 2.2.2绿色须同时满足钓鱼引导及当前可交互软目标：UnitGUID(softinteract)有值且UnitIsInteractable(softinteract)为真，不依赖可能排除GameObject的UnitExists。抛竿施法及无引导显示红色；引导中无交互目标为红色“等待交互”，接口缺失/失败/受限为灰色；黄色仍优先。PLAYER_SOFT_INTERACT_CHANGED及时刷新并每0.1秒补查，不缓存上一轮成功；不比较事件中的受限GUID参数。用户测试前须启用游戏交互键，不自动改变softTargetInteract；status输出可读目标状态/名称/GUID/CVar。不限定目标为自己的鱼漂、不宣称咬钩或扫描所有附近对象；forerver使用独立Compatibility.lua保留受限读取保护。LureDetection.Tests.lua及ForeverCompatibility.Tests.lua分别模拟覆盖组合条件、目标出现/消失、轮询、未知及背包/死亡/关闭优先级。
- wowDetector 使用PLAYER_DEAD及UnitIsDeadOrGhost检测角色死亡/灵魂状态，优先停止监测、清空状态与计时、解除位置锁定并显示关闭状态；保留面板显隐，不改panelHidden。死亡时禁止启动，复活事件不得自动重启；进入世界及监测刷新补充检查。只重置插件，不宣称能直接停止外部wowAuto。
- “启动”按钮和 on 命令将色块中心对齐客户区中心、保存位置并锁定；关闭时解锁。无独立居中按钮，center 命令仍兼容。运行中不允许拖动或用 unlock 解锁；登录或重载默认关闭且解锁。
- wowAuto主界面及设置采用炭灰及低饱和度灰蓝：背景RGB58/58/58、行/工具栏面RGB72/72/72、输入及状态框RGB50/50/50、所有文字RGB255/255/255（含禁用按钮/复选框及设置错误提示）、普通按钮RGB86/86/86、开始/保存强调按钮RGB88/100/112。主窗口及设置使用DimForm，通过DwmSetWindowAttribute按窗口设置系统标题栏黑底白字（20为深色模式、35为黑色标题栏、36为白色文字），在OnHandleCreated中处理句柄重建；不修改Windows全局主题，不移除原生标题栏，保留拖动/缩放及原有窗口按钮。35/36由Windows11支持，旧系统不支持时仍可打开工具并保留系统标题栏。正文字体12pt、页脚11pt、标题23pt；行高190、状态框82，统一设置窗口1000x882以完整显示放大文字。DimTabControl保留原TabControl页选择及布局，自绘黑色标签栏背景，选中进程任务标签采用低饱和度暗蓝RGB54/78/98区分，保留白字；DimButton/DimCheckBox保留原按钮及复选框语义，补绘禁用状态的白字，禁止为改变文字颜色而放开禁用权限；按钮、输入框、分组文字及错误提示统一适配深灰背景，避免恢复大面积纯白。KeyItem.UiTests.ps1覆盖设置内输入框/实际KeyDown事件、草稿隔离、取消/校验失败/保存/重新打开及已配置按键的模拟下发；预览检查主界面和设置布局，不发送真实按键。
- wowAuto 的统一进程任务页包含刷新进程、全部开始、全部停止按钮，按已识别的两服进程生成独立控制行，每行包含角色编排、进程信息、开始/停止和状态框，不再显示模式标签或钓鱼 / 战斗下拉框；进程行不显示手动移动方向按钮，移除逐进程范围输入。PID后显示时光服/无限服及窗口位置。初始按钮锁定。刷新先停止所有任务并清空事件，再按PID和启动时间更新列表，保留存活行的道具勾选，等待范围属于版本配置，移除已退出行；复用PID不得继承状态、模式或勾选。窗口宽度随新增列适配，屏幕容不下时列表允许滚动。
- 用户授权刷新扫描轮流切换游戏窗口到前台，约200ms后核对前台并发送所选模式的开启命令（fish为/wowdetector on、fight为/fightdetector on），再等待约200ms读取中心色，未识别有限重试。钓鱼红/绿或战斗有效主色及职业才开放按钮，黄/灰/未知/切换或命令失败保持锁定；刷新只发送开启命令，不执行任务按键或结束游戏。完成后尝试恢复原前台，任务需手动重新开始。
- 用户已授权运行时自动切换窗口。全部开始只将通过验证的行加入统一调度队列；只有调度目标在前台时发送按键。任务共享单调时钟，不能因切到后台取消收竿事件。
- 每行默认未启动。设置窗口统一配置两服“收杆延迟区间配置（ms）”，下限与上限输入框用-连接（代码默认300–600ms、步长100ms、范围1–3600000）、音频门槛（50–100整数）、全局焦点重试（1000–3600000ms、步长1000）、收竿保持及三个快捷键。所有可配置项持久化到tools/wowAuto/config.ini，18个固定键为TitanMinimumMs/TitanMaximumMs/ForerverMinimumMs/ForerverMaximumMs/FocusRetryIntervalMs/TitanAudioThresholdPercent/ForerverAudioThresholdPercent/TitanAudioTimeoutMs/ForerverAudioTimeoutMs/TitanAudioRecordingId/ForerverAudioRecordingId/ReelHoldMs/CastKey/ReelKey/ItemKey/AudioDetectionEnabled/StatusLogLimit/JumpEveryCycles，另有UseItem_<PID>_<StartTicks>=0/1。快捷键用New-KeyBinding及ConvertFrom-KeyBindingText生成和解析规范文本，支持组合键与0/=/-；开关只接受0/1。Set-VersionWaitRanges统一验证全部计时、门槛、按键及勾选标识后原子写入，再应用内存及界面；File.Replace无备份参数使用Language.NullString::Value，避免PS5.1空路径转换。键名不区分大小写、允许空行/整行注释；拒绝重复/未知/分节/非法值及仅缺部分分组键。兼容旧5/7/12/14/16项：StatusLogLimit可省略并沿用当前值（启动默认50），读取不重写、下次保存补全；录音序号两项可同时省略并沿用当前选择（启动默认titan2/forerver1），无咬钩保护两项可同时省略并沿用当前值（启动默认35000ms），音频门槛两项、新增偏好五项各自可全部省略并沿用当前默认，读取不重写、下次保存补全。启动缺省保持100ms、0/=/-、音频开启、道具未勾选。窗口字段取消/关闭/校验或写入失败不应用，主界面勾选立即保存，失败回滚并提示。config.ini纳入Git，UI不自动执行Git。已有Deadline/Event.Due/FocusRetryAt/ReelHoldUntil/ItemHoldUntil不重算；弹窗期间暂停自动切换/按键及刷新，保留队列，关闭后继续。新保存值用于下一次操作；停止/刷新/关闭继续清理原任务和事件。
- 红色窗口按随机300–600ms周期持续抛竿键直到变绿；相邻周期不同。定时模式绿色登记随机毫秒收竿事件，立即轮转下一窗口。已到期收竿优先于下竿和窗口切换，按截止时间/登记顺序处理，但不得抢占收竿后可配置的前台保持阶段。
- 工具栏在全部停止后显示进程检测数量；收竿后保持输入统一移到设置窗口，0–60000ms、默认100、步长1ms，0表示不保持。编辑仅修改弹窗草稿，全部字段验证并成功保存全部INI配置后才通过Set-WowAutoHoldDuration应用；取消/关闭/校验或保存失败不得应用。保持从下次成功收竿生效，不缩短当前ReelHoldUntil；保持时间持久保存为ReelHoldMs，重启读取。ClientSettings.UiTests.ps1覆盖草稿/保存/重新打开/取消/校验及文件写入失败隔离、现有保持截止不变；Layout.UiTests.ps1核对工具栏不再保留数值输入。启动窗口按内容和行数适配并居中，尺寸限制在屏幕可用区域内，超出高度的行滚动查看。
- 使用钓鱼道具复选框位于各进程行，默认关闭，可在启动前选择或运行中单独修改；全部开始沿用各行选项。停止/重启该行、刷新保留同一PID+启动时间的勾选，新游戏进程默认不勾选，重启工具恢复同一PID+启动时间的已保存勾选。三个全局抛竿/收竿/道具按键录入统一放到设置窗口的快捷键分组，主工具栏不保留按键录入行并缩短高度。默认0/=/-（主键盘单键，VK48/187/189），支持主键盘-（VK189）和=（VK187），可录入Ctrl/Shift/Alt组合。New-KeyBinding生成映射；Set-KeyBinding只写入弹窗独立草稿，计时/门槛验证并保存成功后一次应用三个映射，取消/关闭/校验或保存失败不得应用草稿。重新打开设置显示当前分配，保存从下一次按键生效，按键规范文本持久保存到CastKey/ReelKey/ItemKey，重启读取；UseItem_<PID>_<StartTicks>保存各行勾选，新PID/启动时间不继承。NativeInput.PressChord负责发送配置键并释放修饰键。
- wowDetector新增鱼饵小色块，中心固定为原中心检测点右侧32个物理屏幕像素、大小12x12物理像素。UI单位每物理像素为768/GetPhysicalScreenSize返回的实际画面高度/panel:GetEffectiveScale()（与Blizzard PixelUtil换算一致），不能只除UI缩放。DISPLAY_SIZE_CHANGED、UI_SCALE_CHANGED和监测中每0.1秒刷新都重新定位；尺寸或缩放无效时隐藏小点并设为未知，有效后恢复，主色块坐标不变。titan使用GetInventoryItemLink(player,16)及GetItemInfoInstant确认主手为武器类2、鱼竿子类20，再以GetWeaponEnchantInfo主手临时附魔及剩余毫秒判断：蓝色有效、紫色缺失/过期、灰色关闭/死亡/非鱼竿/未知。水下诱鱼器及其他有效临时鱼饵附魔均算有效，永久附魔不算；不依赖普通UnitAura；forerver使用上述Compatibility.lua的新版接口。状态命令包含附魔、开关/显隐、画面像素尺寸及小点定位信息，死亡关闭重置小点。LureDetection.Tests.lua按UI单位*有效缩放*实际高度/768还原物理像素，覆盖窗口尺寸和UI缩放组合，不能把有效缩放误当完整像素换算。
- UseItem属于钓鱼任务State；勾选后先查右侧鱼饵点：有效附魔跳过使用，缺失+红色请求道具，缺失+绿色先完成收竿，未知每1000ms重查并暂缓该行抛竿。成功发送道具键后保持全局ItemHoldUntil=完成时刻+3000ms，保持结束复查附魔；确认有效后继续监测，以后附魔失效可再次补用。每次尝试从首次发键（含发送失败）起5秒内确认有效附魔；已成功发键时不重复发键，发送失败时每500ms在期限内重试且不新增保持。到期仍未确认则设置ItemDetectionDisabled，仅关闭当前任务的道具检测并继续钓鱼，保留槽位勾选；重新开始任务、重新进入槽位或关闭再开启勾选重置检测。到期收竿优先，其他行继续；3秒保持期间到期事件排队、UI及停止按钮响应，取消勾选不缩短已登记保持。道具不计循环、不重置钓鱼事件，黄色及焦点/身份规则沿用。ItemDetection.Tests.ps1、ItemDetection.UiTests.ps1、ProcessItems.UiTests.ps1、KeyItem.UiTests.ps1、InputAdapter.Tests.ps1仅模拟验证，不发送真实按键。
- 成功发送收竿键并释放按键后设置全局 ReelHoldUntil=完成时刻+配置保持时间；调度队列及刷新扫描在此之前均不切换窗口，到期事件排队等待。保持UI响应，可停止任务，不使用阻塞睡眠。从同一完成时刻计时max(1000ms,配置保持时间)再入下竿队列，保持包含在冷却内；发送失败不新增保持时间。
- 统一队列存储任务会话引用，停止/重启不得执行旧事件。灰/未知暂不按键并让出队列。只在窗口被调度到前台时检测黄色，不承诺后台持续取色。实时状态按最新在上显示每进程最近日志，默认50条。设置“日志保留条数”支持1–1000整数、步长1，以StatusLogLimit持久保存；缺省兼容旧INI，启动默认50。StatusHistory为每行独立有界列表，按状态变化/新事件条数计数，不按文本行数计数；同一PID+启动时间行停止/重启/刷新保留历史，新行不得继承，工具重启清空内存历史。基础消息保存在StatusMessage或State.Status；StatusSnapshot跟踪基础消息、Mode、Deadline、FocusRetryAt、ReelDelayMs，道具等待使用ItemHoldUntil标识新阶段。变化时更新StatusTimestamp并追加[HH:mm:ss]事件快照，旧记录不修改；CurrentStatusText仅保存最新条目，实时倒计时/音频指标更新不得增加记录或更新时间戳。ReelDelayMs从实际采样记录，不从剩余时间/新范围反推，停止、新音频等待、超时重抛及成功收竿清零。减少条数仅在成功保存后立即裁剪最旧日志，增大不恢复已丢弃项，取消/校验或写入失败不应用及不裁剪。DimStatusLog使用仅面向自身TextBox句柄的消息保留滚动位置和选区，MaxLength=0；内容未改变不重新渲染。StatusTimestamp.UiTests.ps1及StatusLog.UiTests.ps1模拟验证时间戳、旧条目/当前指标、条数裁剪/隔离、实际音频与定时延迟、设置草稿/重复保存/重载/失败/非法重复值/旧16项INI与源码配置隔离，不监听音频或操作真实游戏。
- 运行时切换失败、800ms内无法取得焦点、检测或发送按键时失去焦点，不停止任务；通过FocusRetryAt=失败时刻+Scheduler.FocusRetryIntervalMs暂停对应行并显示秒级重试倒计时，保留Mode、收竿事件、道具计时及抛竿标记，释放ActiveKey，其他行继续。Get-WowAutoWork跳过该行所有普通事件，重试到期返回独立FocusRetry动作；每次重试先验证PID/StartTime及客户端路径/版本身份，恢复焦点后清除暂停继续原流程，失败后按当前配置重新计时。保存新间隔不重算已登记的FocusRetryAt；基础状态文字不写死30秒，行内倒计时仍根据原截止时间显示。到期收竿和道具仍先于焦点重试，重试先于普通抛竿，不能抢占收竿保持或道具3秒等待。进程退出、身份变化及其他执行异常仍停止该行；手动停止、全部停止、刷新及关闭清除重试，重启不得继承。刷新扫描失败行为保持锁定按钮、不自动启动。FocusRetry.Engine.Tests.ps1及FocusRetry.UiTests.ps1模拟验证边界、重复失败、恢复、事件保留、隔离、取消与身份校验。
- 成功收竿后设置CheckReelGreen；原冷却结束后的首次红/绿检测，绿先返回Jump发送单独空格（VK32，无修饰键），成功清除标记，下一轮询继续原强制抛竿流程；红清除标记并正常抛竿。灰/未知保留判断、黄色优先，失败可重试，每次收竿最多成功跳一次；不得跳过原保持及道具3秒等待。
- 成功收竿后设置任务 ForceNextCast，原冷却结束后首次红/绿均发送抛竿键；成功发送后通过 Complete-WowAutoCast 清除标记，恢复正常颜色轮询。发送失败保留标记；黄色处理和灰/未知不按键规则不变。新任务不继承标记，首次启动不强制抛竿。
- 成功收竿同时设置 AwaitingFishingTransition=true、SawIdle=false；新一轮必须先读到红色，再读到绿色才登记收竿事件，从确认绿色时计时。强制抛竿后残留绿色只按300–600ms轮询，不重复强制按键、不登记事件；检测到红色继续正常抛竿。上一轮红色不得沿用；首次启动绿色可直接进入等待的行为保留。
- 有效循环定义为已登记的收竿事件成功发送收竿键，一次事件只计一次；不等于确认钓获。计数存储在统一调度器的 CompletedCycles 中，按PID和启动时间对应的Key区分，停止/重启任务/刷新不清零；新游戏进程或重启工具从0计数。行内显示累计次数。
- 运行中钓鱼黄色表示当前角色普通背包已满，与有效收竿次数无关。若本进程有角色编排，把当前角色名加入本次运行的跳过列表（相同角色配置多个槽位时一并跳过），立即停止该槽任务并排队切换下一可用角色；全局定时轮换也必须跳过这些名字。此列表仅在本次运行的进程编排内，不改写已保存计划；手动停止 / 刷新后重新开始会清空。若全部配置角色都已跳过，则停止该进程任务并通过Process.CloseMainWindow请求原游戏进程正常退出；没有角色编排的独立钓鱼任务只停止本行、保留进程。登录后任务开启前检测到黄色也采用同一规则，不等待超时；战斗检测不报告背包状态。退出请求先登记pendingGameExits，防止旧排队动作关闭新任务；30秒未退出才重新核对StartTime及客户端路径/版本身份并对原Process实例Kill一次。正常请求失败但已确认身份并尝试关闭时同样计时；身份改变取消保护，不误杀复用PID。停止、刷新及关闭工具取消保护。GracefulExit.Tests.ps1和Rotation.UiTests.ps1只用模拟进程验证，不关闭真实游戏。
- `tools/wowAuto/tests/Engine.Tests.ps1` 验证纯队列调度。PreviewPath 参数渲染初始窗口；源码中的 UiTest 参数执行 Layout.UiTests.ps1、Refresh.UiTests.ps1 和 Scheduler.UiTests.ps1，以模拟进程验证扫描、按钮、轮转和到期抢占，不调用真实切换/取色/按键/结束进程。

- 窗口位置以窗口中心相对主要所在显示器划分四象限；中心在屏幕中点宽高各10%范围内为居中，最小化/读取失败分别标识最小化/位置未知。ReadWindowPosition在同一DPI上下文读取窗口及显示器物理坐标，支持负坐标显示器；独立1000ms只读定时器更新Row.Position和进程标签，不切换窗口/取色/发键，不改变状态时间戳。ClientIdentity.Tests.ps1仅调用生产C#纯函数；ClientSettings.UiTests.ps1在UiTest内模拟两服队列、统一设置、计时不变、编辑暂停、位置更新、无限服焦点和退出保护。UiTest设置文件使用独立临时.ini路径并清理，校验源码config.ini哈希未改变，不能写用户真实配置；覆盖INI重复保存、注释/大小写/BOM、重复/缺失/未知键及非法范围、文件锁定时不部分应用。

## 音频咬钩检测及设置恢复

- wowAuto不提供录音、WAV导入/导出或制样界面；设置支持试听已保留的录音。ProcessCapture仅实时监听，在内存中保留短帧用于匹配，不保存音频。audio-features/titan-01.feature、titan-02.feature及forerver.feature保存经过校准的数值特征，按版本独立加载；缺失/无效时阻止对应行启动，不隐式退回纯峰值。保留config.ini原五项计时值，新增两项音频门槛见下面约定；audio-samples目录继续忽略并保留本地完整WAV；设置试听只读它们，匹配只读对应数值特征。
- 用户已通知开始，无限服三分钟采集已完成：.local-backups/audio-calibration-3min-pending/forerver-raw.wav，44.1kHz PCM16单声道、7938000点/180秒，及音频采样时间轴、中心色块时间线。目录名保留pending但内容已完成；不得自动续录，每次新采集仍需用户通知。用户确认主要等引导结束再抛竿，部分背景时段缺少颜色标签，不能把候选视作已确认钓获。工具只录身份核对后的目标PID并观察色块，不发送按键、不切换窗口，wowAuto没有录制入口。原始录音/候选WAV/分析及临时工具均留本机不上传；只提交数值特征、实现及验证说明，不把样本变换当多轮实测，不将一服特征冒充另一服。
- 用户本次明确要求匹配门槛可设置，覆盖旧约定“INI只含五项”的限制：新增TitanAudioThresholdPercent/ForerverAudioThresholdPercent，两服默认86、50–100整数百分比、步长1；设置弹窗每服行加入音频门槛。原五项计时键保留，四项等待值按后续用户授权改为两服300–600ms，焦点重试值保留。两音频键同时省略时兼容旧五键文件、沿用当前门槛（启动86）且不重写；仅缺一项拒绝。保存统一验证全部配置、原子重写，保存失败/取消不部分应用。实际匹配使用设置门槛，.feature的Threshold仅推荐；启动及活跃TemplateMode监听按Flavor配置，ProcessCapture.SetMinimumSimilarity在锁内更新，保留候选/预热/音频会话/已有信号/队列；从下次比较生效。行内显示分数与门槛，不刷新状态时间戳。不因低门槛宣称准确率提升，不能将门槛变化伪称已经完成多轮校准。
- 模板模式通过原音量门槛后，比对24个整体对数频带（512点FFT）、8段×24频带的时序频谱及16段音量包络；三组各自归一化，权重35%/50%/15%，保留先后顺序。特征文件格式2/11025Hz/11025样本，包含SpectrumBands=24/TimeSlices=8/EnvelopeBins=16、门槛0.5–1及1–8组232维变体；拒绝格式1，不能将旧32维数据直接迁移。候选保留200ms历史并收集约一秒后续帧；对齐取开头600ms内最强10ms帧向前最多300ms寻找起点、保留80ms引入帧，完整一秒才比较，不静音补尾。候选先收集1.2秒（含200ms历史），若该固定起点的尾部不足，保留候选及其目标长度继续收集，最多1.6秒，不提前以零分拒绝缓慢起伏的声音。三个±256点时间偏差比较取最高分，约1–1.4秒判断延迟；仅通过后消耗本轮信号，拒绝150ms后继续监听。会话切换及道具等待清空旧候选，实时指标不更新时间戳。不宣称能区分其他玩家播放的同一音效或保证排除全部干扰。
- 当前forerver.feature已替换旧单片段为三分钟录音的共同特征：第1.706/68.444/124.547秒的三段起点对齐后，对232维整体频谱/时序频谱/包络分别求平均并归一化，单个Template；44.100/97.419/179.193秒三个其他轮次片段保留验证、不参与准备。仍Status=trial，推荐Threshold=0.90，config.ini实际门槛保留用户已保存值。完整录音按钓鱼区间生产回放在86/90门槛下各接受一次，分数0.930455/0.922942/0.954749/0.958652/0.972035/0.970672；保留第二、第四段改变包边界/大小最低0.914497仍通过，五个抛竿初始区间及153–158秒其他声音区间无误接受，后者0.762079被拒绝。仅一次会话候选验证，不称跨场景准确率；相似度高的弱背景声仍由音量/基线及绿色后一秒预热筛除，不能省略这些门槛。Status允许trial/verified、省略按trial；状态框显示试用匹配，不因指标更新时间戳。两服特征独立，不套用另一服数据。
- 时光服于2026-10-11用户明确通知开始后完成独立180秒采集：.local-backups/audio-calibration-titan-3min-20261011-223629/titan-raw.wav，右侧PID6752、StartTimeTicks639273547296738508、客户端3.80.2.70177，7938000点44.1kHz PCM16单声道，完整色块时间线包含10轮及1轮未结束。titan.feature使用9.029/24.385/40.029秒三段对齐后的232维特征分组求平均归一化，单个Template；另外58.697/76.416/98.476/114.310/132.589/147.076/166.581秒七轮保留验证。86%/90%生产回放10轮各触发一次，末轮无信号；七轮改变包边界/大小最低0.965717，11个初始区间及25个非钓鱼候选无误接受，负例最高相似度0.805686。仍Status=trial、推荐90%，config.ini用户门槛86%不变；仅单次会话离线候选验证，等待实际钓获反馈。录音已结束，不自动续录；本地工具已固定目标身份并禁止覆盖输出，重新录制须新准备和用户通知。
- Audio.Template.Tests.ps1使用合成音频验证归一化、相同频谱换序/尾段缺失/短窗口拒绝/小幅对齐、迟到强峰的有界补帧/实时门槛、拒绝干扰后继续监听、去重/预热/重置及数值文件/变体/非法与旧格式数据；UiTest追加Audio.Features.UiTests.ps1验证没有录制UI/API、两服独立特征、缺失/无效门槛及时间戳。Audio.Capture.Smoke.ps1仅实时监听自身无声PowerShell进程，不录音、不采集游戏。实际长录音需等待用户通知。
- 两服独立的wowDetector/Audio.lua在检测模块前加载。仅从关闭切到开启时保存支持的音频CVar到wowDetectorDB.audioSnapshot，开启总声音/SFX/后台声音，总音量/SFX设为1，静音音乐/环境/对话/错误/宠物/表情。重复on不覆盖原值；hide不改变检测或音频。off、面板关闭、死亡、PLAYER_LOGOUT恢复；ADDON_LOADED补充恢复旧快照。恢复失败原值保留重试，禁止覆盖未恢复快照。不修改音频输出设备、Windows音量或图形设置。AudioSettings.Tests.lua用Lua5.1验证两服。
- wowAuto.Audio.cs通过系统.NET Framework Add-Type加载，使用Windows Build20348+的ActivateAudioInterfaceAsync/进程回环，仅捕获目标PID及子进程。背景线程核对PID/StartTime/路径，不回退系统音频；GUI启动及消费信号仍核对客户端身份。开始建立独立监听，启动完成前禁止抛竿；失败停止本行并报告；停止/刷新/退出释放监听。禁止给真实游戏发送按键或采集游戏音频来验证。
- 工具栏音频勾选读取AudioDetectionEnabled（首次默认开启），只有全部任务停止可更改，勾选变化立即原子保存，失败回滚并提示。设置中的收杆延迟区间用于音频匹配成功后的随机收竿延迟，代码默认两服均300–600ms，实际以INI为准；取消音频时仍从变绿开始按同范围计时。音频确认绿色后登记独立钓鱼会话/对应版本配置的无咬钩保护超时，此时不登记Reel。匹配成功按当前任务MinimumMs/MaximumMs闭区间随机取整数毫秒，以成功时刻加延迟登记Reel，移除原超时，AudioReelPending标记待收竿、ReelDelayMs保存实际随机值并在状态框显示“当前随机延迟：N ms”、停止本轮音频判断；重复信号不得重采延迟。等待不占用ActiveKey，其他窗口继续；到期沿用原优先级及保持规则，停止/刷新/重启清空，成功收竿或重置等待清除标记。运行中范围设置只影响下次匹配，已登记Deadline/Event.Due不重算。状态框区分收竿等待及无信号超时，倒计时不更新时间戳。前1秒屏蔽抛竿声音并建立基线，峰值>=0.06、>=基线+0.025且>=基线*3才进入候选；纯峰值模式立即触发，模板模式匹配通过才触发，每会话一次。不宣称识别声音归属。
- 音频信号按任务引用/会话隔离，进入原Reel优先队列，遵守ReelHoldUntil和ItemHoldUntil。道具3秒期间解除所有音频监听的判断/清空未处理噪声，之后重新预热。收竿前绿色才下发，红色取消重抛，灰/未知停本行，黄色沿用背包规则。达到本轮无咬钩保护截止时间重抛不计循环，收竿成功计数及后续跳跃/强制抛竿/红转绿不变。焦点暂停保留信号队列。峰值显示变化不更新时间戳。
- Audio.Detector.Tests.ps1只编译并测试合成数据/结构；Audio.Engine.Tests.ps1测试纯调度及匹配后随机/固定延迟、范围更新/已登记截止不变、等待不阻塞其他窗口/跨35秒无信号超时及取消；UiTest额外运行Audio.UiTests.ps1，覆盖两服延迟/运行中设置、倒计时标签与时间戳、到期前不发键/保持不可抢占，所有监听和游戏操作模拟。Audio.Capture.Smoke.ps1仅监听自身无声测试PowerShell进程，允许PCM转换的2个最低有效位噪声，验证本机接口初始化和身份拒绝，不监听游戏或发送输入。部署后请用户/reload并重启wowAuto；真实无限服声音准确率需后续实测。


- 全部偏好持久化由Preferences.UiTests.ps1模拟验证：UI保存、全部受支持按键/组合键文本往返、启动读回保持/按键/音频/进程选择、行重建及PID复用隔离、文件锁定时checkbox及弹窗不部分应用、非法/部分缺失/重复记录拒绝、旧5/7项兼容及只读加载。测试独立临时INI，禁止写用户源配置。Sync-PreferenceControls使用updatingPreferenceControls避免程序恢复界面时重复写文件，恢复选择不得自动启动游戏任务。
- 两服设置行新增无咬钩保护（ms）：TitanAudioTimeoutMs/ForerverAudioTimeoutMs，启动默认各35000，1000–3600000整数、步长1000，独立保存并按客户端配置到State.AudioTimeoutMs。确认绿色时Deadline=Now+AudioTimeoutMs；运行中保存仅更新以后各轮使用的值，已有AudioTimeout及Reel截止不重算。超时提示根据原Deadline-FishingStartedAt显示实际登记时长，不读刚保存的新值；超时仍重抛、不发收竿、不计循环，定时模式不使用该保护。INI这两项可同时省略兼容旧12项；仅缺一项、非法值或重复键拒绝整份配置，读取不重写旧文件。Audio.Timeout.UiTests.ps1覆盖两服独立超时、另一服正常收竿、命中取消保护、当前事件不变/下轮更新、超时计数与定时模式隔离、设置草稿/首次及重复保存/重开/取消/锁定写入失败、非法/部分缺失/重复配置、旧12项及源文件隔离；仅模拟，不监听或操作游戏。

- 2026-10-12用户要求再录制并提取左上时光服，目标PID32156/StartTimeTicks639273569284727505/3.80.2.70177。完成新的180秒采集，原始音频保留.local-backups/audio-calibration-titan-upperleft-20261012-002609-241/titan-raw.wav（44.1kHz PCM16单声道7938000点），无后台/未知颜色。将间距小于1秒的声音分量合并为事件，保留400ms前置及完整尾音，筛出七个重复声音；以2.415/98.476/128.059秒三个事件的232维分组均值生成第二组模板，保留原titan.feature模板，两组取最高分。79.519/113.482/156.325/170.203秒四个事件不参与制样，分数0.958064–0.991524；86/90门槛七段各触发一次，四段五种包边界/大小均通过。原十轮、十一个初始区间及二十五个负例不回退，负例最高0.805686；新不同声音0.706324在86/90被拒绝。诊断时用户门槛60%会接受它（旧模板0.607961也会），建议90但保留用户INI。一个连续111秒绿色区间不能推断独立轮次，仍Status=trial，不称实际钓获或成功率；只提交数值及验证说明，采集已结束，不自动续录。维护时必须用两份真实录音检查两组特征对旧正负例的影响。

- 用户2026-10-12明确要求保留前后录音、编号选择和设置试听，随后纠正为选择/试听用于快速匹配的短片段。wowAuto.Recordings.ps1集中维护固定编号：titan1=10-11右侧、titan2=10-12左上、forerver1=10-11；时光服匹配分别只用titan-01.feature/titan-02.feature，默认2，无限服默认1/forerver.feature，旧合并titan.feature只作历史保留。每个共同特征仍来自三段制样素材；从三段中选择与共同特征最接近的一段，调用生产AudioTemplate.Resample/SelectEvent按原对齐提取11025Hz/PCM16单声道11025点/1000ms，分别保存audio-samples/titan-01-match.wav、titan-02-match.wav、forerver-01-match.wav。原录音起点分别40.078390/127.688707/124.197211秒，候选7/6/22；选择未使用保留验证素材，不平均PCM、不重做特征。数值特征和INI序号保持，匹配窗口原本就是1秒。180秒完整titan-01.wav、titan-02.wav、forerver-01.wav及原.local-backups归档保持不动；WAV继续忽略、不上传，特征及INI进入Git。以后新增编号须对应真实采集，不能凭列表顺序或PID重新编号。
- 设置“咬钩匹配片段”分组采用DropDownList/OwnerDrawFixed/Flat灰底白字，显示序号/日期/来源/1秒时长；试听只播放所选短WAV一次，System.Media.SoundPlayer.Load后Play异步，一次一个播放器，切换选择/另一服试听/成功保存/取消/关闭/Dispose均Stop并Dispose，缺失文件提示不改选择，不退回180秒整段。PreviewStatus采用“试听片段”描述，避免1秒播放结束后仍显示正在播放。播放属于工具PID，游戏进程回环不包含它；弹窗继续暂停游戏切换/按键。UiTest使用模拟播放器，验证不得实际播放用户录音或采集游戏。
- TitanAudioRecordingId/ForerverAudioRecordingId为新增两项固定INI键，必须为对应目录已知整数ID；两项同时缺省兼容旧14项，部分缺失/重复/未知ID拒绝整份配置。统一验证和原子保存后应用选择，草稿/取消/写入失败不应用；独立存储，保存不替换当前会话的匹配器/候选/已匹配信号/截止。Capture条目RecordingId显示实际使用的编号，TemplateSession记录钓鱼会话，只有新非零AudioSession才按所选ID加载；先Arm(0)，再锁内SetTemplate，再Arm新会话。道具保持引起的同一会话解除/重新Arm不得切换；载入失败停止本行，不回退。SetTemplate要求session=0并校验模板/门槛，清空已过期信号，捕获线程全部匹配仍在gate锁内。Audio.Recordings.UiTests.ps1验证编号/试听/INI/保存回滚/活动轮次和信号保留/下轮切换/版本及失败隔离；Audio.RecordingSwitch.Tests.ps1仅用未调用原生构造函数的内存对象及合成PCM验证实际C#切换保护，不创建采集线程。快捷方式安装检查所有钓鱼 / 战斗 / Unified运行模块，含Recordings。

## autoFight（2026-10-13）

- 2026-10-14 补 Buff：PC autoFight.config.json v7的每职业配置增加 BuffKey（默认F11）、BuffIntervalSeconds（0–86400秒，0关闭）及BuffCount（1–20，默认1）；旧v1–v6只读迁移为关闭，下次保存原子升级。角色编排确认登录并启动战斗任务时触发首轮，随后从上一轮最后一次成功发键起计时；每轮按成功次数发送，轮内相邻成功按键至少间隔1000ms，失败不消耗次数。仅在非战斗待机、非忙碌、无需恢复且无移动请求时执行；到期但不安全则延后，停止 / 换角取消当前轮，新会话重新触发。走统一Fight.Buff队列、公共门控、前台与白点及色块复核；两服插件无改动。AutoFight.Buff.Tests及完整UiTest使用合成状态 / 模拟输入验证，不运行真实游戏按键。

- 当前合集版本titan2.1.23、forerver2.2.22，两服独立维护fight_detector.lua；保留fightDetectorDB / rangeSpells，新增profiles[classId]恢复阈值。战斗通过模块接口关闭钓鱼以恢复音频，不直接读写wowDetectorDB、音频、图形或交互CVar。
- autoFight.ps1、Engine.ps1、Native.cs、config.json的状态、输入、计时和配置与autofish隔离，通过wowAuto.Unified.ps1共享进程行、设置宿主和统一输入调度；不再有独立主标签或独立运行计时器，UiTest以模拟类型替代战斗原生操作，不加载战斗输入适配器。
- 战斗v5只读取主色块：主32×32物理像素位于客户区正中心，副12×12位于中心右32px，只作恢复提示。无心跳、双块校验或颜色变化要求。主RGB=(16+8*(action*4+recovery),2+4*(identity+busy*26),2+4*(encounter+combat*32))；action=0..6为unknown/idle/opening/waiting/combat/loot/skin；新增target动作分别使用保留R240/248/8对应none/recover/emergency，G/B不变。recovery=0..3为none/recover/emergency/unknown；identity=classId-1+（forerver为13）；encounter模32。通道偏差最多1，拒绝非法字段/组合、版本或职业不符、未知恢复及旧协议；射程未知但恢复明确仍可执行恢复。
- HP进入 / 退出阈值默认非战斗80/95、紧急30/50；可选法力恢复默认关闭，只对法力职业生效。0关闭项，进入<退出，迟滞避免状态抖动。受限 / 不可读不推断。恢复优先于普通动作；施法 / 引导 / 战利品窗口阻止普通发键，紧急宏允许打断当前施法。
- PC普通/紧急恢复各次进入仅成功执行一次，由独立RecoveryState/RecoverySent门闩维护；只有退出或切换恢复类型重置，主状态/怪物变化不得重发；失败保留待执行。正常战斗保留重试间隔，开怪按怪物编号一次，waiting不发键。取得前台等待200ms，发键前重读主色、忙碌和怪物编号；无心跳验证。
- 插件不包含移动功能。脚本进程行不再提供前 / 后 / 左 / 右手动移动按钮或点击请求；已有四向键和按住时长配置及引擎兼容逻辑保留，不自动巡逻。若兼容逻辑中已有移动保持，状态变化/到期/停止/刷新/关闭/设置/失焦/主色无效均释放本模块键。
- 尸体交互按可拾取 → 无剩余战利品且可剥皮驱动；CanLootUnit同时读取hasLoot / canLoot，两项均明确且有权限才拾取，受限 / 不完整返回为unknown。有战利品而无权限时不交互、不判剥皮。LOOT_OPENED / LOOT_CLOSED维护忙碌，LOOT_READY / LOOT_SLOT_CLEARED及轮询刷新；两服独立实现。插件按softinteract尸体GUID在主色块怪物编号中区分交互对象，同一尸体从loot转skin保持编号，目标短暂消失再出现不变；新尸体换号。PC在同一编号成功发出拾取键后，只有插件确认无剩余战利品、可交互且可剥皮才发一次剥皮键；同一尸体状态短暂离开再进入也不重试，新尸体重置门闩。拾取仍按InteractionHoldMs设置保持，剥皮固定保持2000ms，状态提前转idle或普通恢复不缩短，进入战斗可提前结束；发键前仍要求非战斗、非忙碌及无需恢复。交互键沿用SkinKey，设置界面明确“拾取 / 剥皮交互键”，默认F7，按脚本Common通用保存；游戏内绑定交互；独立Loot.lua处理已打开窗口的自动拾取及拾取绑定确认，不改变CVar。
- JSON v7：CommandIntervalMs保留公共100–60000ms间隔；Common保存TargetKey（默认Tab）、四向键、移动时长、交互键/保持/开关及JumpIntervalSeconds，全部服务器职业共享。Profiles包含时光服10职业、无限服9职业的OpeningKey/CombatKey/RecoveryKey/EmergencyKey/CombatIntervalMs、BuffKey/BuffIntervalSeconds/BuffCount及身份；两服排除10/12/13职业，无限服另排除6。设置分别有时光服/无限服Tab，每页独立职业下拉框及按键，按真实职业ID映射德鲁伊11，切换保留草稿及选择。v1–v6只读迁移，下次原子保存升级；删除不可用职业，其余自定义保留，旧跳跃默认0、旧补 Buff 默认关闭；取消/失败不应用。
- 本次Windows任务须执行解析、编译和模拟检查，提交并成功推送后同步两服及桌面快捷方式；不运行真实发键循环、采集游戏声音或结束游戏进程。

- 钓鱼JumpEveryCycles按成功收竿循环次数独立保存到config.ini，0–1000000、默认0、步进1，不改为秒计时。满N次在冷却 / 保持后有效红绿状态按空格，未知等待、黄色优先。PostReelJumpAllowed只由本次任务已登记且成功发送的收竿赋予；正在钓鱼、收竿失败、无咬钩超时、停止后重新开始不得立即跳跃。停止 / 刷新保留计数，继承待跳须等下一次成功收竿；成功跳跃/抛竿/停止/超时清除权限。保留成功收竿后绿色恢复跳跃，成功一次清除两种待跳并归零，失败重试。改变N重置、重复保存不重置，原子保存成功才应用。JumpInterval及完整UiTest模拟覆盖两服待跳继承/钓鱼中不跳/失败/超时/下一次成功收竿及原有优先级。
- 战斗公共CommandGate跨窗口 / 职业 / 状态门控全部成功发键，不约束钓鱼；职业更长冷却和保持仍有效。松键不延迟且不消耗间隔；停止 / 刷新不重置LastSentAt，保存间隔也保留它。v1/v2只读迁移默认公共500ms，下次保存升级v6，全部字段成功写入才应用。AutoFight.Engine.Tests.ps1及UiTest模拟配置失败和全部状态跨窗口门控，生产Native.cs仅编译。
- 两服各自Loot.lua仅在任一检测开启时监听LOOT_OPENED / LOOT_READY / LOOT_SLOT_CHANGED / LOOT_SLOT_CLEARED / LOOT_CLOSED，使用本客户端GetNumLootItems / GetLootSlotInfo第6项locked / LootSlot拾取未锁定槽位。wowDetector及fight_detector通过IsEnabled返回实际开关，不能用面板可见性代替。任一检测开启时，所有来源和品质的LOOT_BIND_CONFIRM均排队下一帧ConfirmLootSlot；事件及每个槽位执行前都重新读取两模块开关，全部关闭时取消确认，另一检测继续开启则保持。缺失 / 异常 / 受限开关不视为开启，不阻断另一模块的有效true。成功才StaticPopup_Hide("LOOT_BIND", slot)；只确认拾取绑定，失败保留人工提示、受限不比较、不改变CVar或两模块设置。按槽位去重、关闭清空；Loot.Tests.lua分别模拟两服全部开关组合、全部槽位、延迟中关闭 / 切换 / 重启、处理途中关闭及API失败，钓鱼与战斗模拟验证真实IsEnabled启动 / 关闭 / 死亡 / 钓鱼hide行为；ForeverCompatibility.Tests.lua按实际TOC加载完整模块。

- 距离检测：两服独立fight_detector/Range.lua采用经典 / Forever已知敌对物品探针，档位5/10/15/20/25/30/35/40码，C_Item.IsItemInRange优先、全局接口仅缺省回退，先排除受限返回；缺失、异常、冲突为unknown。加载时预热物品数据，不使用、购买物品或读取怪物坐标。profiles[classId].DetectionRangeYards默认30，顶层AttackRangeYards默认5且为该客户端账号全局；旧rangeSpells保留。面板一次校验全部距离和恢复阈值后保存，非法不部分应用。
- 开怪后跟踪 GUID；只有玩家实际进入战斗才按攻击距离输出 waiting / combat，伤害技能成功但尚未进入战斗仍输出 opening / waiting。PC 成功发开怪键后等待 1 秒；同一怪仍未进入战斗且可开怪时先重按选目标键，插件确认当前目标 GUID 后再次开怪，每次开怪完成重新计时。目标消失、进入战斗或怪物会话编号改变即取消旧重试；检测距离外静默等待，重新进入检测范围后先选中再开怪。战斗中退远回 waiting，不能因进入战斗直接攻击。本次怪物 GUID 优先于当前目标及其他近处姓名板；输入前重查编号。waiting 期间不发开怪 / 攻击 / 恢复 / 移动键，按住键的释放仍立即执行。

- 战斗色块缩放：unit=UIParent:GetHeight()/GetPhysicalScreenSize高度，将主/副尺寸转换为32/12px，主偏移0，副偏移+32px；DISPLAY_SIZE_CHANGED/UI_SCALE_CHANGED及轮询重算。PC同一PMv2 DPI上下文每次读取客户区中心；无遮挡中心核对WindowFromPoint所属窗口再取像素，遮挡 / 失败时PrintWindow客户区渲染快照取中心；前后窗口尺寸/位置一致才解码，不缓存旧中心，不读取副块或验证心跳。暂时不可读暂停发键并保留会话/恢复门闩，连续800ms失败才停并显示LastReadError及主RGB；保持移动时立即释放。两服FightDistance及AutoFight.Distance跨语言验证v5主RGB/几何/职业/非法/稳定颜色。进程行按监视器位置显示四角/居中/最小化，每秒更新，与钓鱼规则相同。
- 自动战斗全局JumpIntervalSeconds=0..3600秒，默认0关闭，Common共享两服职业，各活动进程独立从启动计时。到期在idle/combat且非忙碌/无需恢复、无移动请求时发一次Space；等待接近/恢复/移动/交互保持延后，主色及前台复查和公共CommandGate仍约束。成功从完成时刻重计，失败不消耗，不重置攻击冷却/恢复门闩。成功保存不同值重新计时，相同值保留；停止/刷新取消，重启重计。AutoFight.Jump及完整UiTest模拟验证边界/优先级/失败/独立性/保存隔离，禁止真实游戏按键。

- 选目标与后台检测（2026-10-15 修订）：两服插件只读取当前目标、软敌对目标和姓名板，不创建 SecureActionButton、不覆盖 TargetKey、不设置或读取游戏焦点。插件输出 target 后由脚本发送 Common.TargetKey（默认 Tab）；只有当前目标 GUID 与本次怪物相同才输出 opening / combat。脚本键须由用户绑定到游戏原生选目标动作，插件无对应设置；旧 fightDetectorDB.TargetKey 字段忽略。开怪后 1 秒未入战斗时脚本再次选目标并重试，战斗中若当前目标变化且仍能找到原怪物，先请求选回原目标；找不到时暂停。脚本公共键校验、500ms 选目标重试和公共门控保留。
- 战斗运行时状态 / 职业 / 位置 / 发键前重读不以 Foreground 作为检测前提；统一刷新先 Activate 发送开启命令再采样，并在结束时 Restore 原窗口。只有实际动作到期才激活并等待 200ms，Press / BeginHold 仍验证前台。交互保持可后台读色，移动失焦释放并继续监测。最小化 / 后台黑图 / 非法色暂停，800ms 规则保留。FightDistance 模拟姓名板先选再开、战斗错选 / 目标丢失、不使用焦点或安全绑定；UiTest 模拟后台扫描、选目标取得前台、确认及开怪重试，不发送真实按键。

- 两服 Init.lua 各自创建 WoWTools.detectorAnchor 在 UIParent 正中心，钓鱼与战斗主色中心重合，战斗副块中心位于主块右侧 32 物理像素。WoWTools.ActivateDetector 在成功启动前停止并隐藏另一个检测，覆盖命令、按钮、小地图及菜单入口。切出钓鱼恢复音频快照，切出战斗清理会话；战斗检测不创建或清理按键绑定。死亡或未初始化拒绝启动时保留原模块。DetectorExclusion.Tests.lua 模拟两服互斥、所有入口、显隐、失败、音频恢复、无绑定及缩放位置。

- 非战斗主块主体使用钓鱼等待红RGB255/0/0，仅combat明确false且state/recovery均非unknown时应用，覆盖待机/选目标/开怪/等待接近/恢复/尸体交互。主32px内部正中心2×2物理px的OVERLAY子层1纹理保留v5数据，PC仍只读原主中心像素；外部仍为两个色块，无副块读取或心跳。战斗/未知隐藏内部纹理并用原编码铺满主块；恢复副块不变。内部区域与共享锚点重合，按相同unit换算，保留缩放及奇偶客户区中心采样。FightDistance.Tests.lua输出实际主中心颜色供C#解码，DetectorExclusion比较切换前的钓鱼等待红，不能误比较关闭后的灰色。

- 选目标键配置验证：AutoFight.Engine 覆盖脚本配置只读迁移、默认 Tab、组合键往返、全职业共享、冲突及原子保存；完整 UiTest 覆盖按键录入、草稿、保存、重开、取消与生产选目标流程。FightDistance 分别验证两服插件没有按键输入框、覆盖绑定或焦点读取，旧 SavedVariables.TargetKey 不恢复旧功能；确认目标 GUID 后才回报开怪，所有操作模拟。

## 统一进程页面（2026-10-13）

- 主界面只有进程任务页，设置内自动钓鱼 / 自动战斗两个Tab，各自独立草稿和保存按钮；保存后继续编辑，不保存另一页草稿，取消 / 关闭丢弃未保存修改。战斗设置内保留两服职业Tab。弹窗暂停两模式输入 / 刷新，打开前释放移动键，切换设置Tab停止试听。
- 每行TaskMode只由角色槽位Mode决定：初建进程按首个有效槽位，轮换按当前槽位，未编排默认fish。移除ModeBox及模式标签，不创建隐藏模式下拉框。旧Mode_<PID>_<StartTicks> INI仍读取 / 保存以兼容旧配置，但不用于任务选择；角色保存后停止原任务、更新对应适配器并作废检测验证，PID复用不继承计划。
- 刷新停止全部任务，逐行激活 / 核对前台，200ms后发送对应检测开启命令，成功后再等待200ms才读色；身份 / 焦点 / 命令失败不采样、不开放开始按钮。只允许两个固定开启命令，游戏聊天使用Enter。完成尝试恢复原前台；手动开始后才能执行任务。插件两服源码本次不变，不混用安装副本。
- wowAuto.Unified.ps1通过单一计时器协调两套状态机和前台输入；正常战斗优先于到期钓鱼收竿，收竿 / 道具保持期间普通动作等待，战斗可只读后台检测。战斗激活待输入及移动 / 交互保持期间，钓鱼不抢焦点。战斗公共CommandGate保留，钓鱼成功收竿跳跃限制不变。
- Unified.UiTests随完整UiTest模拟混合两服模式、激活 / 命令 / 采样顺序、失败隔离、手动全部开始、模式保存失败回滚、重建 / PID复用、非法 / 旧INI、两页独立保存 / 取消和混合战斗优先。真实用户INI / JSON哈希不得改变；禁止真实游戏按键 / 音频 / 结束游戏验证。

## 三槽位角色编排与OCR（2026-10-13）

- 每进程三槽，完整Name / Mode=fish或fight，跳过空槽，单槽仍退出并重新登录；计划保存完整名字，不使用位次 / 总数。OCR选角允许同长度最多一个字符误读（至少N-1个位置相同），仅在该读数唯一对应一个已配置名字时采用；多个候选一律拒绝点击。rotation.config.json v2保存IntervalSeconds=0..604800、OcrIntervalMs=100..60000（100的整数倍，默认1000）及PID:StartTicks计划。旧v2缺OCR周期只读使用1000，下次保存补齐；配置写入原子成功后才应用。设置顶部OCR控件Increment=100，保存全局设置同时保存两项；保存相同轮换间隔不重计，取消 / 失败不部分应用。
- 共用全局轮换截止，到期先停全部参与进程的任务，再逐窗对仍在世界内的进程发送登出请求；所有参与进程的登出请求处理完之后，先逐个OCR识别并缓存全部角色点击位置，再逐窗点击，所有点击结束后才逐窗确认登录并验证。已在选角界面的进程跳过登出。0关闭后续定时轮换，过期批次完成后等待完整周期。停止 / 刷新 / 关闭取消任务，角色切换清除CompletedCycles / CyclesSinceJump，不改成功收竿后的跳跃约束。
- 登出队列优先于选角队列：logout-activate等待200ms，logout-inspect用白点判断是否发送stopcasting / logout，结束后转入选角队列；下一进程仍待登出时禁止启动OCR。选角阶段activate等待200ms，menu中退出未完成每30秒重试。随后按位置识别队列Queue → ClickQueue批量点击 → LoginQueue确认登录 / 白点复核使能任务运行。OCR只在menu / find执行，唯一目标位置连续两次稳定后缓存并立即Stop-RotationOcr；click / login / validate绝不启动OCR；初次已在选角界面可直接识别。
- 选角界面只需在预期客户区位置识别右上“选择服务器”或中下“进入魔兽世界”之一，连续三次确认，不依赖系统公告或配置名当前可见。每次OCR截图前把光标移到客户区左上角；仅识别当前第一页，禁止滚顶或翻页。角色列表用上述N-1规则，长度不同、两个以上字符错误或匹配歧义不点击。日志列出OCR识别到的第一页名字、行号以及准备点击的行号。目标名字及比例坐标连续两次稳定后，先生成两段100–250ms随机间隔，再连续点击三次；第一页连续三次未找到配置名字则停止本行。
- 两服独立LoginPoint.lua在Init后加载，当前合集titan2.1.23 / forerver2.2.22。右下角向左 / 向上各内缩16物理像素的16×16白点，避开Windows圆角裁切；纯白RGB255/255/255、鼠标穿透、高层级，独立于任何检测开关或面板，不保存请求编号；PLAYER_ENTERING_WORLD显示，PLAYER_LEAVING_WORLD / LOGOUT隐藏。768/画面高度/有效缩放换算，尺寸 / UI事件即时及每1秒轮询重定位；常驻白点只确认世界就绪，不编码角色身份。不要恢复旧Rotation.lua、wowRotationDB或arm / probe命令。
- login每300ms检测白点，连续三次存在后进入validate；validate再次检查，缺失回login且不使能。Send-ScanDetectorCommand是钓鱼 / 战斗监控开启的公共入口，必须先检查白点；轮换自动启动前再次检查，普通钓鱼 / 战斗前台调度也在按键前检查。白点读样核对身份 / 前台 / 遮挡 / 几何，取客户区右下内缩16px后的16×16区域（x=客户区宽度-32,y=客户区高度-32）中的内部12×12近白区域，不按桌面绝对坐标读取。
- 战斗白点复核只在需要实际发键、取得前台并满足激活等待后执行；不得放到后台Native.Read之前或后台交互保持轮询内。白点读取要求前台，后台读取会误报并将CanStart置false，导致单行开始被锁。Test-AutoFightLoginPoint显式核对前台，模拟用例覆盖后台监测 / 刷新 / 保持不误锁及前台白点缺失不发键。Set-RowControls的停止条件须包含running，启动资格失效时仍可停止已有任务。
- OCR用Windows zh-Hans-CN，独立runspace，只有选角整图及名字预处理图；移除世界HUD识别。小窗口放大、按OcrEngine.MaxImageDimension限制输入两轴，角色名区域按客户区高度计算宽度并右对齐，NamesBounds记录实际裁剪比例。Windows OCR返回非零TextAngle时将文字框中心从OCR去斜坐标旋回原图；OCR只负责判定第一页角色名及其所在行，点击点使用固定行中心：首行Y=客户区高度的11.9%，后续每行增加7.43%，X取右侧NamesBounds区域中心；不使用OCR文字框中心直接点击。仅接受靠近固定行的识别结果。鼠标坐标用DPI感知的当前客户区物理原点及尺寸映射；截图前独立记录系统客户区宽高，异步识别返回及点击前重读系统尺寸并直接比较，任一维度相对原始尺寸变化超过5%时丢弃重识别；位置不参与缓存复核，三连击内部仍核对当次几何。5%以内的变化按当前尺寸映射缓存比例坐标后下发，禁止直接复用旧绝对坐标。
- NextOcrAt限制同次选角两次截图启动的最小间隔，默认1000ms；异步未完成时100ms轮询，不重叠。保留动作后300ms等待、3秒完成结果过期及全流程180秒超时，保存新周期不重算已登记截止。白点等待与任务使能阶段按300ms轮询，不受OCR周期影响。
- Windows 任务按本文件的解析、模拟测试、提交推送后同步流程执行；历史 mac 会话跳过验证及Windows同步的要求不适用于本次任务。不得把离线OCR或模拟结果描述为游戏实测。
- 历史真实角色切换录屏仅用于时光服选角文字依据，录屏 / 图像 / OCR输出保存在.local-backups，不上传；用户明确要求保留的2026-10-14选角截图作为独立回归夹具提交。无限服界面没有实际验证记录，不把时光服画面冒充无限服验证。

## 公共优先级动作队列（2026-10-13）

- 用户要求所有游戏动作使用同一个队列并提供可调整的多级优先级。wowAuto.ActionQueue.ps1 是唯一执行器，主25ms计时器驱动钓鱼、战斗、刷新、角色编排、正常退出 / 30秒超时结束及窗口恢复；生产扫描不再启动独立动作计时器。用户要求每轮处理所有应该处理的事件：执行器循环消化当前已到期且可执行事件，每个事件后重读单调时钟并复核优先级 / 冷却 / 保持 / 对象身份，回调新增的可执行事件也在本轮处理；前台激活等待不阻塞独立后台事务，同级和更低优先级窗口事务仍等待。不得恢复每轮只推进一个事件，也不得用无等待循环反复重试未稳定窗口。各自状态机及只读探测保持独立，Unified模式共享schedulerClock，避免跨模块截止时间偏移。
- action-priorities.json v1保存事件与数值，越小越优先，仅比较到期事件，依优先级 / 截止 / 入队序号排序。同意图按ID去重、状态变化替换；停止 / 刷新 / 重启取消旧对象身份的动作。Safety.Release=0和Hold.Pulse=5为保留级，普通事件10–999；默认Fight.Emergency=10、Fight.Combat=20、Fish.Reel=30；用户明确要求正常战斗高于钓鱼收竿。完整默认清单在tools/wowAuto/ACTION_PRIORITIES.md。修改优先级后重启工具。不得恢复两套输入调度器直接争抢前台。
- 所有激活、发键、鼠标、松键、CloseMainWindow / Kill及RestoreAfterScan必须有队列执行上下文。窗口激活等待200ms、800ms超时；更高优先级动作可以抢占尚未发键的激活等待，恢复时重新激活并重计等待 / 超时。组合键 / 聊天宏 / 选角三次点击是不可穿插的业务事务。战斗入队前后台探测，执行前核对实际动作及原有身份 / 职业 / 遭遇 / 主色 / 前台白点；不将白点放到后台探测之前。
- 角色编排的队列动作及状态机前台检查使用单调时钟，在暂时激活失败或失焦时每500ms重试，连续5秒无法取得前台才停止该行；成功取得前台后仍等待200ms稳定。进程身份改变立即停止。非角色编排动作保留原800ms规则；不得在调度器单次调用内忙等。
- 角色编排只要还有当前切换或排队进程，就独占前台。钓鱼、战斗、刷新及窗口恢复等其他进程事件不得激活窗口或发键，即使数值优先级更高；已有的非编排激活等待须撤销并在整批完成后重新等待200ms。安全松键、保持监测和进程退出检查继续处理。允许先完成登录的进程建立任务状态，但任务输入直到最后一个进程登录验证完成才下发；不要在不同进程选角间插入钓鱼或战斗动作。
- 原有收竿 / 道具 / 战斗移动 / 交互保持继续阻挡普通事件，释放及保持监测可执行；紧急恢复也受保持约束，监测发现恢复色块变化可提前结束战斗保持。松键通过同一执行器同步排队，只有Safety事件可嵌套执行。战斗公共门控、钓鱼成功收竿循环跳跃、OCR周期 / 缩放定位、两服插件协议不变。
- Windows 维护按本文件的解析、模拟验证及提交推送后同步流程执行；历史 mac 会话中不验证、不同步 Windows 的要求不适用于本次 Windows 任务。不得将模拟通过写成游戏实测。

- 2026-10-13 Windows圆角修复：贴边白点会被系统窗口圆角裁掉，原内部12×12全白校验拒绝。两服LoginPoint定位及PC LoginPointBounds同时内缩16物理像素，保持点本身16×16；仍拒绝部分白 / 遮挡 / 失焦 / 几何变化，不能放宽为任意白像素。LoginPoint.Tests仅编译生产C#及合成图像验证圆角缺失、内缩定位、奇偶窗口尺寸及遮挡，Rotation.Tests分别验证两服缩放后的物理内缩。

## 右下白点、双按钮锚点与名称历史（2026-10-13）

- 两服分别把白点锚到BOTTOMRIGHT，UI单位偏移为(-16*unit,+16*unit)，物理大小16×16；PC LoginPointBounds=(客户区宽-32,高-32,16,16)，保留16px圆角内缩、DPI上下文与几何复核。实际画面 / UI缩放及100ms轮询更新，不改为桌面绝对坐标。
- 角色编辑每槽Name为DropDown可输入ComboBox，历史全进程共享、精确去重，NameHistory保存到rotation.config.json v2；旧v2缺历史时从已有计划初始化，读文件不重写。只在全部校验与原子写入成功后更新历史，取消 / 锁定失败不记入，删除槽位仍记住名字。模式下拉仅保留在槽位中，不在进程行另设。
- 2026-10-14独立选角截图夹具在原尺寸及1.5倍断言双按钮锚点与两个角色名“吔史呀嘞”“双持船橘二咪”；0.67倍降采样会丢失前者字符，只断言双锚点及不误选该名字。新增两张窗口化截图分别断言“乌木力奇”“铁皮小橘”“米勒麦格”和“超级小船”“加洲铁肘”“洋芋巴巴”“阁灵德渥”均识别到对应固定行，点击Y贴合截图中的文字行中心、X位于角色列表内；原尺寸及1.5倍都要通过。角色名可由整图OCR补全黄色文字预处理的误读；非零TextAngle坐标须旋回原图，否则窗口放大时会偏移。模糊匹配的两个错误、长度不同及多个候选必须拒绝。专项UI使用模拟输入，不运行真实游戏按键；完整UI测试应与专项测试分别运行并报告结果。


## 游戏目录、子战网及槽位道具（2026-10-13）

- 设置增加游戏目录页，独立保存两服路径，支持客户端目录或总目录；保存核对产品名、可执行文件与3.80./1.60.版本，再扫描WTF/Account，原子写入成功后才应用并停止任务。rotation.config.json v2可选GameDirectories保存titan/forerver；旧配置只读使用默认路径。
- wowAuto.Accounts.ps1只读子战网/服务器/角色目录，排除SavedVariables和重解析链接，仅读目录名，不读凭据。进程安装路径必须与配置相符。进程行在角色编排旁选择子战网，计划Account保存归属；更改停止任务/作废验证，保留原槽位供用户核对。单一账号或角色名单唯一匹配可建议，否则留空待选择，不用时间戳宣称实时登录身份。
- 名称ComboBox仍可输入，但Items/自动补全只来自当前子战网的本地角色记录，跨服务器同名去重，不能混入全进程历史。保存及启动前验证成员关系，不自动登录账号或换服；未缓存的新角色须登录并正常退出后刷新，旧目录可能残留。
- 移除主行道具勾选，UseItem按三个槽位独立保存，战斗禁用且不生效。旧v2缺字段时按进程身份从旧INI UseItem_*只读迁移到钓鱼槽位，下次编排保存补齐；全局钓鱼道具按键/收竿后跳跃规则不变。运行中保存编排会停止任务，不提供独立主行运行时道具开关。
- Run.AccountsUi.Tests.ps1运行生产UI、Accounts/Rotation/Unified专项与临时目录及模拟输入，覆盖版本/父目录、账号隔离/歧义/保存回滚、角色过滤/原子槽位开关、目录草稿与旧v2迁移。禁止游戏按键、实际账号切换及关闭游戏验证。完整UI模拟已更新后台取色、前台稳定等待和战斗读样时序；专项与完整套件需分别验证。两服插件本次未改动。

## 先识别全部位置再批量点击（2026-10-14）

- 用户要求识别角色点击位置与执行点击独立：LogoutQueue全部登出请求 → Queue全部位置识别 → ClickQueue全部点击 → LoginQueue逐窗确认登录及使能。位置识别后不得直接点击；点击后不得等待本窗口登录才点击下一窗口。菜单三次确认、目标位置两次稳定、第一页唯一N−1名称匹配、三连击100–250ms随机间隔及右下白点三次确认规则保留。
- PreparedTarget / PreparedSlot仅保存在当前运行Entry，包含ProcessKey、名称、行号、0–1坐标及独立ClientSize（截图前系统接口读取的客户区宽高）。独立Rotation.Click事件默认50，Rotation.Select=50只负责识别缓存；各阶段仍使用同一个公共执行器。Test-RotationWorkPending必须包含两个新增阶段队列，整个批次结束前仍阻止其他钓鱼 / 战斗前台输入。
- 点击前复核当前槽位 / 名称 / 进程身份 / 客户区宽高及白点，窗口平移按当前物理原点映射，宽或高相对原始缓存尺寸变化超过5%才清除缓存并返回识别队列；已经进入世界则重新登出和识别。停止、刷新、关闭、会话替换、背包满换角都要移除该行各阶段队列及缓存，其他进程的准备结果不受影响。选择至使能共用每进程180秒截止，重识别不重计，单次OCR结果取回3秒过期规则不套用到已验证缓存。
- 角色轮换与公共队列模拟用例维护阶段屏障、两窗坐标所属、点击期间无OCR、全部点击后才确认登录、缩放重新识别、停止缓存行不点击及持续前台互斥。本次按用户要求Mac仅开发并直接提交推送，未运行测试 / 编译 / 游戏 / UI验证，也未同步Windows；两服插件无改动，重启PC工具生效。

## 角色坐标缓存的系统尺寸复核（2026-10-14）

- 用户明确要求OCR截图前通过系统接口获取窗口尺寸，复核时再次系统读取并直接数值比较；只比较客户区宽 / 高，不比较横纵坐标。Get-RotationClientSize调用Native.ReadClientSize，在PMv2 DPI上下文使用GetClientRect取得物理像素，独立ClientSize快照不能从Bitmap.Width / Height或OCR结果构造。
- 停放光标后先记录ClientSize再Capture，Capture同时核对预期系统尺寸，读取前与截图之间任一维度变化超过5%则丢弃重取。OCR异步返回及点击前都重新系统读取尺寸直接比较；PreparedTarget保存独立ClientSize，OCR只提供角色及比例坐标。窗口平移不使缓存失效；宽、高分别相对原始缓存尺寸计算变化，均不超过5%（含5%）则容忍，任一超过5%才重识别，复核不得更新原始基准以免累计漂移。
- Native.ClientSizeWithinTolerance使用64位整数比较每轴差值×100与原尺寸×5，拒绝无效尺寸；PowerShell复核、Capture与ClickCharacter共用此规则。ClickCharacter在真正映射 / 发送点击前再次核对预期系统宽高，容差内按当前实际尺寸映射，三连击中途移动 / 缩放仍中止，保留原有身份 / 前台 / 遮挡保护。维护模拟用例覆盖系统读取计数、OCR无关字段、不比较窗口位置、宽高正负5%边界、单轴越界、无效尺寸、基准不漂移及容差内不重启OCR直接点击。按用户要求未执行验证或Windows同步，开发后直接提交推送。


## 统一WGC窗口捕获与非激活恢复（2026-10-14）

- 本节按用户最新要求覆盖历史屏幕取色 / PrintWindow后备、白点前台限制、OCR截图前停放光标及全编排阶段激活的约定。所有画面读取统一进入wowAuto.Capture.cs / ps1，以Windows.Graphics.Capture按HWND获取独立客户区帧；NativeInput、Rotation.Native、Fight.Native仅注入通用帧 / 像素 / 尺寸委托，不跨用钓鱼或战斗状态机。支持Windows 10 1903及以上，运行时解析WinRT，不依赖SDK、NuGet或外部DLL；捕获错误明确失败，不退回屏幕截图。
- 每次请求核对PID / StartTicks / 路径 / 两服版本及窗口句柄。最小化清旧帧，Capture.Restore=45进入同一个游戏动作队列，在队列回调使用ShowWindowAsync(...,4=SW_SHOWNOACTIVATE)；恢复每500ms最多一次、从队列首次实际恢复起5秒期限（排队等待不计），禁止SetForegroundWindow及等待前台。读样恢复后等待新帧；首帧 / 尺寸更新最多5秒，重试100ms，不作为白点消失、协议关闭或焦点失败。停止取消该身份的恢复请求；旧恢复事件不得作用于新会话 / PID复用。
- WGC使用每窗口MTA后台线程和CreateFreeThreaded帧池 / D3D11资源，GUI只复制已准备的客户区帧。QPC帧时间超过1500ms、恢复之前的帧、全黑或几何不匹配的帧不参与判断；按DWM实际画面边界与PMv2 ClientToScreen / GetClientRect裁剪客户区，排除标题栏及边框，尺寸改变重建帧池。10秒无请求释放会话，关闭工具异步释放全部资源；不能在UI线程同步等待捕获服务关闭。
- 系统ClientSize继续独立获取，不依赖OCR或Bitmap尺寸，宽高各自与原始缓存比较、<=5%容忍且不滚动基准。白点位置 / 16px内缩 / 16×16及内部12×12校验、v5战斗协议、中心鱼饵32px偏移和钓鱼成功收竿跳跃不变。Windows 10 2004及以上可排除捕获指针；较旧系统以系统行为为准，不在后台OCR截图时移动全局鼠标。
- 钓鱼后台检测仅需要发键时将同一事件转为Foreground，重新读样后下发；状态更新 / AudioTimeout不激活。同进程较低优先级后台读取不能改写等待前台的意图，高优先级到期收竿仍能抢占。战斗检测 / 刷新Sample / 编排menu、find、login、validate均后台；logout-send / menu-logout / click / enable才取得前台，仍保留200ms稳定 / 编排5秒及普通输入800ms规则。全批登出→全部识别→全部点击→全部登录屏障及整批输入互斥不变，Capture.Restore允许在批次期间执行。
- WindowCapture.Adapters.Tests使用合成帧及注入委托覆盖全部原生读取入口、身份传递、白点与主 / 鱼饵像素、OCR独立尺寸及Pending传播；ActionQueue增加非激活恢复 / 后台读取不抢占焦点和100ms首帧等待模拟。按用户当前Mac要求未运行任何解析 / 编译 / 测试 / 游戏 / UI验证，也未同步Windows，完成后直接提交推送。

- 两服检测关闭时各自注销业务事件并移除OnUpdate轮询；启动后重新订阅和读取当前状态，面板显隐不等于检测开关。钓鱼只保留ADDON_LOADED初始化及PLAYER_LOGOUT音频快照收尾；战斗只保留ADDON_LOADED初始化，不创建目标按键绑定或焦点，也不需要脱战清理。拾取模块仅在任一检测开启时订阅拾取事件和逐帧处理，全部关闭时清空待处理槽位且不自动拾取。白点每1秒重定位，画面尺寸 / UI缩放事件即时处理。DetectorExclusion.Tests、Loot.Tests和Rotation.Tests覆盖关停 / 重启 / 切换、无后台拾取及白点间隔。
