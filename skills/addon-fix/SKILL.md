---
name: addon-fix
description: 修复魔兽世界已安装第三方插件，遍历时光服或无限服的插件与补丁映射，核对既有修复、维护停止版本并应用所需补丁。用于插件修复和补丁维护指令。
---

# 插件修复

工程为 `C:\code\wow_tools`。先阅读工程 `AGENTS.md` 和 `skills/wow-tools/SKILL.md`，沿用独立临时 clone、分支、检查、提交推送、合入并推送 main、正式目录同步和部署流程。现有持续授权覆盖这些操作。

## 每次修复

用户指定服务器时处理该服务器，默认处理两服。`titan` 为时光服，`forerver` 为无限服。

1. 读取对应的 `addon_fix/<服务器>/mapping.json`。运行 `addon_fix/repair.ps1 -Flavor all -CheckOnly -ReportPath <临时报告路径>`，指定一服时替换 Flavor。它核对客户端身份，枚举所选服务器所有已安装插件和全部映射补丁，按实际插件目录名匹配并检查源码。读取报告中的全部补丁状态。
2. 对 `review` 项读取补丁、清单、实际 TOC 及相关安装源码，沿调用入口核对修复意图。文件哈希或版本变化后，核对当前实现的调用入口和处理链。对 `retired` 项核对停止版本和记录的源码依据。对 `applied` 项复用已经应用的本仓库修复。
3. 问题仍存在时，在临时 clone 中为当前版本维护适配补丁及原始、修复后 SHA256，将新清单加入该插件映射的 `variants`。同一插件的独立问题使用不同补丁 ID，部分问题已修复时分别维护剩余修复与已解决问题的版本边界。归档保留旧版本基线供旧安装使用。
4. 问题已由上游或其他实现解决时，在临时 clone 的映射中记录 `skipFromVersion` 及 `fixedEvidence`，说明已检查的函数、处理链和解决原因。记录当前实际证实的版本，确认更早版本同样已修复时才把边界向前移。已应用本仓库补丁的状态由 `applied` 表示。
5. 完成所选服务器所有待核对项，通过本地检查后提交、推送、合入 main 并推送。更新正式目录后运行 `addon_fix/repair.ps1 -Flavor all`，按用户指定范围替换 Flavor。它备份并应用需要的修复，复核结果哈希。再次检查报告并完成仍需核对的项目。

`-CheckOnly` 只读游戏目录，在临时副本验证补丁。退出码 2 表示有源码需要核对，继续处理报告中的项目。修复入口可传 `-Python` 指定 Python 3.9+，默认优先选择可用 Python 或 Codex 捆绑运行时。`-GameRoot` 配合单服，`-TitanGameRoot` / `-ForerverGameRoot` 配合默认两服。

## 归档和映射

```text
addon_fix/
  repair.ps1
  scripts/registry.py
  titan/mapping.json
  forerver/mapping.json
  forerver/DungeonsForever/background-scans/2.1.95/
    manifest.json
    fix.patch
```

映射 `plugins` 的键使用实际插件目录名称，每个插件对应补丁数组。每条记录维护以下内容。

- `id` 标识该插件的具体修复，`description` 说明修复意图。
- `variants` 是相对于该插件归档目录的清单路径。清单记录插件、补丁 ID、安装包基线版本、补丁文件哈希和每个受影响文件的原始、修复后哈希。已存在的其他源码修改需要核对并适配到新基线。
- `requires` 记录确有调用依赖的其他插件补丁。当前 Explore 缓存扫描依赖主插件停止清空缓存，入口会先核对这项关联修复，再把可应用项目一起部署。
- `skipFromVersion` 为确认已解决的起始版本，包含该版本及以后的版本。尚无证据时为 `null`。
- `fixedEvidence` 保存已检查版本、源码原因、相关文件及哈希和检查时间。停止范围内的源码改变后，入口会重新标为 `review`，核对通过后追加该版本证据。发现问题重新出现时，修正停止范围并维护相应版本的修复。

记录已修复版本可使用 `addon_fix/scripts/registry.py record-fixed --flavor forerver --addons-root <安装的 AddOns 目录> --review-file <临时审查 JSON>`。审查 JSON 包含 `plugin`、`patch`、`version`、`reason` 和 `files`。`files` 是已核对文件的 AddOns 相对路径数组，覆盖补丁涉及的源码，已移除的路径也列入。脚本核对安装版本，采集源码哈希并写入当前 clone 的映射。复杂的非数字版本范围通过源码核对后在映射维护适用变体。

## 检查和交付

统一运行 `skills/wow-tools/scripts/test-local.ps1`，它检查两服映射、补丁身份、归档哈希及修复入口的 PowerShell / Python 语法。追加 `-AddonFixFlavor forerver -AddonFixAddOnsRoot <已应用补丁的 AddOns 目录>` 可编译受影响 Lua，检查 TOC 依赖和清单中的加载顺序。时光服使用 titan。检查范围遵循工程的语法、语义和接口兼容性约定，游戏时序、交互及实际性能由用户验证。

报告每服安装插件数量、补丁应用结果、已确认解决及停止版本、仍待解决项目、提交推送和部署结果。当前 DungeonsForever 的周期调整记录在对应插件归档中。[周期说明](../../addon_fix/forerver/DungeonsForever/notes.md)
