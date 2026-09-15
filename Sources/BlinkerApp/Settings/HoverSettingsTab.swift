import BlinkerCore
import SwiftUI

// MARK: - Hover tab

/// Hover overlay configuration: master switch, mode and size, scope and
/// extra-button slots — long explanations live in info popovers instead of
/// multi-line footers, keeping the form dense. Per-row `.disabled` only
/// (never section-level), so the master toggle never locks itself.
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
                sizeSlider
                    .disabled(!settings.isEnabled)
                dwellSlider
                    .disabled(!settings.isEnabled)
            } header: {
                SectionHeader(title: tr("放大", "Enlargement"), info: enlargementInfo)
            }

            Section {
                scopePicker
                    .disabled(!settings.isEnabled)
            } header: {
                SectionHeader(
                    title: tr("作用范围", "Scope"),
                    info: tr(
                        "悬停时以一块液态玻璃托盘衬托放大按钮与扩展按钮，随背景自动融合，无需任何额外权限。",
                        "On hover, a Liquid Glass tray sits behind the enlarged buttons and extra chips,"
                            + " blending with any background. No extra permission required."
                    )
                )
            }

            Section {
                extraSlotsGrid
                    .disabled(!settings.isEnabled)
            } header: {
                SectionHeader(
                    title: tr("扩展按钮", "Extra Buttons"),
                    info: tr(
                        "选好动作的按钮会在悬停红绿灯时出现在绿灯右侧，点击即执行该动作；留空则不显示。",
                        "Buttons with a chosen action appear to the right of the green light on hover;"
                            + " clicking performs the action. Leave empty to hide a slot."
                    )
                )
            }
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

    /// The four extra-button slots as a 2×2 grid — half the height of the
    /// old four stacked rows.
    private var extraSlotsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(0 ..< HoverOverlaySettings.extraSlotCount, id: \.self) { index in
                LabeledContent {
                    ActionPicker(
                        dotColor: .controlAccentColor,
                        options: Self.extraOptions,
                        selection: extraBinding(index),
                        emptyLabel: tr("不显示", "Hidden")
                    )
                } label: {
                    Text(tr("按钮 \(index + 1)", "Button \(index + 1)"))
                        .font(.callout)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var dwellLabel: String {
        if settings.mode == .hotspot {
            return tr("不适用", "N/A")
        }
        return settings.dwellMilliseconds == 0
            ? tr("立即响应", "Immediate")
            : "\(settings.dwellMilliseconds) ms"
    }

    /// The merged "what hovering does + which mode means what" explanation,
    /// shown from the section header's info popover.
    private var enlargementInfo: String {
        let intro = tr(
            "开启后，鼠标悬停到窗口红绿灯按钮上会临时放大，点击即执行对应动作。",
            "When enabled, hovering a window's traffic lights enlarges them;"
                + " clicking performs the mapped action."
        )
        let hint: String
        switch settings.mode {
        case .overlay:
            hint = tr(
                "覆盖放大：红绿灯上方绘制液态玻璃质感的放大按钮，带防误触进度环。",
                "Overlay draws Liquid Glass buttons above the traffic lights with a dwell ring."
            )
        case .hotspot:
            hint = tr(
                "纯热区：界面外观完全不变，仅在按钮周围扩大不可见点击区，点击立即响应。",
                "Hotspot keeps the title bar unchanged and only enlarges the invisible click zones."
            )
        }
        return intro + "\n" + hint
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
