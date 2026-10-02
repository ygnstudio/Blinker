# Blinker

简体中文 | [English](README.en.md)

Blinker 是原生 macOS 菜单栏工具，把红绿灯增强、窗口预览与切换、窗口布局管理放在一起。应用规则和设置各有独立窗口；未配置普通左键动作时保留原生按钮行为。

## 能做什么

- **应用规则**：为红、黄、绿灯分别配置左键、右键、Option 点击、Fn 点击和长按动作。每个应用可独立启用重映射与悬停放大；支持复制规则、JSON 导入导出、撤销与重做。
- **悬停放大**：彩色按钮覆盖原生红绿灯，提供连续玻璃底托、可调大小、出现延迟和点击保护，以及四个可选扩展按钮。macOS 26+ 使用系统 Liquid Glass，旧系统使用原生材质回退。
- **窗口预览与切换**：⌥Tab 切换窗口，悬停 Dock 图标预览同应用窗口。整个预览面板可在 50% 至 150% 间缩放；同页排列，多窗口时滚动。可选择将标准 macOS 窗口标签页及 Safari 标签页单独列出。
- **窗口管理**：半屏、四分屏、三分屏、居中、最大化、跨显示器移动和还原上次布局。共用悬浮面板、快捷键与可选拖拽贴靠入口。
- **实验工作区**：显式开启后保存和恢复窗口排布。它按窗口特征匹配，不等同于恢复文稿或浏览器会话。

本文描述当前源码；已发布版本的功能以[发行说明](https://github.com/ygnstudio/Blinker/releases)为准。

## 开始使用

目标系统为 **macOS 15 或更新版本**，发行构建包含 Apple Silicon 与 Intel 架构。编译通过不代表已完成实机兼容性验证；最低系统、Intel 及核心交互和性能的完整验收仍待完成，已验证范围以每版发行说明为准。

推荐通过 [Homebrew](https://brew.sh/) 和项目的 [tap](https://github.com/ygnstudio/homebrew-ygn) 安装：

```bash
brew install --cask ygnstudio/ygn/blinker
```

更新前先退出 Blinker，再执行：

```bash
brew update
brew upgrade --cask ygnstudio/ygn/blinker
```

`brew update` 刷新软件信息，`brew upgrade` 安装 tap 中已提供的新版。tap 会定期校验并同步已发布稳定版，发布后可能有调度延迟；应用内没有自动更新器。命令说明见 [Homebrew 手册](https://docs.brew.sh/Manpage)。

不使用 Homebrew 时，从 [GitHub Releases](https://github.com/ygnstudio/Blinker/releases) 下载 DMG，将 `Blinker.app` 拖入“应用程序”；后续更新也需手动替换。

发行包采用 **ad-hoc 签名，不使用 Developer ID，也不经过 Apple 公证**。首次打开若出现开发者身份或公证提示，确认下载来源后，前往“系统设置 → 隐私与安全性 → 仍要打开”。Homebrew 安装同样可能需要这一步，详见 [Apple 打开应用说明](https://support.apple.com/zh-cn/102445)。

1. 首次启动查看引导，主动点击授权按钮并授予**辅助功能**权限；之后可在“通用”重新查看引导。
2. 点击菜单栏图标打开“应用规则”，添加应用，再打开该应用的编辑窗口。
3. 通过工具栏进入“设置”：按功能调整悬停、预览、布局与快捷键。“关于”提供版本、使用说明与反馈入口。
4. 若需要真实窗口缩略图，在“窗口预览与切换”中主动授予**屏幕录制**权限；未授权时仍可通过图标和标题切换。

操作细节与授权排障见[使用指南](docs/USER_GUIDE.md)。

## 权限与边界

- **辅助功能**用于识别按钮、窗口和受支持的标签页，并执行你选择的窗口操作。
- **屏幕录制为可选项**，仅用于窗口缩略图。采集只在预览打开时进行，图片缓存在内存中；红绿灯的玻璃效果无需录屏。
- Blinker 不上传规则、窗口标题或缩略图，不包含统计分析与自动网络请求。主动打开项目、帮助或反馈链接会交给浏览器访问。
- 自绘标题栏或标签栏可能不提供所需的辅助功能信息；后台标签页没有自己的缓存图像时显示图标与标题。标签预览上的“关闭窗口”和“最小化”作用于其所属窗口。
- 其他桌面的窗口、最小化窗口的新画面以及应用的最小窗口尺寸受 macOS 和目标应用限制。实验工作区的原桌面恢复依赖非公开系统接口。

## 开发

本地构建需要 Swift 6 工具链及包含 macOS 26 SDK 的 Xcode；运行系统最低仍为 macOS 15。

```bash
git clone https://github.com/ygnstudio/Blinker.git
cd Blinker
./Scripts/build-app.sh release
open ~/Applications/Blinker.app
```

开发构建安装到 `~/Applications/Blinker.app`，使用独立的 `com.ygnstudio.Blinker.dev` 标识。完整构建、测试、签名说明及 Intel 构建方式见[贡献指南](CONTRIBUTING.md)。

| 文档 | 内容 |
|---|---|
| [使用指南](docs/USER_GUIDE.md) | 页面分工、操作、权限与常见问题 |
| [架构说明](docs/ARCHITECTURE.md) | 模块边界、线程、性能与安全约束 |
| [窗口预览设计](docs/WINDOW_BROWSER.md) | 窗口与标签身份、缩略图、兼容性与参考项目 |
| [贡献指南](CONTRIBUTING.md) | 开发环境、检查命令与修改入口 |
| [发布与验收](docs/RELEASING.md) | 分发策略、候选版本检查与 tap 更新 |
| [更新日志](CHANGELOG.md) | 待发布变更与已发布版本记录 |

## 许可证

Copyright © 2026 ygnstudio。当前源码及基于本次许可变更发布的版本采用 **[GNU GPL v3.0 only（GPL-3.0-only）](LICENSE)**，不包含“或后续版本”选项。完整项目声明见 [NOTICE](NOTICE)。

GPLv3 **允许商业使用、收费分发和收费服务**。免费或收费分发都须履行许可证义务：保留版权、许可和免责声明，标明修改；分发二进制时按 GPLv3 提供该版本的对应源码（包括必要的构建与安装脚本）；分发修改后的受覆盖作品时继续使用 GPLv3，不得添加禁止商业使用等进一步限制。仅自行使用或私下修改，不要求因此向公众发布源码。具体权利和义务以 [LICENSE](LICENSE) 为准；商业分发说明参见 [GNU FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#DoesTheGPLAllowMoney)。

此前已经按 MIT 发布的版本仍保留原 MIT 授权，本次变更不撤销历史授权。第三方项目的许可证不因本项目变更而改变。参与项目请遵守[行为准则](CODE_OF_CONDUCT.md)。
