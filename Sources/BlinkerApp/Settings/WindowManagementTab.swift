import BlinkerCore
import SwiftUI

/// Window placement and hotkeys; saved layouts live in ExperimentalSettingsTab.
struct WindowManagementTab: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @ObservedObject private var preferences = AppPreferences.shared
    let onSnapEnabledChange: (Bool) -> Void

    var body: some View {
        Form {
            snapSection
            hotkeySwitchSection
            hotkeyGroupSection(
                title: String(localized: "半屏"),
                actions: [.tileLeft, .tileRight, .tileTop, .tileBottom]
            )
            hotkeyGroupSection(
                title: String(localized: "四分屏"),
                actions: [
                    .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight,
                ]
            )
            hotkeyGroupSection(
                title: String(localized: "三分屏"),
                actions: [
                    .tileFirstThird,
                    .tileCenterThird,
                    .tileLastThird,
                    .tileFirstTwoThirds,
                    .tileLastTwoThirds,
                ]
            )
            hotkeyGroupSection(
                title: String(localized: "整窗"),
                actions: [
                    .maximize,
                    .almostMaximize,
                    .centerWindow,
                    .moveToNextDisplay,
                    .restorePreviousFrame,
                ]
            )
        }
        .formStyle(.grouped)
    }

    private var snapSection: some View {
        Section {
            Toggle("开启拖拽贴靠", isOn: snapBinding)
        } header: {
            SectionHeader(
                title: String(localized: "拖拽贴靠（可选）"),
                info: snapInfo
            )
        }
    }

    private var snapInfo: String {
        String(localized: "默认关闭。启用前请确认不会与系统或其他窗口管理工具的拖拽贴靠重复。")
    }

    private var snapBinding: Binding<Bool> {
        Binding(
            get: { preferences.isSnapEnabled },
            set: { newValue in
                preferences.isSnapEnabled = newValue
                onSnapEnabledChange(newValue)
            }
        )
    }

    // MARK: - Hotkeys

    /// The master switch; the binding rows live in the groups below.
    private var hotkeySwitchSection: some View {
        Section {
            Toggle("开启全局快捷键", isOn: hotkeysEnabledBinding)
        } header: {
            SectionHeader(
                title: String(localized: "全局快捷键"),
                info: String(
                    // swiftlint:disable:next line_length
                    localized: "在任意应用下按键即可对最前面的窗口执行动作。点击右侧录制新的快捷键，Esc 取消，减号清除。窗口动作默认方案为 ⌃⌥ 加方向键与 U/I/J/K；悬停放大开关的快捷键在「悬停放大」页配置。"
                )
            )
        }
    }

    /// One hotkey group with a plain section title.
    private func hotkeyGroupSection(title: String, actions: [ButtonAction]) -> some View {
        Section {
            ForEach(actions, id: \.rawValue) { action in
                hotkeyRow(for: action)
            }
        } header: {
            Text(title)
        }
    }

    private func hotkeyRow(for action: ButtonAction) -> some View {
        HotkeyRowView(
            label: action.localizedLabel,
            combo: hotkeyManager.bindings[action.rawValue],
            isRecording: hotkeyManager.recordingTarget == .windowAction(action),
            recordingHint: hotkeyManager.recordingHint,
            conflictWarning: windowActionConflictWarning(for: action),
            registrationWarning: hotkeyManager.registrationWarning(for: .windowAction(action)),
            onRecord: { hotkeyManager.beginRecording(for: action) },
            onClear: { hotkeyManager.clearBinding(for: action) },
            onRetry: { hotkeyManager.retryRegistration(for: .windowAction(action)) }
        )
        // The master switch stays enabled; disabling lands on the individual
        // binding rows only — a Form/Section-level `.disabled` locks the
        // master toggle itself on macOS 26.
        .disabled(!hotkeyManager.isEnabled)
    }

    /// One window action's conflict with any other Blinker binding.
    private func windowActionConflictWarning(for action: ButtonAction) -> String? {
        guard let combo = hotkeyManager.bindings[action.rawValue] else { return nil }
        return hotkeyManager.internalConflictWarning(for: combo, action: action)
    }

    private var hotkeysEnabledBinding: Binding<Bool> {
        Binding(
            get: { hotkeyManager.isEnabled },
            set: { hotkeyManager.setEnabled($0) }
        )
    }
}
