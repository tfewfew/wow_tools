# titan

泰坦时光服的独立插件源码：`wow_tools/`，版本2.1.3，接口版本38002，客户端为3.80.2。基于原归档2.1.1维护；包含开启检测时的音频快照/钓鱼配置，以及关闭、死亡、登出/重载时的原值恢复，不改变音频输出设备。

2.1.3将绿色条件改为：玩家正在钓鱼引导，且 `UnitGUID("softinteract")` 有目标、`UnitIsInteractable("softinteract")` 为真。抛竿施法中、未钓鱼或目标消失时为红色；钓鱼引导中没有目标时显示“等待交互”。读取接口缺失、失败或数据不可读时显示灰色；背包已满仍优先显示黄色。监听 `PLAYER_SOFT_INTERACT_CHANGED` 并每0.1秒补充刷新，不缓存上一轮的成功状态。

测试前在游戏设置中启用“交互键”；插件不自动修改 `softTargetInteract`。`/wowdetector status` 输出交互判断、名称、GUID及该CVar值。目标来自客户端当前的交互软目标，不限定为自己的鱼漂，也不证明咬钩；转向、距离和其他目标可能影响选择，需游戏实测。

接口依据：[泰坦导出接口](https://github.com/Gethe/wow-ui-source/blob/0f73fd6b0e12bf8de89a8084ebd81aade0afe8d7/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)及[软目标姓名板实现](https://github.com/Gethe/wow-ui-source/blob/0f73fd6b0e12bf8de89a8084ebd81aade0afe8d7/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.lua)。无限服源码及检测条件独立保留。

安装目标：`C:\Program Files (x86)\World of Warcraft\_classic_titan_\Interface\AddOns\wow_tools`。先验证、提交并推送，再从仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1 -Flavor titan
```

使用说明见根目录README。`addon/tests/LureDetection.Tests.lua` 使用模拟接口验证钓鱼引导与可交互目标的组合条件、目标变化/轮询及未知状态、鱼竿附魔、死亡关闭及窗口尺寸/UI缩放下的物理像素定位。
