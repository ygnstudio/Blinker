# Blinker

[简体中文](README.md) | English

A native macOS menu bar utility: enlarge traffic-light buttons, choose their actions per app, find windows through Option-Tab and Dock previews, and arrange them on your displays.

[Download a release](https://github.com/ygnstudio/Blinker/releases/latest) · [User guide (中文)](docs/USER_GUIDE.md) · [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/ygnstudio/Blinker/issues)

## Install and update

Install with [Homebrew](https://brew.sh/):

```bash
brew install --cask ygnstudio/ygn/blinker
```

Quit Blinker before updating:

```bash
brew update
brew upgrade --cask ygnstudio/ygn/blinker
```

The [project tap](https://github.com/ygnstudio/homebrew-ygn) periodically verifies and adopts stable releases, so an update may take time to appear. Blinker has no built-in updater. Alternatively, download a DMG from [Releases](https://github.com/ygnstudio/Blinker/releases), drag `Blinker.app` into Applications, and replace it manually for future updates.

Targets **macOS 15 or later**, with Apple Silicon and Intel architectures in release builds. Minimum-OS and Intel runtime compatibility, along with complete performance acceptance, remain unverified. Each release's notes describe its tested scope.

Releases use **ad-hoc signing, without Developer ID signing or Apple notarization**. If macOS blocks the first launch, verify the download source and choose **System Settings → Privacy & Security → Open Anyway**. Homebrew installations may need this too; see [Apple's instructions](https://support.apple.com/en-us/102445).

## Features

| Feature | What it does |
|---|---|
| App rules | Assign clicks, modified clicks and long presses to each traffic-light button per app; copy rules, import/export them and undo edits |
| Hover Buttons | Colored controls cover the native traffic lights, with adjustable size, delay, click protection and extra buttons; macOS 26+ uses system Liquid Glass |
| Previews & Switching | Use Option-Tab or hover over a Dock icon; scale the whole panel from 50% to 150% and optionally list Safari and standard macOS tabs separately |
| Window management | Halves, quarters, thirds, centering, maximize, display transfer and layout restore, with shortcuts, drag to snap and experimental workspaces |

App rules and settings have separate windows. An unconfigured ordinary left click keeps the native button behavior. General settings provide appearance and Chinese/English language choices. See the [user guide (中文)](docs/USER_GUIDE.md) for controls and compatibility details.

### New in v0.7.0

- **Status icons** show battery, network and volume in the menu bar, Dock or both. The panel controls volume, mute and output devices. Configure content, appearance and ordering in **Settings → Status Icons**. Left click opens the panel by default, with App Rules as an alternative; right click retains the menu.
- **Minimize and restore** optionally makes another click on the frontmost app's Dock icon minimize its windows, then restore them on the next click. Show Desktop defaults to Control-Option-D; repeating it restores only that operation's windows. Both skip fullscreen and previously minimized windows.
- **Duo lid effect** tilts, blurs, dims or restores the built-in display as a compatible MacBook opens or closes. It is off by default, with a simulated preview, calibration and recommended settings. It requires a readable lid-angle sensor, preserves normal lid-close sleep and is not a privacy screen.

### New in the development build (unreleased)

- **Status panel depth rows**: battery cycle count, health, temperature and charge/discharge power; averaged up/down throughput and the local IP; an opt-in public IP (off by default, the panel's only outbound request); Bluetooth signal strength. Two panel densities, with an individual toggle for every row family.
- **Bluetooth devices and nearby batteries**: the paired-device list shows kind icons, battery and signal strength with ordering, limits and inquiry-residue hiding; connected devices mislabeled by the manufacturer (a keyboard reporting itself as a mouse) are corrected from the interfaces the system enumerates. Optional nearby-device battery scanning, plus A2DP codec subtitles and per-device disconnect, share one Bluetooth grant.
- **Quick Actions page**: a second panel page with a microphone mute, display cleaning (full-screen black overlays, no permission), keyboard cleaning (system-wide lock requiring Accessibility and Input Monitoring) and up to three Shortcut slots.
- **Wi-Fi name and VPN rows**: the Wi-Fi name needs a Location grant to un-redact the SSID; the VPN row is a read-only view of tunnels, system services or the proxy endpoint.
- **Audio input**: volume and mute for the default input device.
- **Storage and performance sections**: boot-volume available space (Finder-identical) with a usage bar; external volumes listed individually with eject buttons and inline failure reasons. CPU load, memory and swap usage, plus uptime (off by default) — all read from local kernel interfaces, no permission needed.

## Get started

1. Follow the first-launch guide to grant Accessibility, or click **Grant Access…** in **Settings → Privacy and Permissions**. You still need to approve access in System Settings.
2. Right-click the menu bar icon, open **App Rules**, and add an app to configure its buttons. Button rules and hover enlargement can be enabled separately per app.
3. Enable the previews, window-management features and shortcuts you need in Settings. Grant Screen Recording explicitly for real thumbnails; switching by icon and title works without it.

| Permission | Purpose |
|---|---|
| Accessibility | Identify windows, buttons and supported tabs, and perform window actions; also used to pause Duo with Esc while another app is active, and by keyboard cleaning's system-wide key interception |
| Screen Recording (optional) | Generate window thumbnails and run Duo. Hover-button glass needs no screen capture |
| Location (optional) | Show the current Wi-Fi name in the status panel; the name simply stays hidden without it |
| Bluetooth (optional) | Scan nearby devices for battery levels, show A2DP codecs and disconnect connected devices; the paired list and signal strength need no grant |
| Input Monitoring (optional) | Keyboard cleaning's system-wide key interception, required together with Accessibility; keyboard cleaning will not start without it |

Screen images stay in memory, with no audio capture or saved recordings. Blinker does not upload rules, window titles or screen content, and has no analytics; apart from the optional public-IP lookup (off by default, with the endpoint named when enabled), it makes no automatic network requests. Opening project and help links uses your browser.

Custom tab bars, windows on other Spaces and minimized-window previews depend on macOS and the target app. Inactive tabs without their own cached image show an icon and title; closing or minimizing a tab item affects its whole window. Experimental workspaces match existing windows, do not restore documents or sessions, and use private APIs for original-Space restoration. See the [user guide (中文)](docs/USER_GUIDE.md) and [window browser documentation](docs/WINDOW_BROWSER.md) for permission troubleshooting and other limits.

## Build from source

Use a Swift 6 toolchain and Xcode with the macOS 26 SDK. These commands target Apple Silicon:

```bash
git clone https://github.com/ygnstudio/Blinker.git
cd Blinker
./Scripts/build-app.sh release
open ~/Applications/Blinker.app
```

Development builds use the distinct `com.ygnstudio.Blinker.dev` identity and separate permission grants from releases. See [Contributing](CONTRIBUTING.md) for Intel builds, tests and signing.

- [Architecture](docs/ARCHITECTURE.md): module ownership, threading and data boundaries.
- [Release checklist (中文)](docs/RELEASING.md): build checks, manual acceptance and Homebrew updates.
- [Code of Conduct](CODE_OF_CONDUCT.md): participation guidelines.

## License and sources

Copyright © 2026 ygnstudio. The current source uses **[GPL-3.0-only](LICENSE)**, which permits commercial use and paid distribution. Distribution requires compliance with Corresponding Source, notice and same-license obligations, without additional restrictions such as a commercial-use ban. See [NOTICE](NOTICE) and the [distribution guide](CONTRIBUTING.md#license-and-distribution). Historical MIT releases retain their original grants.

Status icons and parts of the system-status and audio-control implementation are adapted from [Status Trio](https://github.com/lingyired/status-trio), retaining its Apache 2.0 license; see the [source and modification notes](ThirdParty/StatusTrio/README.md). Parts of Duo's sensor, image-processing and capture implementation are adapted from [Duo Effect](https://github.com/RuixiangHuang/Macbook_Duo_Effect), retaining its MIT license; see its [source and modification notes](ThirdParty/MacbookDuoEffect/README.md). Full licenses and notices ship with the app and are available offline in About.
