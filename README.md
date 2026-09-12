# Blinker

**EN** | [中文](#中文)

Blinker is a native macOS menu bar app that remaps the window traffic light
buttons (close / minimize / zoom) on a per-application basis, and enlarges
them on hover so they are easier to see and click.

- Red button → quit the app instead of closing a window (configurable)
- Green button → maximize (zoom) instead of fullscreen (configurable)
- Hover enlargement with action preview and mis-click protection
- Rules only apply to apps you add; everything else keeps system defaults

Requirements: macOS 15+, Apple Silicon & Intel.
License: MIT.

## Build

```bash
git clone https://github.com/ygnstudio/Blinker.git
cd Blinker
./Scripts/build-app.sh          # produces Blinker.app
open Blinker.app
```

Or run tests:

```bash
swift test
```

## Permissions

Blinker needs **Accessibility** permission (System Settings → Privacy &
Security → Accessibility) to read and rewrite other apps' window buttons.
All processing is local; no network requests, no analytics.

---

# 中文

Blinker 是一个原生 macOS 菜单栏应用，可按应用单独重定义窗口红绿灯按钮的行为，并在鼠标悬停时放大按钮，让它们更容易看清和点击。

- 红灯 → 退出应用（而非仅关闭窗口），可配置
- 绿灯 → 最大化（而非全屏），可配置
- 悬停放大：动作预览 + 防误触 dwell
- 规则只对你添加的应用生效，其余保持系统默认

系统要求：macOS 15+，支持 Apple Silicon 与 Intel。
开源协议：MIT。

## 构建

```bash
git clone https://github.com/ygnstudio/Blinker.git
cd Blinker
./Scripts/build-app.sh          # 产出 Blinker.app
open Blinker.app
```

运行测试：

```bash
swift test
```

## 权限说明

Blinker 需要**辅助功能**权限（系统设置 → 隐私与安全性 → 辅助功能），
用于读取并改写其他应用窗口的红绿灯按钮。所有处理均在本地完成：
无网络请求、无数据收集。
