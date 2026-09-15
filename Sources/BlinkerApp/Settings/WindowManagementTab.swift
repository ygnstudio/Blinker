import BlinkerCore
import SwiftUI

/// The window management tab: saved layouts, desktop switching with
/// drag-to-snap, and the global hotkey configuration. Long explanations
/// live in info popovers instead of multi-line footers; naming a saved
/// layout happens in a proper sheet, not a bare alert. Hotkey bindings are
/// grouped into halves / quarters / whole-window sections so the flat
/// eleven-row list reads as browsable chunks; the hover-toggle hotkey lives
/// on the hover tab, next to the feature it controls.
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
            hotkeySwitchSection
            hotkeyGroupSection(
                title: tr("半屏", "Halves"),
                actions: [.tileLeft, .tileRight, .tileTop, .tileBottom]
            )
            hotkeyGroupSection(
                title: tr("四分屏", "Quarters"),
                actions: [
                    .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight
                ]
            )
            hotkeyGroupSection(
                title: tr("整窗", "Window"),
                actions: [.maximize, .almostMaximize, .centerWindow, .moveToNextDisplay]
            )
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingSaveWorkspaceSheet) {
            SaveWorkspaceSheet(store: workspaceStore)
        }
    }

    /// Compact leading-aligned desktop buttons — small bordered controls,
    /// not two full-width giant buttons.
    private func panelButton(
        _ label: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
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
            // The save action is a footer-style affordance of the section,
            // not a sibling setting of the toggle above — drop the divider
            // that separated them.
            .listRowSeparator(.hidden, edges: .top)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(tr("开启拖拽贴靠", "Enable Drag to Snap"), isOn: snapBinding)
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

    /// The master switch; the binding rows live in the three groups below.
    private var hotkeySwitchSection: some View {
        Section {
            Toggle(tr("开启全局快捷键", "Enable Global Hotkeys"), isOn: hotkeysEnabledBinding)
        } header: {
            SectionHeader(
                title: tr("全局快捷键", "Global Hotkeys"),
                info: tr(
                    "在任意应用下按键即可对最前面的窗口执行动作。点击右侧录制新的快捷键，Esc 取消，"
                        + "减号清除。窗口动作默认方案为 ⌃⌥ 加方向键与 U/I/J/K；"
                        + "悬停放大开关的快捷键在「悬停放大」页配置。",
                    "Press anywhere to act on the frontmost window. Click a binding to record a new"
                        + " key (Esc cancels); the minus clears it. Window actions default to ⌃⌥ with"
                        + " arrows and U/I/J/K; the hover-toggle hotkey lives on the Hover tab."
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
            onRecord: { hotkeyManager.beginRecording(for: action) },
            onClear: { hotkeyManager.clearBinding(for: action) }
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
