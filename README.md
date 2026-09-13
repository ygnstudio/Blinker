# Blinker

**EN** | [中文](#中文)

Blinker is a native macOS menu bar app that remaps the window traffic light
buttons (close / minimize / zoom) on a per-application basis, and enlarges
them on hover so they are easier to see and click.

- Red button → quit the app instead of closing a window (configurable)
- Green button → maximize (zoom) instead of fullscreen (configurable)
- Yellow button and window tiling (left/right half) are remappable too
- Hover enlargement with action preview and mis-click protection
- Rules only apply to apps you add; everything else keeps system defaults

### Hover enlargement

When the pointer rests near a window's traffic lights, enlarged button
overlays appear above them:

- Adjustable size (18–48 pt) and dwell delay (0–800 ms) — the dwell ring
  must fill before a click registers, so brushing past never triggers
- Action preview labels ("Quit Safari") show what a click will do
- Without a rule, an enlarged click still performs the button's native
  action, so enlargement is useful on its own
- Scope: all windows, or only apps that have rules
- Two modes: **overlay** (draws enlarged buttons with preview and dwell)
  or **hotspot** (invisible enlarged click zones; the title bar keeps its
  original look and clicks respond immediately)

### Settings

The menu bar menu opens the settings window with three sections: the
per-app rule table (red / green actions as dropdowns), the hover
enlargement section described above, and status / help notes.

### Known limitations

- Secure Input (e.g. password fields) temporarily disables event
  interception; buttons fall back to system behavior
- Apps with fully custom title bars (some Electron apps) may expose no
  standard accessibility buttons and cannot be intercepted

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
- 黄灯与左右半屏动作同样可重映射
- 悬停放大：动作预览 + 防误触 dwell
- 规则只对你添加的应用生效，其余保持系统默认

### 悬停放大

鼠标停在窗口红绿灯附近时，按钮上方会出现放大覆盖层：

- 尺寸（18–48 pt）与防误触延迟（0–800 ms）可调——进度环填满才响应点击，路过不会误触
- 悬停时显示动作预览（如「退出 Safari」），点击前明确后果
- 未配置规则时，放大的点击执行按钮原生动作，放大本身即有价值
- 作用范围可选：全部窗口，或仅配置了规则的应用
- 两种模式：**覆盖放大**（绘制放大按钮，带预览与防误触）或**纯热区**
  （外观完全不变，仅扩大不可见点击区，点击立即响应）

### 设置

菜单栏菜单打开设置窗口，含三个区块：按应用规则表（红/绿动作下拉）、
悬停放大区块（如上）、状态与帮助说明。

### 已知限制

- 安全输入激活时（如密码框）事件拦截临时失效，按钮回退系统行为
- 完全自绘标题栏的应用（部分 Electron 应用）无标准辅助功能按钮，无法拦截

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
