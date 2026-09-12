# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
