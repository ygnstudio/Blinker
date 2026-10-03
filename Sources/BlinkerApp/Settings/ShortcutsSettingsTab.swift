import BlinkerCore
import SwiftUI

/// One editor for placement and hover shortcuts, with a link to the independent switcher.
struct ShortcutsSettingsTab: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var browser: WindowBrowserController
    let onOpenBrowser: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("启用布局与悬停快捷键", isOn: hotkeysEnabledBinding)
            } footer: {
                Text("点击组合录制快捷键，Esc 取消，减号清除。此开关同时控制窗口布局和悬停放大快捷键。")
            }
            Section("悬停放大") {
                hoverToggleHotkeyRow
            }
            WindowSwitcherShortcutSection(browser: browser, preferences: browser.preferences,
                                          onOpenBrowser: onOpenBrowser)
            hotkeyGroupSection(
                title: String(localized: "半屏"),
                actions: [.tileLeft, .tileRight, .tileTop, .tileBottom]
            )
            hotkeyGroupSection(
                title: String(localized: "四分屏"),
                actions: [.tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight]
            )
            hotkeyGroupSection(
                title: String(localized: "三分屏"),
                actions: [.tileFirstThird, .tileCenterThird, .tileLastThird,
                          .tileFirstTwoThirds, .tileLastTwoThirds]
            )
            hotkeyGroupSection(
                title: String(localized: "整窗"),
                actions: [.maximize, .almostMaximize, .centerWindow,
                          .moveToNextDisplay, .restorePreviousFrame]
            )
        }
        .formStyle(.grouped)
        .onDisappear { hotkeyManager.endRecording() }
    }

    private func hotkeyGroupSection(title: String, actions: [ButtonAction]) -> some View {
        Section {
            ForEach(actions, id: \.rawValue) { action in
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
                // Disable rows, keeping the master switch and switcher navigation available.
                .disabled(!hotkeyManager.isEnabled)
            }
        } header: {
            Text(title)
        }
    }

    private var hoverToggleHotkeyRow: some View {
        HotkeyRowView(
            label: String(localized: "悬停放大开关"),
            combo: hotkeyManager.hoverToggleCombo,
            isRecording: hotkeyManager.recordingTarget == .hoverToggle,
            recordingHint: hotkeyManager.recordingHint,
            conflictWarning: hoverToggleConflictWarning,
            registrationWarning: hotkeyManager.registrationWarning(for: .hoverToggle),
            onRecord: { hotkeyManager.beginRecordingHoverToggle() },
            onClear: { hotkeyManager.clearHoverToggleBinding() },
            onRetry: { hotkeyManager.retryRegistration(for: .hoverToggle) }
        )
        .disabled(!hotkeyManager.isEnabled)
    }

    private func windowActionConflictWarning(for action: ButtonAction) -> String? {
        guard let combo = hotkeyManager.bindings[action.rawValue] else { return nil }
        return hotkeyManager.internalConflictWarning(for: combo, action: action)
    }

    private var hoverToggleConflictWarning: String? {
        guard let combo = hotkeyManager.hoverToggleCombo else { return nil }
        return hotkeyManager.internalConflictWarning(for: combo, action: nil)
    }

    private var hotkeysEnabledBinding: Binding<Bool> {
        Binding(
            get: { hotkeyManager.isEnabled },
            set: { enabled in
                if !enabled {
                    hotkeyManager.endRecording()
                }
                hotkeyManager.setEnabled(enabled)
            }
        )
    }
}

private struct WindowSwitcherShortcutSection: View {
    @ObservedObject var browser: WindowBrowserController
    @ObservedObject var preferences: WindowBrowserPreferences
    let onOpenBrowser: () -> Void

    var body: some View {
        Section {
            LabeledContent("⌥Tab 窗口切换", value: preferences.switcherEnabled
                ? String(localized: "已启用") : String(localized: "已关闭"))
            if preferences.switcherEnabled, !browser.shortcutAvailable {
                Text("⌥Tab 已被其他应用占用。请停用冲突的快捷键后重新开启。")
                    .foregroundStyle(.orange)
            }
            Button("前往预览与切换…", action: onOpenBrowser)
        } header: {
            Text("窗口切换")
        } footer: {
            Text("⌥Tab 独立启用，不受上方开关影响。")
        }
    }
}
