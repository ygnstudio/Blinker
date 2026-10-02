# 发布与验收

[返回贡献指南](../CONTRIBUTING.md)

## 分发约定

- 正式安装和更新优先通过 [Homebrew tap](https://github.com/ygnstudio/homebrew-ygn)，GitHub Release 的 DMG 为备用渠道。应用内不检查或下载更新。
- 发行包固定采用 ad-hoc 签名，不使用 Developer ID，也不经过 Apple 公证。首次打开可能需要用户在“系统设置 → 隐私与安全性”允许打开；组织策略可能禁止这一操作。安装器和 cask 不应关闭 Gatekeeper 或删除隔离属性。
- 稳定版使用 `vX.Y.Z` 标签；预发布版使用 `vX.Y.Z-alpha.N`、`vX.Y.Z-beta.N` 或 `vX.Y.Z-rc.N`，其中 N 为正整数。预发布版通过 DMG 测试，不进入 Homebrew 稳定通道。
- 当前源码使用 GPL-3.0-only，允许商业分发。二进制必须附带 `LICENSE`、`NOTICE`，并在同一发行页清楚提供对应版本的完整源码和构建脚本。不要用持续变动的分支链接替代发行版本的源码。

## 发布候选检查

发布前确定候选提交、版本和构建号，把实际验收结果记录在该次发布记录或 PR。`Unreleased` 表示尚未发布，只有真实发布时才改为版本号和日期。

- [ ] 工作区变更已核对，源码、更新日志、README 和发行说明描述同一候选版本；公开内容无私密路径、窗口内容或凭据。
- [ ] CI 的测试、SwiftLint、SwiftFormat、打包及发行校验脚本测试全部通过。
- [ ] 用发行构建生成包含 arm64 和 x86_64 的应用；版本、构建号、应用标识、最低系统版本、图标、中英文本和离线许可均正确。
- [ ] 校验最终 DMG 内的应用及 ad-hoc 签名，通过后生成 `SHA256SUMS.txt`，再验证校验和。不能仅验证打包前的可执行文件。
- [ ] 从候选下载包完成下表验收；未覆盖的平台、失败案例和已知限制写入发行说明。
- [ ] 发行页同时提供 DMG、校验和、对应标签源码、未公证安装说明、升级注意事项及已知限制。

标签工作流在发布前复用 CI，并由 `Scripts/validate-release.py` 检查标签和只读挂载后的 DMG。它验证架构、元数据、必要资源、许可文件与签名，但不会替代真实桌面操作和权限测试。脚本入口可用 `python3 Scripts/validate-release.py --help` 查看。

## 实机验收

目标最低系统是 macOS 15，发行二进制包含 Apple Silicon 和 Intel。**编译成功不等于这些组合已通过实机测试**。目前最低系统、Intel 和核心交互及性能的完整验收仍待完成；不得把下列清单本身当作通过记录。

| 范围 | 必须记录的验收 |
|---|---|
| 安装与升级 | 在无既有 Blinker 授权的账户中测试保留隔离属性的下载包、Gatekeeper 提示和首次引导；分别测试 Homebrew 与 DMG 安装。升级保留规则、设置和工作区，确认实际运行的是新版本。 |
| 系统与外观 | 记录 macOS 版本和芯片；分别覆盖最低系统、当前系统及 Intel，检查深浅色、减少透明度、多显示器和不同缩放。未测试的组合明确列出。 |
| 权限 | 辅助功能未授权、授权、撤销与重启；缩略图未授权、授权、关闭和撤销后清除缓存。关闭录屏时仍能按图标和标题切换。 |
| 红绿灯与布局 | 原生和悬浮按钮的配置动作、未配置动作、点击保护、暂停；绿色缩放与全屏按钮；贴靠、还原及跨屏，检查不支持移动或缩放的窗口。 |
| 预览与标签页 | Safari、访达和文本编辑的多窗口、标准标签页、最小化及相同标题；切换目标正确，后台标签页不借用其他图像，不支持的标签栏退回窗口。 |
| 键盘与鼠标 | 快速按下与松开 Option、重复打开、正反向切换、Esc、Return、⌘W、⌘M；Dock 到预览的鼠标移动和延迟设置；50% 与 150% 面板大小。 |
| 数据 | 旧规则迁移、导入导出往返、超限拒绝、失败不覆盖备份、撤销重做；实验工作区失配或应用退出时的反馈。 |
| 性能 | 在记录窗口数量和机器条件的情况下，测量空闲 CPU、唤醒、内存、首次和重复预览延迟；关闭面板后停止采集，反复开关无持续内存增长。用实测结果说明，不写未经测量的“零开销”。 |

发现操作会指向错误窗口、权限绕过、数据丢失或持续卡死时，应修复并重验后再发布。未覆盖的系统组合或目标应用兼容性可以作为测试版限制披露；不能因此宣称已全面支持。

## Homebrew 更新

发布流程分为两段：向 Blinker 源码仓推送 `vX.Y.Z` 标签后，远端 Release 工作流执行测试、构建和校验，再发布 DMG 与校验和；tap 随后定时检查 GitHub 的最新稳定版，校验通过才更新 `Casks/blinker.rb` 并自动提交、推送。预发布标签不进入稳定 cask。

tap 的 **Update Blinker cask** 工作流在默认分支每 15 分钟检查一次，计划时间为每小时第 7、22、37、52 分钟。发现新版后，它从 Blinker 官方仓库下载实际 DMG，将 SHA-256 与该发行页的 `SHA256SUMS.txt` 比对；草稿、预发布版或校验失败不修改 cask。自动检查遇到相同或更旧版本会跳过，不下载 DMG。流程仅使用 tap 自己的工作流权限，不需要额外的跨仓令牌。

需要立即检查时，在 tap 仓库的 Actions 中手动运行 **Update Blinker cask**，`tag` 留空检查最新稳定版，或填写指定的已发布稳定版标签；指定标签仍须校验实际 DMG，并拒绝降级或同版本校验值变化。也可在 tap 仓库的工作副本中预览或应用变更：

```bash
# 校验最新稳定版并展示差异
python3 Scripts/update-blinker.py --latest
# 核对差异后写入；本地执行仍需自行提交和推送
python3 Scripts/update-blinker.py --latest --write
# 指定标签时，将占位值替换为已发布稳定版；默认只展示差异
python3 Scripts/update-blinker.py vX.Y.Z
```

GitHub 的定时任务可能延迟，不能承诺发布后 15 分钟内必定完成同步。公开仓库连续 60 天无活动时，定时工作流会被停用；维护者应检查 Actions 状态并在需要时重新启用，参见 [GitHub 定时任务说明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。

tap 更新并发布后，从已安装版本测试：

```bash
brew update
brew upgrade --cask ygnstudio/ygn/blinker
```

确认版本升级、应用位置和数据保留。`brew update` 获取最新包信息，`brew upgrade` 安装 cask 中提供的新版；它们不会绕过 macOS 的应用信任检查。

命令与分发格式参考 [Homebrew 手册](https://docs.brew.sh/Manpage)、[Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)；首次打开流程参考 [Apple 的应用安全说明](https://support.apple.com/zh-cn/102445)。
