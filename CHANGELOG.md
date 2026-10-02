# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.5.0] - 2026-10-03

### Added

- A Permissions settings page and shared permission assistant for settings and onboarding, with a draggable app icon, Show in Finder, status checks and reauthorization instructions; granting access still requires confirmation in System Settings.

### Fixed

- Local builds now use SwiftPM's reported binary path, including newer build-engine layouts.
- Packaging now requires an explicit, non-empty bundle identifier before modifying output, preventing accidental use of the release identity.

## [0.4.0] - 2026-10-03

### Added

- Window previews through Option-Tab and Dock hover, with configurable delays, optional thumbnails, minimized-window caches and per-app window lists. Standard macOS window tabs and Safari tabs can appear as separate items.
- Preview panel scaling from 50% to 150%, with the frame, controls and content scaling together. Items share one grid and scroll when they exceed the available screen space.
- Independent app-rule windows and editors, searchable application selection, per-app hover controls, rule copying, JSON import/export, undo/redo and temporary pause controls.
- Thirds and previous-layout restore for window placement, shared action feedback, compatibility diagnostics and a first-launch guide that requests permissions only after an explicit button press.
- Offline license and project notices in About and in the app bundle.

### Changed

- Reorganized native settings into General, Hover Enlargement, Window Previews & Switching, Window Management, Experimental Features and About. Workspace controls now live under the explicit experimental switch.
- Hover controls cover the native traffic lights, retain their colors and share a continuous glass tray. macOS 26+ uses system Liquid Glass; earlier systems use native fallback materials.
- Rule import and export share the same validation and limits of 1000 rules and 1 MiB. Exports use compact JSON; invalid or oversized exports fail before replacing an existing backup.
- The current source is licensed under GPL-3.0-only. Commercial use and paid distribution are permitted subject to GPLv3 obligations. Previously released MIT versions retain their original grants.
- Homebrew is the primary installation and update path; DMG remains available. Releases explicitly use ad-hoc signing without Developer ID or Apple notarization. Users may need to allow the app in Privacy & Security.

### Removed

- Invisible hit-area mode and sampled title-bar backdrops. Hover enlargement uses visible covering controls and native materials without screen capture.
- Desktop-switch shortcut actions. Experimental workspace restoration remains available, including its separately enabled original-Space option.

### Fixed

- Hover trays extending beyond their owner window, cramped button spacing, inconsistent preview appearance and missing tray backgrounds.
- Native green-button fallback on windows that expose a zoom button without a fullscreen button.
- Thumbnail matching that could accept a reused window ID or a conflicting title. Tab capture checks the containing window while keeping each tab's own image identity.
- Keyboard events leaking to another app while the switcher opens, and rapid Option release leaving the switcher open. Switcher shortcuts now follow the panel's selection and dismissal state.
- Window-management and hover-toggle hotkeys now request exclusive registration instead of silently sharing a combination with another app. Registration errors appear inline with a retry control, preserving the configured binding; this does not detect every shortcut intercepted by macOS.
- Rule exports that could not be imported again after JSON expansion or accumulated imports.
- Packaging failures replacing an installed app. Packaging verifies a staged bundle first and rejects unsafe output paths or a different bundle identifier.

### Known limits

- macOS 15+ is the deployment target and release builds include arm64 and x86_64. Compilation does not replace runtime testing; minimum-OS, Intel, core compatibility and performance acceptance remain incomplete.
- Custom tab bars and windows on other Spaces may not be discoverable. Inactive tabs and minimized windows use their own cached image when available, otherwise an icon and title. Tab preview actions such as Close Window apply to the containing window.
- Unconfigured enhanced clicks on the hover controls perform no action; an unconfigured ordinary left click presses the native button.
- Experimental workspaces match existing windows and do not reopen documents or sessions. Restoring an original Space relies on private system APIs.

## [0.3.0] - 2026-09-17

### Added
- **Transparent management HUD**: the window-manager HUD floats on a
  see-through dim backdrop with dark-appearance content, reading as glass
  over the window it acts on, readable against any background.

### Fixed
- **Trigger zone**: the hover overlay wakes only at the native
  traffic-light corner (plus 12 pt) instead of a wide band of the title
  bar — previously the wake-up area ballooned across the whole enlarged
  group, especially wide with extra chips enabled.
- **First-hover glass flash**: the tray no longer flashes an unblended
  light-or-dark rectangle before turning translucent. The tray and HUD
  panels are kept alive across hide/show cycles and reused, so every
  appearance after the first is instant and clean.
- **First-hover ghost**: tray glows render from the very first frame
  (only the glass backdrop fades in), so the native buttons no longer
  peek through the gaps between the enlarged chips during the fade.
- **Corrupt store safety**: an undecodable rules or workspaces blob is
  quarantined under a `.corrupt-backup` key instead of being silently
  overwritten by the next save.
- **Workspace restore honesty**: the restored-window count now reflects
  windows that actually moved (apps rejecting the position write are no
  longer counted).

### Changed
- Internal refactor: AppDelegate split into focused collaborators
  (status item, settings window, interception coordinator); HUD manager
  and dwell controller extracted; settings rebuilt on environment
  injection. No user-visible change beyond the fixes above.

## [0.2.3] - 2026-09-16

### Added
- **Workspaces**: capture every visible window's position and size as a
  named layout and restore it in one click (per-app largest-window capture,
  skipped apps reported). Saving under an existing name overwrites.
- **Desktop switching** buttons that synthesize the system ⌃← / ⌃→ shortcut.
- **Window-manager hover chip**: the traffic-light overlay gains a chip that
  opens a compact HUD (placement grid + workspace restore) acting on the
  hovered window. The settings instant-action panel was removed — actions
  always target the hovered window, never the frontmost one.
- **Click variants work through the hover overlay**: right click, ⌥/🌐
  clicks and long press now resolve on the enlarged buttons, matching the
  interceptor's behavior for clicks on the real ones.

### Removed
- **Scenario rule profiles**: the rules tab returns to a single flat table;
  any profile-era data migrates back automatically.
- **Click-variant action matrix**: every traffic button now has five slots —
  plain left click, right click, ⌥+left click, 🌐+left click and long press
  (~0.45 s). The rules UI exposes the extra variants in an expandable matrix;
  existing rules keep working (they map to the plain left-click slots).
- **Window management page** in Settings: an instant-action panel that
  applies any placement to the frontmost window, drag-to-snap with a live
  preview (edge halves, top-edge maximize, corner quadrants) and rebindable
  global hotkeys (default ⌃⌥ scheme) executed on the frontmost window.
- Window layout math is shared by all entry points via `WindowGeometry` /
  `WindowPlacement`, with a pure `SnapZones` hit-tester covered by tests.

### Changed
- Release artifacts are now a `Blinker-vX.Y.Z.dmg` (mount and drag to
  `/Applications`) plus `SHA256SUMS.txt`, with install steps in the release
  notes, replacing the universal zip.
- README restructured around a Chinese front page with an English edition
  linked from the top ([README.en.md](README.en.md)).

### Added
- The mask backdrop is now configurable: **Liquid Glass** (default, no extra
  permission) or **Sampled**, which captures a clean strip of the host
  window's title bar via ScreenCaptureKit and stretches it across the mask
  so the backdrop is pixel-identical to the real background. Selecting
  sampled prompts for Screen Recording permission once; without it the
  overlay falls back to glass automatically.
- The yellow (minimize) button is now remappable per app, alongside the red
  and green buttons. Cross-button native remaps (e.g. red → minimize,
  yellow → close window) now actually press the corresponding native button;
  they previously did nothing.
- "Add App" now opens an application library picker listing every installed
  app (with search), instead of only running apps.

### Fixed
- The backdrop pill is now a tint-free Liquid Glass view on macOS 26+ whose
  heavy blur smears the native buttons into the real background behind the
  window, replacing the flat gray titlebar-material capsule. Older systems
  fall back to a neutral `underWindowBackground` material pill.
- The titlebar-material backdrop now sits one window level below the
  enlarged chips, so it can never cover the enlarged buttons (it previously
  jumped above them when the overlay was re-synced during hover).
- The enlarged size minimum is raised from 18 pt to 28 pt: after the chip's
  inner padding the smallest circle (20 pt) is still clearly larger than a
  native traffic light, instead of smaller.
- The enlarged overlay group is now clamped to the window's bounds
  intersected with its screen, so windowed windows no longer let the chips
  spill past the window edges (fullscreen stays covered too).
- The overlay only wakes up near the native traffic lights (or on top of an
  already-enlarged panel) instead of anywhere in the title bar band.
- A titlebar-material backdrop panel now covers the native buttons while the
  overlay is visible, so the small originals no longer peek through the gaps
  between enlarged chips. Hotspot mode keeps the title bar untouched.

### Changed
- **Settings redesigned around the traffic-light motif**: the rules tab opens
  with a signal card summarizing each light's left-click action, the
  click-variant matrix renders as red/amber/green tinted lanes of bezel-free
  menu cells (replacing the fifteen-popup grid), rule list rows carry a
  three-light status trio (filled = customized, hollow = default), and the
  hover tab leads with a live preview rendering the real enlarged chips,
  glass tray and dwell ring from the current settings.

### Fixed
- Settings launch stall on macOS 26: a suppressed `Window` scene prevented
  `applicationDidFinishLaunching` from ever running (no menu bar item, no
  interceptor); the `Settings` placeholder scene is restored.
- The app library sheet showed "no results" during its background scan; it
  now shows an honest loading state.
- The General tab's interception footer offers the adjacent recovery action
  in failure states (open System Settings / retry the event tap).
- The menu bar status row maps severity by color (failures red, transitional
  states orange, running green) instead of a binary green/orange.
- HUD placement-tile labels use the system caption2 size; workspace window
  counts read "N 个窗口", matching the Settings wording.

### Developer
- Local dev builds carry a distinct bundle ID (`com.ygnstudio.Blinker.dev`)
  so they never collide with an installed release in LaunchServices —
  same-ID copies across /Applications, the repo and the Trash broke menu bar
  icon rendering.
- SwiftFormat disables `redundantSelf` and `wrapMultilineStatementBraces`
  (they fought SwiftLint's `opening_brace` and stripped compiler-required
  `self.`); the tree is reformatted to match.

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
