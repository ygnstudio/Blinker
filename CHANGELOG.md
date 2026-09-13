# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- The enlarged overlay group is now clamped to the window's bounds
  intersected with its screen, so windowed windows no longer let the chips
  spill past the window edges (fullscreen stays covered too).
- The overlay only wakes up near the native traffic lights (or on top of an
  already-enlarged panel) instead of anywhere in the title bar band.
- A titlebar-material backdrop panel now covers the native buttons while the
  overlay is visible, so the small originals no longer peek through the gaps
  between enlarged chips. Hotspot mode keeps the title bar untouched.

## [0.2.2] - 2026-09-13

### Added
- Liquid Glass styling: overlay panels render on a system `NSGlassEffectView`
  chip tinted per button on macOS 26+ (translucent backdrop fallback on older
  systems), and the settings window uses native `glassEffect` cards with a
  graceful fallback below macOS 26.
- Settings window is now organized into tabs — Rules, Hover Enlargement and
  an About page with version and project links.

### Fixed
- Enlarged overlay buttons no longer stack on top of each other: panels are
  laid out as a group (original left-to-right order, centered on the native
  buttons' bounding box, minimum gap enforced) instead of each panel being
  centered on its own button, which overlapped heavily at larger sizes.
- Enlarged buttons are drawn as perfect circles instead of vertically
  squashed ellipses; symbols now scale with the button size, neighboring
  chips use a tight minimum gap so the native buttons stay covered, and
  the glass corner radius adapts to the panel size.
- Removed the hover preview labels: the enlarged panels were too small
  for readable four-character titles and the text overflowed the glass
  chips.

## [0.2.1] - 2026-09-13

### Added
- Hotspot mode for hover enlargement: invisible enlarged click zones
  around the native buttons — the title bar keeps its original look and
  clicks respond immediately (dwell does not apply). Selected in Settings
  next to the overlay mode.
- Legacy hover settings (v0.2.0, without a mode key) decode with defaults
  instead of resetting.

## [0.2.0] - 2026-09-13

### Added
- Hover enlargement overlays: enlarged traffic light buttons appear above
  the native ones while the pointer rests near a window's title bar, with
  an action preview label and a dwell progress ring for mis-click
  protection (size 18–48 pt, dwell 0–800 ms, scope all windows or
  rule apps only; configurable in Settings).
- Without a per-app rule, an enlarged click performs the button's native
  action, so enlargement works standalone.
- Left/right half tiling actions for the green button, implemented via
  direct window frame setting (visible frame halves).
- Shared `WindowActionPerformer` used by both the click interceptor and
  the hover overlays, so every action path behaves identically.

### Fixed
- Settings window now activates the app when opened from the menu bar;
  it previously appeared behind the frontmost app.
- Overlay clicks are gated with a short suppression window so the
  interceptor event tap can never execute the same click twice.
- `RuleStore` and `HoverOverlaySettings` mutate published state outside
  their locks, removing a potential re-entrant deadlock.
- Hover overlays no longer appear for Blinker's own windows, and a
  native button press failure is now logged instead of being silent.

### Changed
- GitHub Actions release action pinned to a commit SHA.

## [0.1.5] - 2026-09-13

### Fixed
- Window actions (close press, maximize) now target the clicked window,
  resolved by frame match, instead of the app's focused window — clicking the
  title bar of a background window no longer acts on the wrong window.
- Green-button maximize rewritten to set `AXPosition`/`AXSize` directly;
  the read-only `AXZoomWindow` attribute silently failed on most apps.
- AX messaging timeout capped at 250 ms so a hung app can no longer stall
  the system-wide event tap for seconds.
- Interceptor auto-starts (retry + trust-change notification) once the
  Accessibility permission is granted, without an app relaunch.
- Live interceptor status shown in the menu bar menu.

### Changed
- Unimplemented tile actions removed from the settings pickers.
- Bundle packaging unified in `Scripts/package-app.sh`, shared by the local
  build script and the release workflow; version derives from git tags.
- Release workflow now runs tests before publishing.

### Added
- Per-app remapping of the red (close) and green (zoom) traffic light buttons.
- Rule engine with enable/disable per rule; unlisted apps keep system defaults.
- Menu bar app shell (`MenuBarExtra`) with a settings window.
- CGEventTap + AX hit-test interceptor with title bar region pre-filtering.
- App bundle build scripts (`Scripts/build-app.sh`, `Scripts/package-app.sh`).
- CI: build, tests, SwiftLint & SwiftFormat checks.
- Structured logging (`os.Logger`, subsystem `com.ygnstudio.blinker`) across
  the interception pipeline for diagnosability.
