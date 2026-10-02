# Blinker

[简体中文](README.md) | English

Blinker is a native macOS menu bar utility for traffic-light controls, window previews and switching, and window placement. App rules and settings have separate windows. An unconfigured ordinary left click keeps the native button behavior.

## Features

- **App rules**: configure each traffic-light button for left click, right click, Option-click, Fn-click and long press. Enable remapping and hover enlargement independently per app; copy rules, import/export JSON, and undo or redo edits.
- **Hover enlargement**: colored controls cover the native traffic lights on a continuous glass tray. Adjust size, appearance delay and click protection, with four optional action buttons. macOS 26+ uses system Liquid Glass; earlier systems use native fallback materials.
- **Window previews and switching**: use Option-Tab or hover over a Dock icon. Scale the entire preview panel from 50% to 150%; items share one grid, scrolling when needed. Optionally list standard macOS window tabs and Safari tabs separately.
- **Window placement**: halves, quarters, thirds, centering, maximize, display transfer and previous-layout restore. Shared actions are available through the hover panel, shortcuts and optional drag to snap.
- **Experimental workspaces**: explicitly enable saving and restoring window arrangements. Matching uses window characteristics; it does not restore documents or browser sessions.

This README describes the current source. For downloaded builds, consult the [release notes](https://github.com/ygnstudio/Blinker/releases).

## Get started

Targets **macOS 15 or later**, with Apple Silicon and Intel architectures in release builds. Compilation does not establish runtime compatibility: complete testing on the minimum OS and Intel, along with core interaction and performance acceptance, is still pending. Each release's notes define its verified scope.

Install through [Homebrew](https://brew.sh/) and the project's [tap](https://github.com/ygnstudio/homebrew-ygn):

```bash
brew install --cask ygnstudio/ygn/blinker
```

Quit Blinker before updating, then run:

```bash
brew update
brew upgrade --cask ygnstudio/ygn/blinker
```

`brew update` refreshes package information; `brew upgrade` installs the newer version available in the tap. Blinker has no built-in updater, and pushing source changes does not update the tap. See the [Homebrew manual](https://docs.brew.sh/Manpage).

As an alternative, download a DMG from [GitHub Releases](https://github.com/ygnstudio/Blinker/releases) and drag `Blinker.app` into Applications. Update a manual installation by replacing the app with a newer download.

Release packages are **ad-hoc signed, without Developer ID signing or Apple notarization**. If macOS blocks the first launch because the developer cannot be verified or the app is not notarized, verify the download source and use **System Settings → Privacy & Security → Open Anyway**. This may also be needed after a Homebrew installation. See [Apple's opening instructions](https://support.apple.com/en-us/102445).

1. Follow the first-launch guide and explicitly choose to grant **Accessibility** permission. Reopen the guide from **General** at any time.
2. Click the menu bar icon to open **App Rules**, add an app, and open its editor.
3. Open **Settings** from the toolbar to configure hover, previews, placement and shortcuts. **About** contains version, help and feedback links.
4. To use real thumbnails, explicitly grant **Screen Recording** in **Window Previews & Switching**. Icons and titles remain usable without it.

If an update stops responding despite the permission toggle being on, verify which copy of Blinker is running, quit it, and remove/re-add that copy in System Settings → Privacy & Security → Accessibility. Signature changes can require a new grant; local development and release builds have separate identities. See the [user guide (中文)](docs/USER_GUIDE.md) for further troubleshooting.

## Permissions and limits

- **Accessibility** identifies buttons, windows and supported tabs, and performs the window actions you choose.
- **Screen Recording is optional**, used only for thumbnails while a preview is open. Images remain in memory. Traffic-light glass rendering requires no screen capture.
- Blinker does not upload rules, window titles or thumbnails, and includes no analytics or automatic network requests. Opening project, help or feedback links uses your browser.
- Custom title bars and tab bars may omit the necessary accessibility information. Inactive tabs without their own cached image show an icon and title. Close Window and Minimize on a tab preview apply to its containing window.
- Discovery on other Spaces, fresh images of minimized windows and minimum window sizes depend on macOS and the target app. Experimental restoration to an original Space uses private system APIs.

## Development

Building requires a Swift 6 toolchain and Xcode with the macOS 26 SDK. The runtime deployment target remains macOS 15.

```bash
git clone https://github.com/ygnstudio/Blinker.git
cd Blinker
./Scripts/build-app.sh release
open ~/Applications/Blinker.app
```

Development builds install to `~/Applications/Blinker.app` using the distinct `com.ygnstudio.Blinker.dev` identity. See [Contributing](CONTRIBUTING.md) for build, test, signing and Intel instructions.

| Document | Purpose |
|---|---|
| [User guide (中文)](docs/USER_GUIDE.md) | Page responsibilities, controls, permissions and troubleshooting |
| [Architecture](docs/ARCHITECTURE.md) | Module boundaries, threading, performance and safety constraints |
| [Window browser](docs/WINDOW_BROWSER.md) | Window/tab identity, thumbnails, compatibility and reference projects |
| [Contributing](CONTRIBUTING.md) | Development setup, checks and change entry points |
| [Release checklist (中文)](docs/RELEASING.md) | Distribution policy, candidate acceptance and tap updates |
| [Changelog](CHANGELOG.md) | Pending changes and published release history |

## License

Copyright © 2026 ygnstudio. The current source and releases based on this license change use **[GNU GPL v3.0 only (GPL-3.0-only)](LICENSE)**, without an “or later” option. See [NOTICE](NOTICE) for the project notice.

GPLv3 **permits commercial use, charging for copies and paid services**. Free and paid distribution must preserve copyright/license notices and warranty disclaimers, and identify changes. Binary distribution must provide the version's Corresponding Source, including required build and installation scripts, in accordance with GPLv3. Distributed modified covered works must remain under GPLv3, without further restrictions such as a ban on commercial use. Private use or modification alone does not require public source publication. [LICENSE](LICENSE) contains the controlling terms; see the [GNU FAQ on selling copies](https://www.gnu.org/licenses/gpl-faq.en.html#DoesTheGPLAllowMoney).

Versions previously released under MIT retain their original MIT grants; this change does not revoke them. Third-party projects retain their own licenses. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).
