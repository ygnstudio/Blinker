# Status Trio attribution

Blinker's status icons and parts of its status-reading and audio-control implementation include material adapted from [Status Trio](https://github.com/lingyired/status-trio), Copyright 2026 lingyired, under the Apache License, Version 2.0.

The source revision is [`d1672377a172ee4cb4af53d5054610c407c0d34f`](https://github.com/lingyired/status-trio/tree/d1672377a172ee4cb4af53d5054610c407c0d34f). [LICENSE](LICENSE) and [NOTICE](NOTICE) are unchanged copies from that revision. The license text also matches the [Apache Software Foundation's official text](https://www.apache.org/licenses/LICENSE-2.0.txt).

## Scope and modifications

Blinker adapts the battery ring, network indicator, volume dots or arc, and Dock artwork. The integration reads local battery, network and audio-output state and uses public CoreAudio APIs to adjust volume, mute and switch output devices. Current-output Bluetooth metadata can change the icon; this is not a nearby-device scanner or pairing manager. Blinker does not import Status Trio's complete application, updater, analytics, DDC support, VPN management or identifying network information such as SSIDs.

Adapted source files carry a modification notice identifying their origin. Blinker-specific settings control placement, appearance, panel sections and device ordering. Left click opens the status panel by default, with App Rules as an alternative; right click retains the menu.

The upstream paths below are relative to `Sources/StatusTrioCore/` at the pinned revision. Blinker paths are relative to `Sources/BlinkerApp/`.

| Blinker file | Upstream source | Changes |
|---|---|---|
| `MenuBar/TrioIconGeometry.swift` | `UI/Icon/StatusIconGeometry.swift` | Retains battery, Ethernet, volume-dot and volume-arc geometry; removes unused upstream geometry. |
| `MenuBar/TrioIconRenderer.swift` | `UI/Icon/StatusIconRenderer.swift`; `Models/StatusMappings.swift`, `Models/BatteryIconOptions.swift`, `Models/VolumeIconOptions.swift`, `Models/RingStrokeStyle.swift` | Adapts colors, scale, weight, battery numbers, network and current-output Bluetooth symbols, and volume styles to Blinker's configuration and explicit unknown states. The glyph renderer is static; Blinker supplies separate charging effects. |
| `MenuBar/DockIconRenderer.swift` | `UI/Icon/DockIconRenderer.swift` | Preserves the Dock artwork proportions with configurable backgrounds, including transparency, and Blinker's shared glyph renderer. |
| `MenuBar/SystemStatusMonitor.swift` | `Store/SystemStatusStore.swift`, `Monitoring/BatteryMonitor.swift` | Rewrites event and lifecycle handling with one bounded reader, restart guards and a timeout; retains no upstream store or application controller. |
| `MenuBar/SystemStatusReader.swift` | `Monitoring/BatteryMonitor.swift`, `Monitoring/WiFiMonitor.swift`, `Monitoring/WiFiStatusReader.swift`, `Monitoring/AudioStatusReader.swift` | Adapts battery parsing, signal thresholds and serial reads; reads local status without network names. |
| `MenuBar/SystemAudioStatusReader.swift` | `Monitoring/VolumeMonitor.swift`, `Audio/CoreAudioOutputChannelElements.swift` | Adapts default-output volume reads and channel handling, with bounded buffers and listener cleanup; derives Bluetooth audio appearance from public transport and terminal metadata, without DDC. |
| `Audio/CoreAudioBackend.swift`, `Audio/SystemAudioHardware.swift` | `Audio/CoreAudioOutputController.swift` | Adapts output-device enumeration and public CoreAudio volume, mute and selection operations, adding serialization, cancellation, bounded buffers and device-identity guards. |

The monitoring and audio-control code is a Blinker-specific rewrite informed by those implementations, not an unchanged copy of the upstream controllers. Blinker's snapshot and preference models, settings and panel views, presentation, scroll handling, charging animation, and `Audio/SystemAudioController.swift` and `Audio/SystemAudioModels.swift` are new integration code.

## Distribution

The app bundle includes this directory at `Contents/Resources/ThirdParty/StatusTrio/`. The license view in About displays this provenance, the original NOTICE and the full Apache 2.0 text without a network connection. Packaging includes these files and release validation compares them byte for byte with the release source.

Blinker as a whole remains GPL-3.0-only. The incorporated Status Trio material retains its Apache 2.0 notices and terms; this does not relicense the upstream project. The [GNU license list](https://www.gnu.org/licenses/license-list.html#apache2) identifies Apache 2.0 as compatible with GPLv3.
