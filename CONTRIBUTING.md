# Contributing to Blinker

Thanks for your interest in contributing!

## Development

```bash
git clone https://github.com/ygnstudio/Blinker.git
cd Blinker
swift build
swift test
./Scripts/build-app.sh   # produce Blinker.app for manual testing
```

CI runs the same gates: build, tests, SwiftLint (`--strict`) and SwiftFormat (`--lint`).

## Codebase tour

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first — it explains the module
layout, both data flows (click interception and hover enlarge), the threading
model, and why key decisions were made. Quick reference:

| Directory | One-liner |
|---|---|
| `Sources/BlinkerCore/AXInterceptor` | CGEventTap entry, AX hit-testing, action performance |
| `Sources/BlinkerCore/RuleEngine` | Pure `(bundleID, button) → action` lookup + persistence |
| `Sources/BlinkerCore/Models` | Value types: `AppRule`, `ButtonAction`, `TrafficButton` |
| `Sources/BlinkerCore/HoverOverlay` | Hover-to-enlarge overlay: geometry, chips, glass tray |
| `Sources/BlinkerCore/Permission` | Accessibility permission detection & onboarding |
| `Sources/BlinkerApp` | SwiftUI shell: menu bar, onboarding, three-tab settings |
| `Tests/BlinkerCoreTests` | Unit tests for core logic (no UI harness needed) |
| `Scripts` | Build/package/release tooling |

## Common tasks

### Add a new `ButtonAction` case

1. Add the case in `Sources/BlinkerCore/Models/ButtonAction.swift` (decode it
   leniently — unknown values must not break old persisted rules).
2. Map it to its native AX subrole in
   `Sources/BlinkerCore/AXInterceptor/WindowActionPerformer.swift`
   (`nativeSubrole(for:)`).
3. Expose it in the `ActionPicker` UI (`Sources/BlinkerApp/Settings/SettingsScreen.swift`).
4. Add unit tests: engine lookup + lenient decoding round-trip.

### Add a rule field (like `minimizeAction`)

1. Add the optional field to `AppRule` (`Sources/BlinkerCore/Models/AppRule.swift`)
   with lenient decoding so old stored rules still load.
2. Wire it through `RuleEngine.swift` (remove any hard-coded `nil` returns).
3. Add a picker row in `SettingsScreen.swift` (follow the color-dot pattern).
4. Add decoding-compatibility and engine tests.

### Adjust the enlarge layout

All geometry lives in `Sources/BlinkerCore/HoverOverlay/HoverOverlayGeometry.swift`:
`panelFrames` (whole-group layout, gap, clamping) and `isCursorInTriggerZone`
(trigger padding). Geometry changes must come with
`HoverOverlayGeometryTests` updates; keep the window∩screen clamping intact.

## Ground rules

- Follow the Swift API Design Guidelines; use lowerCamelCase for variables
  and functions, UpperCamelCase for types, and semantic (non-abbreviated) names.
- Add or update unit tests for changes in `BlinkerCore`.
- Performance matters: the event tap runs on every mouse click. Avoid
  allocations in the hot path and keep AX calls behind the cheap pre-filters.
- Do not add network access, analytics, or telemetry — Blinker is
  local-only by design.

## Reporting issues

Use the issue templates — they collect macOS version, hardware, and the
target app's bundle identifier, which is exactly what interception
problems need.
