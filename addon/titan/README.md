# titan

泰坦时光服的独立插件源码：`wow_tools/`，版本2.1.9，接口版本38002，客户端为3.80.2。基于原归档2.1.1维护；包含开启检测时的音频快照/钓鱼配置，以及关闭、死亡、登出/重载时的原值恢复，不改变音频输出设备。

2.1.3将绿色条件改为：玩家正在钓鱼引导，且 `UnitGUID("softinteract")` 有目标、`UnitIsInteractable("softinteract")` 为真。抛竿施法中、未钓鱼或目标消失时为红色；钓鱼引导中没有目标时显示“等待交互”。读取接口缺失、失败或数据不可读时显示灰色；背包已满仍优先显示黄色。监听 `PLAYER_SOFT_INTERACT_CHANGED` 并每0.1秒补充刷新，不缓存上一轮的成功状态。

测试前在游戏设置中启用“交互键”；插件不自动修改 `softTargetInteract`。`/wowdetector status` 输出交互判断、名称、GUID及该CVar值。目标来自客户端当前的交互软目标，不限定为自己的鱼漂，也不证明咬钩；转向、距离和其他目标可能影响选择，需游戏实测。

接口依据：[泰坦导出接口](https://github.com/Gethe/wow-ui-source/blob/0f73fd6b0e12bf8de89a8084ebd81aade0afe8d7/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)及[软目标姓名板实现](https://github.com/Gethe/wow-ui-source/blob/0f73fd6b0e12bf8de89a8084ebd81aade0afe8d7/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.lua)。无限服源码及检测条件独立保留。

安装目标：`C:\Program Files (x86)\World of Warcraft\_classic_titan_\Interface\AddOns\wow_tools`。先验证、提交并推送，再从仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1 -Flavor titan
```

使用说明见根目录README。`addon/tests/LureDetection.Tests.lua` 使用模拟接口验证钓鱼引导与可交互目标的组合条件、目标变化/轮询及未知状态、鱼竿附魔、死亡关闭及窗口尺寸/UI缩放下的物理像素定位。

2.1.4增加独立 `fight_detector/fight_detector.lua`：小地图右键启动 / 关闭、按职业设置测距伤害法术，读取战斗和软交互尸体的拾取 / 剥皮提示，以独立色块协议供autoFight使用。配置保存到独立 `fightDetectorDB`，不改变wowDetector、音频及画面模块。按本次用户要求未执行验证；使用流程见工具README。

2.1.5：fight_detector由插件驱动开怪 / 正常战斗主色，并增加中心上方64px、右侧88px的独立恢复色块（蓝=无需恢复、紫=非战斗恢复、橙=战斗紧急恢复、灰=未知）。面板按本职业配置生命值进入 / 退出阈值，默认非战斗80% / 95%、战斗紧急30% / 50%；法力恢复可选，默认关闭。四向移动暂不确定自动规则，仅提供手动单次状态请求。PC需同时更新协议v2并重启；插件需/reload。详见工具README，本次仍未执行验证。

2.1.6：尸体拾取同时确认有战利品且当前角色可拾取，战利品窗口（含自动拾取过程）打开期间标记忙碌；拾取关闭 / 槽位清空及时刷新，确认无剩余战利品并可剥皮后切换剥皮状态。PC在拾取与剥皮阶段切换时重新执行同一可配置交互键，同阶段失败重试继续保留间隔。按本次用户要求未执行验证。

2.1.7：独立 `Loot.lua` 在打开战利品时自动拾取未锁定的槽位，包括钓鱼战利品；下一帧自动确认 `LOOT_BIND_CONFIRM`，成功后只隐藏对应槽位的 `LOOT_BIND` 弹窗。受限数据、缺失接口或确认失败时保留人工处理，不改CVar，不共享钓鱼和战斗设置。已通过Lua5.1编译及 `Loot.Tests.lua`、钓鱼检测与音频模拟；实际拾取效果由游戏测试确认。

2.1.8：fight_detector增加本职业检测 / 开怪距离（默认30码）和全局开始战斗距离（默认5码），以游戏码数配置，可选5 / 10 / 15 / 20 / 25 / 30 / 35 / 40。已发现的怪物在开怪后持续跟踪，远于攻击范围显示青色“等待怪物接近”；进入范围才显示红色攻击，退远后继续等待。PC每个怪物会话仅成功下发一次开怪键，等待时不发任何键。进入战斗不直接允许攻击；怪物会话编号由新协议v3第9格传递，工具与插件需一起更新。

两服分别在fightDetectorDB.profiles[classId].DetectionRangeYards保存本职业检测范围，fightDetectorDB.AttackRangeYards保存该客户端账号的全局攻击范围；不会复制账号 / 客户端间的SavedVariables。旧rangeSpells配置保留，新检测不依赖已学会的测距技能。独立Range.lua采用敌对目标物品距离探针；缺失 / 受限 / 冲突 / 失败数据为未知。姓名板只涵盖客户端已暴露的单位，不能扫描所有附近怪物；开怪宏仍需自行选敌并施放伤害技能。FightDistance.Tests.lua分别验证两服，AutoFight.Distance.Tests.ps1验证生产C#纯协议解析及PC状态流程，不发送真实按键。

2.1.9将战斗协议收敛为主、副两块12px色块，移除插件移动按钮及处理；PC移动/交互转为通用设置，职业只配置攻击和恢复，普通/紧急恢复每次进入只执行一次。动态按物理窗口与UI缩放定位，两服独立Lua5.1及完整脚本模拟检查通过；更新须/reload并重启wowAuto。
