import BlinkerCore
import SwiftUI

struct HoverTimingSettings: View {
    let settings: HoverOverlaySettings
    let onApply: (HoverOverlaySettings) -> Void

    var body: some View {
        SliderReadoutRow(label: String(localized: "出现延迟"),
                         readout: "\(settings.appearanceDelayMilliseconds) ms",
                         value: delayBinding, range: 0 ... 800, step: 50)
        SliderReadoutRow(label: String(localized: "点击保护时间"),
                         readout: settings.dwellMilliseconds == 0 ? String(localized: "立即响应")
                             : "\(settings.dwellMilliseconds) ms",
                         value: dwellBinding, range: 0 ... 800, step: 50)
        Toggle("仅保护退出应用操作", isOn: Binding(
            get: { settings.protectQuitOnly },
            set: { var copy = settings; copy.protectQuitOnly = $0; onApply(copy) }
        ))
    }

    private var delayBinding: Binding<Double> {
        Binding(get: { Double(settings.appearanceDelayMilliseconds) },
                set: { var copy = settings; copy.appearanceDelayMilliseconds = Int($0); onApply(copy) })
    }

    private var dwellBinding: Binding<Double> {
        Binding(get: { Double(settings.dwellMilliseconds) },
                set: { var copy = settings; copy.dwellMilliseconds = Int($0); onApply(copy) })
    }
}
