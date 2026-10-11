# titan

泰坦时光服的独立插件源码：`wow_tools/`。保留原版2.1.1，接口版本38002，客户端为3.80.2；本次归档不修改其Lua或TOC。

安装目标：`C:\Program Files (x86)\World of Warcraft\_classic_titan_\Interface\AddOns\wow_tools`。先验证、提交并推送，再从仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\wow-tools\scripts\sync-local.ps1 -Flavor titan
```

使用说明见根目录README。`addon/tests/LureDetection.Tests.lua` 使用模拟接口验证鱼竿附魔、死亡关闭及窗口尺寸/UI缩放下的物理像素定位。
