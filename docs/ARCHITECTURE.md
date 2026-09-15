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
│   │   ├── TrafficLightInterceptor.swift   # CGEventTap 入口 + 4 步点击管线（右键/⌥/🌐/长按）
│   │   ├── AXWindowQuery.swift             # AXUIElement 查询：命中的窗口/按钮
│   │   ├── WindowActionPerformer.swift     # 通过 AXPress/AX 帧写入执行重映射后的动作
│   │   ├── WindowGeometry.swift            # 纯摆放数学：17 种动作的目标帧
│   │   ├── WindowSnapper.swift             # 拖拽贴靠：observe-only tap + 预览面板
│   │   ├── SnapZones.swift                 # 纯命中测试：光标 → 贴靠分区
│   │   ├── FrontWindowActionPerformer.swift # 对最前窗口执行动作（面板/快捷键共用）
│   │   ├── WorkspaceManager.swift          # 工作区：CGWindowList 采集 + AX 恢复
│   │   ├── WorkspaceStore.swift            # 工作区持久化（UserDefaults）
│   │   └── SpaceSwitcher.swift             # 模拟 ⌃←/⌃→ 切换桌面
│   ├── RuleEngine/            # 纯查找，无副作用
│   │   ├── RuleEngine.swift   # (bundleID, 按钮) → ButtonAction?
│   │   └── RuleStore.swift    # 规则的持久化（UserDefaults）
│   ├── Models/                # AppRule / ButtonAction / TrafficButton 值类型
│   ├── HoverOverlay/          # 悬停放大覆盖层（10 个文件，见下）
│   └── Permission/            # 辅助功能权限检测与引导
└── BlinkerApp/                # SwiftUI 应用壳
    ├── AppDelegate.swift      # 长生命周期状态：拦截器 + 覆盖层 + 贴靠 + 快捷键 + store
    ├── BlinkerApp.swift       # @main，MenuBarExtra 场景
    ├── Onboarding/            # 首次启动权限引导
    ├── Settings/              # 五 tab 设置页 + 应用库选择器
    └── WindowManagement/      # 全局快捷键：Carbon 注册 + 录制 + 持久化

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
鼠标移动检测（事件节流 + 拖拽停摆 + latest-wins 合并）
  → HoverOverlayController+Detection：isCursorInTriggerZone（按钮组外扩 12pt）
  → HoverOverlayGeometry.panelFrames：整组左缘锚定布局 + 钳制到窗口∩屏幕
  → rebuildPanels：先铺玻璃托盘（Level = popUpMenu - 1，点击穿透 + 三灯受控辉光），再铺放大芯片
```

### 线程模型

- **CGEventTap 回调**：专用线程（拦截器与悬停检测各持一个 tap 线程），永不触碰主线程。命中标题栏带的点击会在拦截器回调内同步做一次 AX hit test（250 ms 消息超时上限）——吞事件必须同步决策，这是唯一留在 tap 线程的 AX 调用。
- **AX 动作执行**：串行工作队列，动作执行不占用 tap 线程。
- **主线程**：只负责 NSPanel 显示/隐藏与 SwiftUI 设置页。

### 坐标系

`HoverOverlayGeometry` 统一使用**屏幕全局坐标**（`CGWindowListCopyWindowInfo` 与 NSPanel frame 的交集空间）。AX 返回的窗口/按钮坐标已换算为全局坐标后再参与布局；所有钳制在 `overlayContainerBounds`（窗口 ∩ 屏幕）内完成。AppKit（底左原点）与 AX/CG（顶左原点）之间的换轴枢轴统一为 `AXQuery.coordinatePivotY`（主屏顶边）——不要用全屏 `max()`，副屏摆在主屏上方时会错位。

### 关键设计决策

| 决策 | 原因 |
|---|---|
| NSPanel 覆盖层 + CGEventTap 拦截（而非 AXObserver 抢点击） | 保留原生按钮的可访问性语义；覆盖层只做视觉替换 |
| 玻璃托盘 + 不透明放大珠（而非采样遮罩） | 玻璃由系统合成器实时取景，任意背景自动融合，零权限零延迟；不透明珠从源头杜绝偏色；受控辉光（衰减边界 < 托盘边距）吸收原生按钮残影，永不溢出或被裁剪 |
| 布局左缘锚定（而非组中心对齐） | 放大珠组从原生组左缘向右生长：红灯玻璃残影始终被首珠盖住，组也永不越出窗口左缘 |
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
│   │   ├── TrafficLightInterceptor.swift   # CGEventTap entry + 4-step click pipeline (right/⌥/🌐/long press)
│   │   ├── AXWindowQuery.swift             # AXUIElement queries: hit window/button
│   │   ├── WindowActionPerformer.swift     # Performs remapped actions via AXPress / AX frames
│   │   ├── WindowGeometry.swift            # Pure placement math: target frames for all actions
│   │   ├── WindowSnapper.swift             # Drag-to-snap: observe-only tap + preview panel
│   │   ├── SnapZones.swift                 # Pure hit-testing: cursor → snap placement
│   │   ├── FrontWindowActionPerformer.swift # Acts on the frontmost window (panel/hotkeys)
│   │   ├── WorkspaceManager.swift          # Workspaces: CGWindowList capture + AX restore
│   │   ├── WorkspaceStore.swift            # Workspace persistence (UserDefaults)
│   │   └── SpaceSwitcher.swift             # Simulated ⌃←/⌃→ desktop switching
│   ├── RuleEngine/            # Pure lookup, no side effects
│   │   ├── RuleEngine.swift   # (bundleID, button) → ButtonAction?
│   │   └── RuleStore.swift    # Rule persistence (UserDefaults)
│   ├── Models/                # AppRule / ButtonAction / TrafficButton value types
│   ├── HoverOverlay/          # Hover-to-enlarge overlay (see table below)
│   └── Permission/            # Accessibility permission detection & onboarding
└── BlinkerApp/                # SwiftUI app shell
    ├── AppDelegate.swift      # Long-lived state: interceptor + overlay + snapper + hotkeys
    ├── BlinkerApp.swift       # @main, MenuBarExtra scene
    ├── Onboarding/            # First-launch permission flow
    ├── Settings/              # Five-tab settings + app library picker
    └── WindowManagement/      # Global hotkeys: Carbon registration + recorder

Tests/BlinkerCoreTests/         # BlinkerCore only (pure logic, no UI harness)
Scripts/                        # build-app.sh / package-app.sh / release artifacts
```

Inside `HoverOverlay/`:

| Layer | Files | Responsibility |
|---|---|---|
| Orchestration | `HoverOverlayController(+Detection/+Panels)` | Mouse tracking, trigger decision, panel lifecycle |
| Geometry | `HoverOverlayGeometry` | `panelFrames` (leading-anchored group layout, clamped to window∩screen), trigger zone |
| Presentation | `HoverOverlayPanel` / `HoverOverlayTrayPanel` | Enlarged chips (opaque vivid dots) / click-through glass tray with bounded glows |

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
Mouse-move detection (throttled + drag stand-down + latest-wins coalescing)
  → HoverOverlayController+Detection: isCursorInTriggerZone (button group + 12pt)
  → HoverOverlayGeometry.panelFrames: leading-anchored group layout, clamped to window∩screen
  → rebuildPanels: glass tray first (Level = popUpMenu - 1, click-through + bounded dot glows), then enlarged chips
```

### Threading model

- **CGEventTap callbacks**: dedicated threads (the interceptor and hover detection each own one); the main thread is never touched. Clicks inside a title-bar band run one synchronous AX hit test inside the interceptor callback (capped at 250 ms messaging timeout) — swallowing an event requires a synchronous decision, the only AX call that stays on the tap thread.
- **AX action performance**: serial worker queue; action execution never occupies the tap thread.
- **Main thread**: NSPanel show/hide and SwiftUI settings only.

### Coordinate spaces

`HoverOverlayGeometry` works exclusively in **global screen coordinates**. AX-returned window/button rects are converted to global coordinates before layout; all clamping happens inside `overlayContainerBounds` (window ∩ screen). The y-axis pivot between AppKit (bottom-left origin) and AX/CG (top-left origin) is unified in `AXQuery.coordinatePivotY` (the primary screen's top edge) — never use a max() across all screens, which breaks when a secondary display sits above the primary.

### Key design decisions

| Decision | Rationale |
|---|---|
| NSPanel overlays + CGEventTap (not AXObserver click stealing) | Preserves native button accessibility semantics; overlays only replace visuals |
| Glass tray + opaque enlarged dots (not a sampled mask) | The glass is composited live by the system — any background blends with zero permission and zero latency; opaque dots eliminate color bleed at the source; bounded glows (decay edge < tray margin) absorb the native buttons' ghosts without ever spilling or clipping |
| Leading-edge-anchored layout (not group-center alignment) | The enlarged group grows rightward from the native group's left edge: the red button's glass ghost stays covered by the first dot, and the group never crosses the window's left edge |
| Non-sandboxed, Developer ID + notarized website distribution | Accessibility permission is mutually exclusive with App Sandbox |
| No logging / statistics / telemetry | Privacy-first; local-only is a product promise (see CONTRIBUTING) |
| Deployment target macOS 15 | Covers final Intel systems; no `#available` branching pressure |
