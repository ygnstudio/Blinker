import BlinkerCore
import SwiftUI

/// The window management tab: an instant action panel that manipulates the
/// frontmost window right away, plus the drag-to-snap and global hotkey
/// configuration.
struct WindowManagementTab: View {
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var workspaceStore: WorkspaceStore
    let onSnapEnabledChange: (Bool) -> Void
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var showingSaveWorkspaceAlert = false
    @State private var draftWorkspaceName = ""

    /// The nine grid placements, in reading order.
    private static let gridPlacements: [BlinkerCore.WindowPlacement] = [
        .topLeft, .top, .topRight,
        .left, .center, .right,
        .bottomLeft, .bottom, .bottomRight,
    ]

    var body: some View {
        Form {
            workspaceSection
            spaceSection
            snapSection
            hotkeySection
        }
        .formStyle(.grouped)
    }

    private func panelButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
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
            Button {
                draftWorkspaceName = ""
                showingSaveWorkspaceAlert = true
            } label: {
                Label(tr("保存当前布局…", "Save Current Layout…"), systemImage: "plus")
            }
            .alert(
                tr("保存工作区", "Save Workspace"),
                isPresented: $showingSaveWorkspaceAlert
            ) {
                TextField(tr("名称", "Name"), text: $draftWorkspaceName)
                Button(tr("保存", "Save")) {
                    let name = draftWorkspaceName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    workspaceStore.saveCurrentLayout(named: name)
                }
                Button(tr("取消", "Cancel"), role: .cancel) {}
            } message: {
                Text(tr(
                    "记录当前所有可见窗口的位置和大小；同名保存会覆盖旧布局。",
                    "Records the position and size of every visible window; "
                        + "saving under an existing name overwrites it."
                ))
            }
        } header: {
            Text(tr("工作区", "Workspaces"))
        } footer: {
            Text(tr(
                "把当前窗口排布存成命名预设，点「恢复」一键还原；最小化和其他桌面的窗口也会一并记录。同名保存会覆盖旧布局，已退出的应用会被跳过。",
                "Save the current window arrangement as a named preset and restore it in one click — "
                    + "minimized and other-Space windows are captured too. Saving under an existing name "
                    + "overwrites it; apps that are not running are skipped."
            ))
        }
    }

    // MARK: - Space switching

    private var spaceSection: some View {
        Section {
            HStack(spacing: 10) {
                panelButton(tr("上一个桌面", "Previous Desktop"), icon: "chevron.left.circle") {
                    SpaceSwitcher.switchDesktop(.previous)
                }
                panelButton(tr("下一个桌面", "Next Desktop"), icon: "chevron.right.circle") {
                    SpaceSwitcher.switchDesktop(.next)
                }
            }
        } header: {
            Text(tr("桌面切换", "Desktop Switching"))
        } footer: {
            Text(tr(
                "通过模拟系统快捷键 ⌃← / ⌃→ 切换桌面；若你在系统设置中改过“调度中心”快捷键，将以系统设置为准。",
                "Switches desktops by simulating the system shortcut ⌃← / ⌃→; "
                    + "honors whatever Mission Control shortcuts you have set."
            ))
        }
    }

    // MARK: - Snap

    private var snapSection: some View {
        Section {
            Toggle(tr("启用拖拽贴靠", "Enable Drag to Snap"), isOn: snapBinding)
        } header: {
            Text(tr("拖拽贴靠", "Drag to Snap"))
        } footer: {
            Text(tr(
                "按住窗口标题栏拖到屏幕边缘或角落，出现预览框后松手即贴靠："
                    + "左右边缘贴半屏，上边缘最大化，四角贴四分之一屏。",
                "Drag a window by its title bar to a screen edge or corner; release over the preview to snap."
                    + " Edges tile to halves, the top edge maximizes, corners tile to quarters."
            ))
        }
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
                // Keep the master switch clickable while the bindings are
                // grayed out, otherwise the toggle locks itself out.
                .disabled(false)
            HotkeyRowView(
                label: tr("悬停放大开关", "Toggle Hover Enlargement"),
                combo: hotkeyManager.hoverToggleCombo,
                isRecording: hotkeyManager.isRecordingHoverToggle,
                onRecord: { hotkeyManager.beginRecordingHoverToggle() },
                onClear: { hotkeyManager.clearHoverToggleBinding() }
            )
            ForEach(HotkeyManager.bindableActions, id: \.rawValue) { action in
                HotkeyRowView(
                    label: action.localizedLabel,
                    combo: hotkeyManager.bindings[action.rawValue],
                    isRecording: hotkeyManager.recordingAction == action,
                    onRecord: { hotkeyManager.beginRecording(for: action) },
                    onClear: { hotkeyManager.clearBinding(for: action) }
                )
            }
        } header: {
            Text(tr("全局快捷键", "Global Hotkeys"))
        } footer: {
            Text(tr(
                "在任意应用下按键即可对最前面的窗口执行动作；「悬停放大开关」直接开关悬停放大。"
                    + "点击右侧录制新的快捷键，Esc 取消，减号清除。"
                    + "窗口动作默认方案为 ⌃⌥ 加方向键与 U/I/J/K，悬停开关默认 ⌃⌥H。",
                "Press anywhere to act on the frontmost window; the hover toggle switches hover "
                    + "enlargement directly. Click a binding to record a new key (Esc cancels); "
                    + "the minus clears it. Window actions default to ⌃⌥ with arrows and "
                    + "U/I/J/K; the hover toggle defaults to ⌃⌥H."
            ))
        }
        .disabled(!hotkeyManager.isEnabled)
    }

    private var hotkeysEnabledBinding: Binding<Bool> {
        Binding(
            get: { hotkeyManager.isEnabled },
            set: { hotkeyManager.setEnabled($0) }
        )
    }
}

// MARK: - Workspace row

/// One saved workspace: name, entry count and restore / update / delete
/// actions.
private struct WorkspaceRowView: View {
    let workspace: SavedWorkspace
    let onRestore: () -> Void
    let onUpdate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.body)
                Text(tr(
                    "\(workspace.entries.count) 个窗口",
                    "\(workspace.entries.count) windows"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRestore) {
                Image(systemName: "arrow.counterclockwise.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("恢复此工作区", "Restore this workspace"))
            Button(action: onUpdate) {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("用当前布局覆盖", "Overwrite with current layout"))
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("删除此工作区", "Delete this workspace"))
        }
    }
}

// MARK: - Hotkey row

/// One hotkey binding row: label, current combo (or record prompt) and a
/// clear button.
private struct HotkeyRowView: View {
    let label: String
    let combo: HotkeyCombo?
    let isRecording: Bool
    let onRecord: () -> Void
    let onClear: () -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        HStack {
            // While recording the prompt replaces the label so the trailing
            // column (chip + clear) keeps a fixed width on every row.
            Text(
                isRecording
                    ? tr("按下快捷键…（Esc 取消）", "Press keys… (Esc to cancel)")
                    : label
            )
            .font(isRecording ? .callout : .body)
            .foregroundStyle(isRecording ? Color.accentColor : .primary)
            Spacer()
            // Fixed-width trailing column: chip and clear button reserve
            // their space even when absent, so all rows share the same
            // right edge.
            HStack(spacing: 6) {
                Button {
                    onRecord()
                } label: {
                    Text(combo?.displayLabel ?? tr("未设置", "Not Set"))
                        .frame(width: 84)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive, action: onClear) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(tr("清除快捷键", "Clear hotkey"))
                .disabled(combo == nil)
                .opacity(combo == nil ? 0 : 1)
            }
        }
        if let combo, let warning = HotkeyManager.systemConflictWarning(for: combo) {
            Text(warning)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}
