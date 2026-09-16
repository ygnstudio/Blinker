import BlinkerCore
import SwiftUI

// MARK: - Hover tab

/// Hover overlay configuration: master switch, mode and size, scope,
/// extra-button slots and the hover-toggle hotkey — long explanations live
/// in info popovers instead of multi-line footers, keeping the form dense.
/// Per-row `.disabled` only (never section-level), so the master toggle
/// never locks itself.
struct HoverSettingsTab: View {
    @ObservedObject var store: HoverOverlaySettingsStore
    /// Owns the hover-toggle hotkey binding; observed here so the row moved
    /// from the window-management tab keeps its live recording state.
    @ObservedObject var hotkeyManager: HotkeyManager
    let onApply: (HoverOverlaySettings) -> Void

    private var settings: HoverOverlaySettings {
        store.settings
    }

    var body: some View {
        Form {
            Section {
                Toggle("开启悬停放大", isOn: isEnabledBinding)
                modePicker
                    .disabled(!settings.isEnabled)
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
                    info: String(localized: "悬停时以一块液态玻璃托盘衬托放大按钮与扩展按钮，随背景自动融合，无需任何额外权限。")
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
                    // swiftlint:disable:next line_length
                    info: String(localized: "在任意应用下按下即可直接开关悬停放大；点击右侧录制新的快捷键，Esc 取消，减号清除。默认 ⌃⌥H；受「窗口管理 → 全局快捷键」总开关控制。")
                )
            }
        }
        .formStyle(.grouped)
    }

    /// Every action except `none` — a chip that does nothing is pointless.
    static let extraOptions: [ButtonAction?] = [nil] + ButtonAction.allCases
        .filter { $0 != .none }

    private var modePicker: some View {
        Picker("模式", selection: modeBinding) {
            Text("覆盖放大").tag(HoverOverlayMode.overlay)
            Text("纯热区").tag(HoverOverlayMode.hotspot)
        }
        .pickerStyle(.segmented)
    }

    private var sizeSlider: some View {
        LabeledContent("放大尺寸") {
            Slider(value: enlargedSizeBinding, in: 28 ... 48, step: 1)
                .frame(width: 200)
            Text("\(Int(settings.enlargedSize)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var dwellSlider: some View {
        LabeledContent("防误触延迟") {
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
        if settings.mode == .hotspot {
            return String(localized: "不适用")
        }
        return settings.dwellMilliseconds == 0
            ? String(localized: "立即响应")
            : "\(settings.dwellMilliseconds) ms"
    }

    /// The merged "what hovering does + which mode means what" explanation,
    /// shown from the section header's info popover.
    private var enlargementInfo: String {
        let intro = String(localized: "开启后，鼠标悬停到窗口红绿灯按钮上会临时放大，点击即执行对应动作。")
        let hint: String
        switch settings.mode {
        case .overlay:
            hint = String(localized: "覆盖放大：红绿灯上方绘制液态玻璃质感的放大按钮，带防误触进度环。")
        case .hotspot:
            hint = String(localized: "纯热区：界面外观完全不变，仅在按钮周围扩大不可见点击区，点击立即响应。")
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
