import BlinkerCore
import SwiftUI

// MARK: - Hover tab

/// Hover overlay configuration: master switch, mode, enlarged size,
/// anti-mistouch dwell and scope, bound to `HoverOverlaySettingsStore`.
struct HoverSettingsTab: View {
    @ObservedObject var store: HoverOverlaySettingsStore
    let onApply: (HoverOverlaySettings) -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    private var settings: HoverOverlaySettings {
        store.settings
    }

    var body: some View {
        Form {
            Section {
                Toggle(tr("启用悬停放大", "Enable Hover Enlargement"), isOn: isEnabledBinding)
                modePicker
                    .disabled(!settings.isEnabled)
            } header: {
                Text(tr("模式与尺寸", "Mode & Size"))
            } footer: {
                Text(tr(
                    "开启后，鼠标悬停到窗口红绿灯按钮上会临时放大，点击即执行对应动作。",
                    "When enabled, hovering a window's traffic lights enlarges them;"
                        + " clicking performs the mapped action."
                ))
                Text(modeHint)
            }

            Section {
                sizeSlider
                dwellSlider
            } header: {
                Text(tr("放大参数", "Enlargement"))
            }
            .disabled(!settings.isEnabled)

            Section {
                scopePicker
            } header: {
                Text(tr("作用范围", "Scope"))
            } footer: {
                Text(tr(
                    "悬停时以一块液态玻璃托盘衬托放大按钮与扩展按钮，随背景自动融合，无需任何额外权限。",
                    "On hover, a Liquid Glass tray sits behind the enlarged buttons and extra chips,"
                        + " blending with any background. No extra permission required."
                ))
            }
            .disabled(!settings.isEnabled)

            Section {
                ForEach(0 ..< HoverOverlaySettings.extraSlotCount, id: \.self) { index in
                    LabeledContent {
                        ActionPicker(
                            dotColor: .controlAccentColor,
                            options: Self.extraOptions,
                            selection: extraBinding(index),
                            emptyLabel: tr("不显示", "Hidden"),
                            pickerWidth: 120
                        )
                    } label: {
                        Text(tr("按钮 \(index + 1)", "Button \(index + 1)"))
                    }
                }
            } header: {
                Text(tr("扩展按钮", "Extra Buttons"))
            } footer: {
                Text(tr(
                    "选好动作的按钮会在悬停红绿灯时出现在绿灯右侧，点击即执行该动作；留空则不显示。",
                    "Buttons with a chosen action appear to the right of the green light on hover;"
                        + " clicking performs the action. Leave empty to hide a slot."
                ))
            }
            .disabled(!settings.isEnabled)
        }
        .formStyle(.grouped)
    }

    /// Every action except `none` — a chip that does nothing is pointless.
    static let extraOptions: [ButtonAction?] = [nil] + ButtonAction.allCases
        .filter { $0 != .none }

    private var modePicker: some View {
        Picker(tr("模式", "Mode"), selection: modeBinding) {
            Text(tr("覆盖放大", "Overlay")).tag(HoverOverlayMode.overlay)
            Text(tr("纯热区", "Hotspot")).tag(HoverOverlayMode.hotspot)
        }
        .pickerStyle(.segmented)
    }

    private var sizeSlider: some View {
        LabeledContent(tr("放大尺寸", "Enlarged Size")) {
            Slider(value: enlargedSizeBinding, in: 28 ... 48, step: 1)
                .frame(width: 200)
            Text("\(Int(settings.enlargedSize)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var dwellSlider: some View {
        LabeledContent(tr("防误触延迟", "Dwell Delay")) {
            Slider(value: dwellBinding, in: 0 ... 800, step: 50)
                .frame(width: 200)
                .disabled(settings.mode == .hotspot)
            Text(dwellLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var scopePicker: some View {
        Picker(tr("作用范围", "Scope"), selection: appliesToAllWindowsBinding) {
            Text(tr("全部窗口", "All Windows")).tag(true)
            Text(tr("仅规则应用", "Rule Apps Only")).tag(false)
        }
    }

    private var dwellLabel: String {
        if settings.mode == .hotspot {
            return tr("不适用", "N/A")
        }
        return settings.dwellMilliseconds == 0
            ? tr("立即响应", "Immediate")
            : "\(settings.dwellMilliseconds) ms"
    }

    private var modeHint: String {
        switch settings.mode {
        case .overlay:
            tr(
                "覆盖放大：红绿灯上方绘制液态玻璃质感的放大按钮，带防误触进度环。",
                "Overlay draws Liquid Glass buttons above the traffic lights with a dwell ring."
            )
        case .hotspot:
            tr(
                "纯热区：界面外观完全不变，仅在按钮周围扩大不可见点击区，点击立即响应。",
                "Hotspot keeps the title bar unchanged and only enlarges the invisible click zones."
            )
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in update { $0.isEnabled = newValue } }
        )
    }

    private var modeBinding: Binding<HoverOverlayMode> {
        Binding(
            get: { settings.mode },
            set: { newValue in update { $0.mode = newValue } }
        )
    }

    /// The slot's configured action; `nil` hides the chip.
    private func extraBinding(_ index: Int) -> Binding<ButtonAction?> {
        Binding(
            get: {
                settings.extraButtonActions.indices.contains(index)
                    ? settings.extraButtonActions[index]
                    : nil
            },
            set: { newValue in
                update { settings in
                    if settings.extraButtonActions.indices.contains(index) {
                        settings.extraButtonActions[index] = newValue
                    }
                }
            }
        )
    }

    private var enlargedSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.enlargedSize) },
            set: { newValue in update { $0.enlargedSize = CGFloat(newValue) } }
        )
    }

    private var dwellBinding: Binding<Double> {
        Binding(
            get: { Double(settings.dwellMilliseconds) },
            set: { newValue in update { $0.dwellMilliseconds = Int(newValue) } }
        )
    }

    private var appliesToAllWindowsBinding: Binding<Bool> {
        Binding(
            get: { settings.appliesToAllWindows },
            set: { newValue in update { $0.appliesToAllWindows = newValue } }
        )
    }

    private func update(_ mutate: (inout HoverOverlaySettings) -> Void) {
        var updated = settings
        mutate(&updated)
        onApply(updated)
    }
}
