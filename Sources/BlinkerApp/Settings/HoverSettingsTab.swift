import BlinkerCore
import SwiftUI

// MARK: - Hover tab

/// Hover overlay configuration: master switch, size, scope,
/// extra-button slots and the hover-toggle hotkey — long explanations live
/// in info popovers instead of multi-line footers, keeping the form dense.
/// Per-row `.disabled` only (never section-level), so the master toggle
/// never locks itself.
struct HoverSettingsTab: View {
    @EnvironmentObject var store: HoverOverlaySettingsStore
    /// Owns the hover-toggle hotkey binding; observed here so the row moved
    /// from the window-management tab keeps its live recording state.
    @EnvironmentObject var hotkeyManager: HotkeyManager
    let onApply: (HoverOverlaySettings) -> Void

    private var settings: HoverOverlaySettings {
        store.settings
    }

    var body: some View {
        Form {
            // The live preview leads the page: every control below answers
            // here first, so the feature explains itself.
            Section {
                HoverPreviewCard(settings: settings)
            } header: {
                SectionHeader(
                    title: String(localized: "实时预览"),
                    info: String(localized: "放大按钮直接覆盖原生红绿灯；材质与按钮跟随系统外观。")
                )
            }

            Section {
                Toggle("开启悬停放大", isOn: isEnabledBinding)
                sizeSlider
                    .disabled(!settings.isEnabled)
                dwellSlider
                    .disabled(!settings.isEnabled)
            } header: {
                SectionHeader(title: String(localized: "放大"), info: enlargementInfo)
            }

            Section {
                scopePicker
                    .disabled(!settings.isEnabled)
            } header: {
                SectionHeader(
                    title: String(localized: "作用范围"),
                    info: String(localized: "悬停时显示系统液态玻璃按钮；红黄绿保留各自颜色，扩展按钮使用系统强调色。")
                )
            }

            Section {
                extraSlotsGrid
                    .disabled(!settings.isEnabled)
            } header: {
                SectionHeader(
                    title: String(localized: "扩展按钮"),
                    info: String(localized: "选好动作的按钮会在悬停红绿灯时出现在绿灯右侧，点击即执行该动作；留空则不显示。")
                )
            }

            Section {
                hoverToggleHotkeyRow
            } header: {
                SectionHeader(
                    title: String(localized: "快捷键"),
                    info: String(
                        localized: "在任意应用下按下即可直接开关悬停放大；点击右侧录制新的快捷键，Esc 取消，减号清除。默认 ⌃⌥H；受「窗口管理 → 全局快捷键」总开关控制。"
                    )
                )
            }
        }
        .formStyle(.grouped)
    }

    /// Every action except `none` — a chip that does nothing is pointless.
    static let extraOptions: [ButtonAction?] = [nil] + ButtonAction.allCases
        .filter { $0 != .none }

    private var sizeSlider: some View {
        SliderReadoutRow(
            label: String(localized: "放大尺寸"),
            readout: "\(Int(settings.enlargedSize)) pt",
            value: enlargedSizeBinding,
            range: 28 ... 48,
            step: 1
        )
    }

    private var dwellSlider: some View {
        SliderReadoutRow(
            label: String(localized: "防误触延迟"),
            readout: dwellLabel,
            value: dwellBinding,
            range: 0 ... 800,
            step: 50
        )
    }

    private var scopePicker: some View {
        Picker("作用范围", selection: appliesToAllWindowsBinding) {
            Text("全部窗口").tag(true)
            Text("仅规则应用").tag(false)
        }
    }

    /// The four extra-button slots as a 2×2 grid — half the height of the
    /// old four stacked rows.
    private var extraSlotsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(0 ..< HoverOverlaySettings.extraSlotCount, id: \.self) { index in
                LabeledContent {
                    ActionPicker(
                        dotColor: .controlAccentColor,
                        options: Self.extraOptions,
                        selection: extraBinding(index),
                        emptyLabel: String(localized: "不显示"),
                        // The same 104pt width as the rules matrix, so the
                        // "下一显示器" option never truncates on either
                        // surface (previously 88 here).
                        pickerWidth: 104,
                        // Every slot shares the same accent color, so the
                        // dots carry no information — drop them (matching
                        // the rules matrix).
                        showsDot: false
                    )
                } label: {
                    Text("按钮 \(index + 1)")
                        .font(.callout)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// The hover-toggle hotkey row, moved from the window-management tab so
    /// the binding lives next to the feature it controls. The binding
    /// itself is still owned by the hotkey manager, so the row follows the
    /// global-hotkeys master switch.
    private var hoverToggleHotkeyRow: some View {
        HotkeyRowView(
            label: String(localized: "悬停放大开关"),
            combo: hotkeyManager.hoverToggleCombo,
            isRecording: hotkeyManager.recordingTarget == .hoverToggle,
            recordingHint: hotkeyManager.recordingHint,
            conflictWarning: hoverToggleConflictWarning,
            onRecord: { hotkeyManager.beginRecordingHoverToggle() },
            onClear: { hotkeyManager.clearHoverToggleBinding() }
        )
        .disabled(!hotkeyManager.isEnabled)
    }

    /// The hover-toggle combo's conflict with any window-action binding.
    private var hoverToggleConflictWarning: String? {
        guard let combo = hotkeyManager.hoverToggleCombo else { return nil }
        return hotkeyManager.internalConflictWarning(for: combo, action: nil)
    }

    private var dwellLabel: String {
        settings.dwellMilliseconds == 0
            ? String(localized: "立即响应")
            : "\(settings.dwellMilliseconds) ms"
    }

    private var enlargementInfo: String {
        String(localized: "鼠标悬停时，放大按钮直接覆盖原生红绿灯，驻留后可点击；移开鼠标即收起。")
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in update { $0.isEnabled = newValue } }
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

/// `LabeledContent` row with a fixed-width slider and a fixed-width,
/// monospaced trailing readout — the shared shape of the hover tab's two
/// numeric sliders, so the readouts align across rows.
private struct SliderReadoutRow: View {
    let label: String
    let readout: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(label) {
            Slider(value: $value, in: range, step: step)
                .frame(width: 200)
            Text(readout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
