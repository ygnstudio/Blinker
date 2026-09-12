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

## Ground rules

- Follow the Swift API Design Guidelines; use lowerCamelCase for variables
  and functions, UpperCamelCase for types, and semantic (non-abbreviated) names.
- CI runs SwiftLint (`--strict`) and SwiftFormat (`--lint`); make sure both
  pass locally before opening a PR.
- Add or update unit tests for changes in `BlinkerCore`.
- Performance matters: the event tap runs on every mouse click. Avoid
  allocations in the hot path and keep AX calls behind the cheap pre-filters.
- Do not add network access, analytics, or telemetry — Blinker is
  local-only by design.

## Reporting issues

Include macOS version, hardware, and the target app's bundle identifier
when reporting interception problems.
