# 架构 / Architecture

Blinker 是一个原生 macOS 菜单栏应用，拦截窗口红绿灯按钮的点击并按应用重定义其行为，同时提供悬停放大的覆盖层。本文描述模块划分、两条核心数据流、线程与坐标系模型，以及关键设计决策的取舍原因。

Blinker is a native macOS menu bar app that intercepts clicks on window traffic-light buttons and remaps their behavior per app, with a hover-to-enlarge overlay. This document describes the module layout, the two core data flows, the threading and coordinate-space models, and the reasoning behind key design decisions.

---

## 中文

### 模块地图

```
Sources/
├── BlinkerCore/               # 无 UI 的核心逻辑（可独立测试）
│   ├── AXInterceptor/         # 事件拦截与动作执行
│   │   ├── TrafficLightInterceptor.swift   # CGEventTap 入口 + 4 步点击管线
│   │   ├── AXWindowQuery.swift             # AXUIElement 查询：命中的窗口/按钮
│   │   └── WindowActionPerformer.swift     # 通过 AXPress 执行重映射后的动作
│   ├── RuleEngine/            # 纯查找，无副作用
│   │   ├── RuleEngine.swift   # (bundleID, 按钮) → ButtonAction?
│   │   └── RuleStore.swift    # 规则的持久化（UserDefaults）
│   ├── Models/                # AppRule / ButtonAction / TrafficButton 值类型
│   ├── HoverOverlay/          # 悬停放大覆盖层（10 个文件，见下）
│   └── Permission/            # 辅助功能权限检测与引导
└── BlinkerApp/                # SwiftUI 应用壳
    ├── AppDelegate.swift      # 长生命周期状态：拦截器 + 覆盖层 + 两个 store
    ├── BlinkerApp.swift       # @main，MenuBarExtra 场景
    ├── Onboarding/            # 首次启动权限引导
    └── Settings/              # 三 tab 设置页 + 应用库选择器

Tests/BlinkerCoreTests/         # 仅测 BlinkerCore（纯逻辑，无需沙盒 UI）
Scripts/                        # build-app.sh / package-app.sh / release 产物
```

`HoverOverlay/` 内部再分三层：

| 层 | 文件 | 职责 |
|---|---|---|
| 编排 | `HoverOverlayController(+Detection/+Panels)` | 鼠标跟踪、触发判定、面板生命周期、异步采样调度 |
| 几何 | `HoverOverlayGeometry` | `panelFrames`（整组布局 + 窗口∩屏幕钳制）、触发区判定 |
| 呈现 | `HoverOverlayPanel` / `HoverOverlayMaskPanel` | 放大芯片（NSGlassEffectView）/ 原生按钮遮罩 |
| 采样 | `TitlebarSampler` / `TitlebarPixelScan` | SCScreenshotManager 抓条带 → 逐列干净度分析 → 选最宽干净段 |

### 数据流一：点击拦截（冷路径，每次点击）

```
CGEventTap（独立线程）
  → TrafficLightInterceptor：便宜前置过滤（只看鼠标按下 + 坐标在标题栏带）
  → AXWindowQuery：AXUIElement 查询命中窗口与按钮（工作队列）
  → RuleEngine：bundleID + 按钮 → 重映射动作（纯查找）
  → WindowActionPerformer：AXPress 原生执行（红=退出等）
```

前置过滤是性能关键：绝大多数点击在第一步就被丢弃，不会产生 AX 调用。

### 数据流二：悬停放大（热路径，鼠标移动）

```
鼠标移动检测（事件节流）
  → HoverOverlayController+Detection：isCursorInTriggerZone（按钮组外扩 12pt）
  → HoverOverlayGeometry.panelFrames：整组布局 + 钳制到窗口∩屏幕
  → rebuildPanels：先铺遮罩面板（Level = popUpMenu - 1），再铺放大芯片
  → （采样模式）scheduleSampledBackdrop：异步 SCScreenshotManager 抓条带
     → TitlebarPixelScan 逐列分析 → 最宽干净段拉伸 → 回填遮罩
```

采样回填带 staleness 守卫（`isOverlayVisible` / `panelPID` / `panelSignature`），异步结果返回时若上下文已变则直接丢弃。

### 线程模型

- **CGEventTap 回调**：独立线程，只做便宜过滤，不碰 UI。
- **AX 查询与动作执行**：工作队列（串行），避免 AX 调用阻塞 tap。
- **主线程**：只负责 NSPanel 显示/隐藏与 SwiftUI 设置页。
- **屏幕采样**：`userInitiated` Task，结果经 staleness 校验后回主线程贴图。

### 坐标系

`HoverOverlayGeometry` 统一使用**屏幕全局坐标**（`CGWindowListCopyWindowInfo` 与 NSPanel frame 的交集空间）。AX 返回的窗口/按钮坐标已换算为全局坐标后再参与布局；所有钳制在 `overlayContainerBounds`（窗口 ∩ 屏幕）内完成。

### 关键设计决策

| 决策 | 原因 |
|---|---|
| NSPanel 覆盖层 + CGEventTap 拦截（而非 AXObserver 抢点击） | 保留原生按钮的可访问性语义；覆盖层只做视觉替换 |
| `SCScreenshotManager.captureImage`（SDK 26） | `CGWindowListCreateImage` 在 SDK 26 硬性不可用，无迁移路径 |
| 双遮罩方案（玻璃默认 / 真实采样可选） | 采样需屏幕录制权限；默认零权限，用户显式 opt-in 才申请 |
| 不沙盒，Developer ID + 公证官网直发 | 辅助功能权限与沙盒互斥，无法上 MAS |
| 无日志/统计/遥测 | 隐私优先，local-only 是产品承诺（见 CONTRIBUTING） |
| deployment target macOS 15 | 覆盖 Intel 末代系统（26 是最后支持 Intel 的版本），核心 API 无 `#available` 分支压力 |

---

## English

### Module map

```
Sources/
├── BlinkerCore/               # UI-free core logic (unit-testable in isolation)
│   ├── AXInterceptor/         # Event tap + action performance
│   │   ├── TrafficLightInterceptor.swift   # CGEventTap entry + 4-step click pipeline
│   │   ├── AXWindowQuery.swift             # AXUIElement queries: hit window/button
│   │   └── WindowActionPerformer.swift     # Performs remapped actions via AXPress
│   ├── RuleEngine/            # Pure lookup, no side effects
│   │   ├── RuleEngine.swift   # (bundleID, button) → ButtonAction?
│   │   └── RuleStore.swift    # Rule persistence (UserDefaults)
│   ├── Models/                # AppRule / ButtonAction / TrafficButton value types
│   ├── HoverOverlay/          # Hover-to-enlarge overlay (see table below)
│   └── Permission/            # Accessibility permission detection & onboarding
└── BlinkerApp/                # SwiftUI app shell
    ├── AppDelegate.swift      # Long-lived state: interceptor + overlay + stores
    ├── BlinkerApp.swift       # @main, MenuBarExtra scene
    ├── Onboarding/            # First-launch permission flow
    └── Settings/              # Three-tab settings + app library picker

Tests/BlinkerCoreTests/         # BlinkerCore only (pure logic, no UI harness)
Scripts/                        # build-app.sh / package-app.sh / release artifacts
```

Inside `HoverOverlay/`:

| Layer | Files | Responsibility |
|---|---|---|
| Orchestration | `HoverOverlayController(+Detection/+Panels)` | Mouse tracking, trigger decision, panel lifecycle, async sampling |
| Geometry | `HoverOverlayGeometry` | `panelFrames` (whole-group layout, clamped to window∩screen), trigger zone |
| Presentation | `HoverOverlayPanel` / `HoverOverlayMaskPanel` | Enlarged chips (NSGlassEffectView) / native-button mask |
| Sampling | `TitlebarSampler` / `TitlebarPixelScan` | SCScreenshotManager capture → per-column cleanliness scan → widest clean run |

### Data flow 1: click interception (cold path, per click)

```
CGEventTap (dedicated thread)
  → TrafficLightInterceptor: cheap pre-filter (mouse-down + title-bar band)
  → AXWindowQuery: AXUIElement hit-testing (worker queue)
  → RuleEngine: bundleID + button → remapped action (pure lookup)
  → WindowActionPerformer: native AXPress (e.g. red = quit)
```

The pre-filter is the performance contract: most clicks die in step one and never reach AX.

### Data flow 2: hover enlarge (hot path, per mouse move)

```
Mouse-move detection (throttled)
  → HoverOverlayController+Detection: isCursorInTriggerZone (button group + 12pt)
  → HoverOverlayGeometry.panelFrames: whole-group layout, clamped to window∩screen
  → rebuildPanels: mask panel first (Level = popUpMenu - 1), then enlarged chips
  → (sampled style) scheduleSampledBackdrop: async SCScreenshotManager capture
     → TitlebarPixelScan column analysis → widest clean run → mask backfill
```

The sampled backfill carries staleness guards (`isOverlayVisible` / `panelPID` / `panelSignature`); stale results are dropped on arrival.

### Threading model

- **CGEventTap callback**: dedicated thread; cheap filtering only, never touches UI.
- **AX queries & action performance**: serial worker queue so AX calls never block the tap.
- **Main thread**: NSPanel show/hide and SwiftUI settings only.
- **Screen sampling**: `userInitiated` Task; results re-validated for staleness before being applied on the main thread.

### Coordinate spaces

`HoverOverlayGeometry` works exclusively in **global screen coordinates**. AX-returned window/button rects are converted to global coordinates before layout; all clamping happens inside `overlayContainerBounds` (window ∩ screen).

### Key design decisions

| Decision | Rationale |
|---|---|
| NSPanel overlays + CGEventTap (not AXObserver click stealing) | Preserves native button accessibility semantics; overlays only replace visuals |
| `SCScreenshotManager.captureImage` (SDK 26) | `CGWindowListCreateImage` is hard-unavailable on SDK 26 |
| Dual mask styles (glass default / sampled opt-in) | Sampling needs Screen Recording permission; default is zero-permission |
| Non-sandboxed, Developer ID + notarized website distribution | Accessibility permission is mutually exclusive with App Sandbox |
| No logging / statistics / telemetry | Privacy-first; local-only is a product promise (see CONTRIBUTING) |
| Deployment target macOS 15 | Covers final Intel systems; no `#available` branching pressure |
