# Macbook Duo Effect attribution

Blinker's lid-angle reader, Duo image effect and GPU frame pipeline include material adapted from [Duo Effect](https://github.com/RuixiangHuang/Macbook_Duo_Effect), Copyright (c) 2026 Ruixiang Huang, under the MIT License.

The source revision is [`af3b89df6c11f9fb6d07b5a6c9872cfde08bb2a1`](https://github.com/RuixiangHuang/Macbook_Duo_Effect/tree/af3b89df6c11f9fb6d07b5a6c9872cfde08bb2a1). [LICENSE](LICENSE) is an unchanged copy from that revision.

## Scope and modifications

The upstream paths below are relative to `Sources/` at the pinned revision. Blinker paths are relative to `Sources/BlinkerApp/ScreenEffects/`.

| Blinker file | Upstream source | Changes |
|---|---|---|
| `LidAngleReader.swift` | `LidSensor.swift`; `EffectModel.swift` (`LidReport`) | Adapts HID matching and angle decoding with serial device access, bounded reports, typed failures and restartable cleanup. |
| `LidEffectProcessor.swift` | `EffectProcessor.swift`, `EffectModel.swift` | Adapts the Duo perspective, dimming and variable-blur pipeline to Blinker's effect configuration. |
| `LidEffectFrameRenderer.swift` | `BlurOverlay.swift` (`FrameRenderer`) | Adapts the ScreenCaptureKit-to-Metal rendering path with Blinker's frame mailbox and lifecycle handling. |
| `LidEffectOverlay.swift` | `BlurOverlay.swift` (`BlurOverlay`) | Adapts built-in-display capture and the click-through overlay with serialized start/stop, permission preflight, display checks and Blinker menu access. |

Adapted files carry source and modification notices. Blinker's lid-angle monitor, preferences, gesture model and application integration are new code. The integration provides the Duo lid effect only.

This integration does not include the upstream application's icon, settings window, build scripts or debug logger. It does not change system sleep behavior. The undocumented lid-angle sensor protocol and screen-capture support remain hardware and system compatibility limits; the effect is not a privacy or security boundary.

## Distribution

The app bundle includes this directory at `Contents/Resources/ThirdParty/MacbookDuoEffect/`. The license view in About displays this provenance and the complete MIT text offline. Packaging includes both files, and release validation compares them byte for byte with the release source.

Blinker as a whole remains GPL-3.0-only. The incorporated material retains its MIT copyright and permission notice; this does not change the upstream project's license.
