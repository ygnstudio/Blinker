# Contributing to Blinker

Start with [Architecture](docs/ARCHITECTURE.md) for ownership and threading, or [Window browser](docs/WINDOW_BROWSER.md) for preview and tab behavior. User-facing instructions belong in the [user guide](docs/USER_GUIDE.md), not in code comments or the About page.

## Build and run

Use a Swift 6 toolchain and Xcode with the macOS 26 SDK. The package uses Swift 5 language mode and targets macOS 15+. Release CI builds a universal arm64/x86_64 binary; compilation alone does not verify behavior on either architecture or the minimum OS.

```bash
git clone https://github.com/ygnstudio/Blinker.git
cd Blinker
swift build
swift test
python3 Scripts/test-package-app.py
./Scripts/build-app.sh release
open ~/Applications/Blinker.app
```

The local wrapper currently invokes an arm64 build. On an Intel development machine, build natively and use the shared packager:

```bash
swift build -c release
BLINKER_BUNDLE_ID=com.ygnstudio.Blinker.dev \
  ./Scripts/package-app.sh .build/release/Blinker dev 1 "$HOME/Applications/Blinker.app"
```

`build-app.sh` uses `~/Applications/Blinker.app` by default; `BLINKER_APP_PATH` can override it. Packaging accepts a non-symlink `.app` output; an existing bundle must have the expected bundle identifier. It assembles and verifies a staged bundle before replacing the output. A failed build or signature check leaves the installed copy intact. Keep one stable development path so the application you authorize is the one you run. Local builds use `com.ygnstudio.Blinker.dev`; releases use `com.ygnstudio.Blinker`. Each identity has its own system permissions and login-item registration.

Local packaging uses `BlinkerDev` when available and otherwise defaults to ad-hoc signing. An explicit `CODESIGN_IDENTITY` must be available (`-` explicitly selects ad-hoc); signing failures stop packaging rather than silently changing identities. Release CI explicitly sets `CODESIGN_IDENTITY=-`, with no Developer ID signing or Apple notarization. Signature changes can invalidate permission grants. The packager verifies its result; you can also verify an installed bundle before testing:

```bash
codesign --verify --deep --strict --verbose=2 ~/Applications/Blinker.app
```

The resource bundles, icon, version metadata and build SDK stamp are assembled by `Scripts/package-app.sh`. Use the bundle for UI testing; running the raw executable does not reproduce the complete app packaging.

## Checks

CI pins SwiftLint **0.62.2** and SwiftFormat **0.63.0** in `.github/workflows/ci.yml`:

```bash
swift test
python3 Scripts/test-package-app.py
python3 Scripts/test-validate-release.py
swiftlint lint --strict
swiftformat --lint .
git diff --check
```

Add focused tests for changed logic: imports, migrations, target identity, asynchronous result lifetime, geometry or rule behavior. A reversible copy/layout edit does not need a test that merely repeats the implementation. Native behavior still needs manual checks where relevant: permission fallback, focus, mouse travel, multiple displays, light/dark appearance and target-app compatibility. Record the actual checks in the PR; do not append dated machine-specific test logs to permanent design docs.

## Change entry points

| Change | Main owners |
|---|---|
| App-rule lists and editing | `Sources/BlinkerApp/ApplicationRules` |
| Global settings and About | `Sources/BlinkerApp/Settings` |
| Rule values, migration and transfer | `Sources/BlinkerCore/Models`, `RuleEngine` |
| Button interception and window actions | `Sources/BlinkerCore/AXInterceptor` |
| Hover geometry, controls and presentation | `Sources/BlinkerCore/HoverOverlay` |
| Window/tab discovery and thumbnails | `Sources/BlinkerCore/WindowBrowser` |
| Preview preferences, shortcuts and UI | `Sources/BlinkerApp/WindowBrowser` |
| Global placement shortcuts | `Sources/BlinkerApp/WindowManagement` |
| English and Chinese copy | Each target's `Resources/Localizable.xcstrings` |

### Actions and rules

Add action values in `ButtonAction`, implement them in the shared action performer, and expose them through the shared picker. Preserve defaults for fields absent from older rules; reject unknown action values rather than interpreting them as another action. A new rule field needs an explicit backward-compatible default and must round-trip through import/export, copy, undo and persistence. Extend the existing model instead of introducing separate versions for each UI entry point.

### Hover and preview layout

Keep hover calculations in `HoverOverlayGeometry` and preview sizing in `WindowBrowserGeometry`. Keep the full hover tray inside the owner-window/screen intersection. Preview scale applies to content and frame together. Selection, action routing and capture identity must survive layout changes; a thumbnail is never an action target.

### Tabs and asynchronous work

Tab discovery belongs in the AX worker, with bounded traversal. Do not scan webpage content to infer document tabs. An application-specific exception must remain scoped to that application; unsupported tab bars fall back to windows. Cached images belong to their own tab, and selection must be checked before and after capture.

## License and distribution

Homebrew is the primary distribution and update channel, with DMG downloads as an alternative. See the [release checklist](docs/RELEASING.md) for candidate validation, manual acceptance and the separate tap update. There is no built-in updater, and a source push alone does not update Homebrew.

New contributions to this version must be available under **GPL-3.0-only**. Submit only work you are entitled to license on those terms, retain applicable copyright notices, and check third-party license compatibility before copying code. The project's notice is [NOTICE](NOTICE); [LICENSE](LICENSE) contains the unmodified GNU GPLv3 text. This is not a copyright assignment, and historical MIT releases keep their original grants.

Commercial use and paid distribution are permitted. When distributing a modified covered work, preserve notices, identify modifications and license the covered work under GPLv3 without further restrictions. When distributing binaries, fulfill section 6's Corresponding Source requirements: provide the exact version's source and necessary build/install scripts through a compliant method. For downloadable releases, make the corresponding source available with equivalent access and clear directions alongside the binary. Include `LICENSE` and `NOTICE` in packaged releases. Do not substitute a moving branch, an inaccessible repository or the upstream unmodified source for the actual distributed version's source.

Private modifications alone do not require public publication. The complete license governs these obligations; this summary does not add a noncommercial restriction or alter third-party licenses. Official references: [GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html), [GPL-3.0-only identifier](https://spdx.org/licenses/GPL-3.0-only.html), [GNU distribution FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#DoesTheGPLAllowMoney).

## Maintenance and safety

- Keep AppKit view/window mutations on the main thread. Keep AX work, file I/O and discovery bounded and away from UI rendering paths.
- Never put screenshot capture, disk I/O or unbounded discovery on the event-tap callback. Its synchronous hit test is required to decide whether to consume a click; maintain timeouts and pass-through behavior.
- Use retained AX identities for actions. Do not select a target by title, position or thumbnail alone.
- Preserve user settings, existing uncommitted work, stored layouts and migration readers during refactors. Separate pure calculations and validation from UI and system effects.
- Request permissions through explicit UI. Keep thumbnails in memory and invalidate stale asynchronous work. Do not add analytics, uploads or automatic network requests.
- Read rule files with a size bound before decoding, reject invalid archives without partial edits, and keep a successful import one undoable change.
- Do not use private system APIs outside the explicit workspace experiment. Document fallback behavior and failures rather than claiming universal compatibility or unmeasured performance gains.

For bug reports, use the issue templates and include macOS version, target app and reproduction steps. Review any shared screenshot or rule file for private content first.
