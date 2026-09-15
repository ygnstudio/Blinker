import BlinkerCore
import SwiftUI

/// The window management tab: saved layouts, desktop switching with
/// drag-to-snap, and the global hotkey configuration. Long explanations
/// live in info popovers instead of multi-line footers; naming a saved
/// layout happens in a proper sheet, not a bare alert.
struct WindowManagementTab: View {
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var workspaceStore: WorkspaceStore
    let onSnapEnabledChange: (Bool) -> Void
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var showingSaveWorkspaceSheet = false

    var body: some View {
        Form {
            workspaceSection
            desktopAndSnapSection
            hotkeySection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingSaveWorkspaceSheet) {
            SaveWorkspaceSheet(store: workspaceStore)
        }
    }

    private func panelButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Workspaces

    private var workspaceSection: some View {
        Section {
            ForEach(workspaceStore.workspaces) { workspace in
                WorkspaceRowView(
                    workspace: workspace,
                    onRestore: { workspaceStore.restore(id: workspace.id) },
                    onUpdate: { workspaceStore.update(id: workspace.id) },
                    onRemove: { workspaceStore.remove(id: workspace.id) }
                )
            }
            Toggle(
                tr("恢复时移回原桌面", "Restore Windows to Their Desktops"),
                isOn: spaceRestoreBinding
            )
            Button {
                showingSaveWorkspaceSheet = true
            } label: {
                Label(tr("保存当前布局…", "Save Current Layout…"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
        } header: {
            SectionHeader(
                title: tr("工作区", "Workspaces"),
                info: tr(
                    "把当前窗口排布存成命名预设，点「恢复」一键还原；最小化和其他桌面的窗口也会一并记录。"
                        + "开启「恢复时移回原桌面」后，窗口会一并回到保存时所在的桌面。"
                        + "同名保存会覆盖旧布局，已退出的应用会被跳过。",
                    "Save the current window arrangement as a named preset and restore it in one click"
                        + " — minimized and other-Space windows are captured too. With \"Restore Windows"
                        + " to Their Desktops\" on, windows also move back to the desktop they were"
                        + " saved on. Saving under an existing name overwrites it; apps that are not"
                        + " running are skipped."
                )
            )
        }
    }

    private var spaceRestoreBinding: Binding<Bool> {
        Binding(
            get: { preferences.isWorkspaceSpaceRestoreEnabled },
            set: { preferences.isWorkspaceSpaceRestoreEnabled = $0 }
        )
    }

    // MARK: - Desktop switching + snapping

    /// Desktop switching and drag-to-snap share one section: each alone was
    /// a one-control group, which wasted a whole form card.
    private var desktopAndSnapSection: some View {
        Section {
            HStack(spacing: 10) {
                panelButton(tr("上一个桌面", "Previous Desktop"), icon: "chevron.left.circle") {
                    SpaceSwitcher.switchDesktop(.previous)
                }
                panelButton(tr("下一个桌面", "Next Desktop"), icon: "chevron.right.circle") {
                    SpaceSwitcher.switchDesktop(.next)
                }
            }
            Toggle(tr("启用拖拽贴靠", "Enable Drag to Snap"), isOn: snapBinding)
        } header: {
            SectionHeader(
                title: tr("桌面与贴靠", "Desktop & Snapping"),
                info: desktopAndSnapInfo
            )
        }
    }

    private var desktopAndSnapInfo: String {
        let desktop = tr(
            "桌面切换通过模拟系统快捷键 ⌃← / ⌃→ 完成；若你在系统设置中改过「调度中心」快捷键，将以系统设置为准。",
            "Desktop switching simulates the system shortcut ⌃← / ⌃→;"
                + " honors whatever Mission Control shortcuts you have set."
        )
        let snap = tr(
            "拖拽贴靠：按住窗口标题栏拖到屏幕边缘或角落，出现预览框后松手即贴靠——"
                + "左右边缘贴半屏，上边缘最大化，四角贴四分之一屏。",
            "Drag to snap: drag a window by its title bar to a screen edge or corner; release"
                + " over the preview to snap. Edges tile to halves, the top edge maximizes,"
                + " corners tile to quarters."
        )
        return desktop + "\n" + snap
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

    private var hotkeySection: some View {
        Section {
            Toggle(tr("启用全局快捷键", "Enable Global Hotkeys"), isOn: hotkeysEnabledBinding)
            // The master switch stays enabled; disabling lands on the
            // individual binding rows only — a Form/Section-level
            // `.disabled` locks the master toggle itself on macOS 26.
            HotkeyRowView(
                label: tr("悬停放大开关", "Toggle Hover Enlargement"),
                combo: hotkeyManager.hoverToggleCombo,
                isRecording: hotkeyManager.recordingTarget == .hoverToggle,
                recordingHint: hotkeyManager.recordingHint,
                conflictWarning: hoverToggleConflictWarning,
                onRecord: { hotkeyManager.beginRecordingHoverToggle() },
                onClear: { hotkeyManager.clearHoverToggleBinding() }
            )
            .disabled(!hotkeyManager.isEnabled)
            ForEach(HotkeyManager.bindableActions, id: \.rawValue) { action in
                HotkeyRowView(
                    label: action.localizedLabel,
                    combo: hotkeyManager.bindings[action.rawValue],
                    isRecording: hotkeyManager.recordingTarget == .windowAction(action),
                    recordingHint: hotkeyManager.recordingHint,
                    conflictWarning: windowActionConflictWarning(for: action),
                    onRecord: { hotkeyManager.beginRecording(for: action) },
                    onClear: { hotkeyManager.clearBinding(for: action) }
                )
                .disabled(!hotkeyManager.isEnabled)
            }
        } header: {
            SectionHeader(
                title: tr("全局快捷键", "Global Hotkeys"),
                info: tr(
                    "在任意应用下按键即可对最前面的窗口执行动作；「悬停放大开关」直接开关悬停放大。"
                        + "点击右侧录制新的快捷键，Esc 取消，减号清除。窗口动作默认方案为 ⌃⌥ 加方向键"
                        + "与 U/I/J/K，悬停开关默认 ⌃⌥H。",
                    "Press anywhere to act on the frontmost window; the hover toggle switches"
                        + " hover enlargement directly. Click a binding to record a new key (Esc cancels);"
                        + " the minus clears it. Window actions default to ⌃⌥ with arrows and U/I/J/K;"
                        + " the hover toggle defaults to ⌃⌥H."
                )
            )
        }
    }

    /// The hover-toggle combo's conflict with any window-action binding.
    private var hoverToggleConflictWarning: String? {
        guard let combo = hotkeyManager.hoverToggleCombo else { return nil }
        return hotkeyManager.internalConflictWarning(for: combo, action: nil)
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

// MARK: - Save-workspace sheet

/// A proper naming form for saving the current layout — a real sheet with
/// a description, replacing the bare Alert + TextField combination.
private struct SaveWorkspaceSheet: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("保存工作区", "Save Workspace"))
                .font(.headline)
            TextField(tr("名称", "Name"), text: $name)
                .textFieldStyle(.roundedBorder)
            Text(tr(
                "记录当前所有可见窗口的位置和大小；同名保存会覆盖旧布局。",
                "Records the position and size of every visible window;"
                    + " saving under an existing name overwrites it."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(tr("取消", "Cancel"), role: .cancel) {
                    dismiss()
                }
                Button(tr("保存", "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.saveCurrentLayout(named: trimmedName)
        dismiss()
    }
}

// MARK: - Workspace row

/// One saved workspace: name, entry count, a primary restore button and
/// an overflow menu for update / delete — the system-list pattern instead
/// of a row of borderless icon buttons.
private struct WorkspaceRowView: View {
    let workspace: SavedWorkspace
    let onRestore: () -> Void
    let onUpdate: () -> Void
    let onRemove: () -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.body)
                Text(tr(
                    "\(workspace.entries.count) 个窗口",
                    workspace.entries.count == 1 ? "1 window" : "\(workspace.entries.count) windows"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(tr("恢复", "Restore"), action: onRestore)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Menu {
                Button(
                    tr("用当前布局覆盖", "Overwrite with Current Layout"),
                    action: onUpdate
                )
                Divider()
                Button(
                    tr("删除", "Delete"),
                    role: .destructive,
                    action: onRemove
                )
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .controlSize(.small)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("更多操作", "More actions"))
            .accessibilityLabel(tr("更多操作", "More actions"))
        }
    }
}

// MARK: - Hotkey row

/// One hotkey binding row: label, current combo (or record prompt), a clear
/// button, plus inline recorder feedback and conflict warnings.
private struct HotkeyRowView: View {
    let label: String
    let combo: HotkeyCombo?
    let isRecording: Bool
    /// Recorder feedback (e.g. "hold a modifier") while this row records.
    let recordingHint: String?
    /// Conflict with another Blinker binding, if any.
    let conflictWarning: String?
    let onRecord: () -> Void
    let onClear: () -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        HStack {
            // The label never changes while recording — swapping it made the
            // whole row jump; the recording state lives on the chip instead.
            Text(label)
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
            Spacer()
            // Fixed-width trailing column: chip and clear button reserve
            // their space even when absent, so all rows share the same
            // right edge.
            HStack(spacing: 6) {
                Button {
                    onRecord()
                } label: {
                    Text(
                        isRecording
                            ? tr("按下快捷键…", "Press keys…")
                            : combo?.displayLabel ?? tr("未设置", "Not Set")
                    )
                    // Wide enough for the recording prompt ("按下快捷键…")
                    // and four-modifier combos ("⌃⌥⇧⌘K"), so no row ellipsizes
                    // and all rows keep a shared right edge.
                    .frame(width: 96)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                Button(role: .destructive, action: onClear) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(tr("清除快捷键", "Clear hotkey"))
                .accessibilityLabel(tr("清除快捷键", "Clear hotkey"))
                .disabled(combo == nil)
                .opacity(combo == nil ? 0 : 1)
            }
        }
        if isRecording {
            // Recorder feedback: the reject reason when the last press was
            // unusable, otherwise the visible cancel affordance.
            Text(recordingHint ?? tr("按 Esc 取消录制", "Esc to cancel"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let conflictWarning {
            WarningLine(text: conflictWarning)
        }
        if let combo, let warning = HotkeyManager.systemConflictWarning(for: combo) {
            WarningLine(text: warning)
        }
    }
}

/// A small warning line: primary-color text (contrast-safe in both
/// appearances) with a decorative orange glyph carrying the tone.
private struct WarningLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.primary)
        }
    }
}
