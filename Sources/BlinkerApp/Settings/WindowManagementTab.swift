import BlinkerCore
import SwiftUI

/// The window management tab: an instant action panel that manipulates the
/// frontmost window right away, plus the drag-to-snap and global hotkey
/// configuration.
struct WindowManagementTab: View {
    let frontWindowPerformer: FrontWindowActionPerformer
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var workspaceStore: WorkspaceStore
    let onSnapEnabledChange: (Bool) -> Void
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var frontAppName = ""
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
            instantPanelSection
            workspaceSection
            spaceSection
            snapSection
            hotkeySection
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshFrontAppName)
        .onReceive(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didActivateApplicationNotification)
        ) { _ in
            refreshFrontAppName()
        }
    }

    // MARK: - Instant panel

    private var instantPanelSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Self.gridPlacements, id: \.self) { placement in
                    PlacementTile(placement: placement) {
                        frontWindowPerformer.perform(placement.action)
                    }
                }
            }
            HStack(spacing: 10) {
                panelButton(tr("最大化", "Maximize"), icon: "arrow.up.backward.and.arrow.down.forward") {
                    frontWindowPerformer.perform(.maximize)
                }
                panelButton(tr("准最大化", "Almost Maximize"), icon: "rectangle.compress.vertical") {
                    frontWindowPerformer.perform(.almostMaximize)
                }
                panelButton(tr("下一显示器", "Next Display"), icon: "display.2") {
                    frontWindowPerformer.perform(.moveToNextDisplay)
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(tr("即时操作", "Instant Actions"))
                if !frontAppName.isEmpty {
                    Text("· \(frontAppName)")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(tr(
                "点击立即对最前面的窗口生效，无需配置规则。",
                "Clicks act on the frontmost window immediately — no rules needed."
            ))
        }
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
                "把当前窗口排布存成命名预设，点「恢复」一键还原。已退出的应用会被跳过，重新打开后恢复即生效。",
                "Save the current window arrangement as a named preset and restore it in one click. "
                    + "Apps that are not running are skipped."
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
            ForEach(HotkeyManager.bindableActions, id: \.rawValue) { action in
                HotkeyRowView(
                    action: action,
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
                "在任意应用下按键即可对最前面的窗口执行动作。点击右侧录制新的快捷键，"
                    + "Esc 取消，减号清除。"
                    + "默认方案为 ⌃⌥ 加方向键与 U/I/J/K。",
                "Press anywhere to act on the frontmost window. Click a binding to record a new key "
                    + "(Esc cancels); "
                    + "the minus clears it. The default scheme is ⌃⌥ with arrows and U/I/J/K."
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

    private func refreshFrontAppName() {
        frontAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }
}

// MARK: - Placement tile

/// One grid button: a mini screen with the target region highlighted.
private struct PlacementTile: View {
    let placement: BlinkerCore.WindowPlacement
    let onPerform: () -> Void

    var body: some View {
        Button(action: onPerform) {
            VStack(spacing: 5) {
                miniScreen
                Text(placement.action.localizedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var miniScreen: some View {
        let frame = WindowGeometry.tiledFrame(placement, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return ZStack(alignment: alignment(for: placement)) {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: max(8, frame.width * 44), height: max(6, frame.height * 30))
        }
        .frame(width: 46, height: 32)
    }

    private func alignment(for placement: BlinkerCore.WindowPlacement) -> Alignment {
        switch placement {
        case .topLeft: .topLeading
        case .top: .top
        case .topRight: .topTrailing
        case .left: .leading
        case .center: .center
        case .right: .trailing
        case .bottomLeft: .bottomLeading
        case .bottom: .bottom
        case .bottomRight: .bottomTrailing
        case .maximize, .almostMaximize: .center
        }
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

/// One hotkey binding row: action label, current combo (or record prompt) and
/// a clear button.
private struct HotkeyRowView: View {
    let action: ButtonAction
    let combo: HotkeyCombo?
    let isRecording: Bool
    let onRecord: () -> Void
    let onClear: () -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        HStack {
            Text(action.localizedLabel)
            Spacer()
            if isRecording {
                Text(tr("按下快捷键…（Esc 取消）", "Press keys… (Esc to cancel)"))
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
            } else {
                Button {
                    onRecord()
                } label: {
                    Text(combo?.displayLabel ?? tr("未设置", "Not Set"))
                        .frame(minWidth: 72)
                }
                .buttonStyle(.bordered)
                if combo != nil {
                    Button(role: .destructive, action: onClear) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(tr("清除快捷键", "Clear hotkey"))
                }
            }
        }
        if let combo, let warning = HotkeyManager.systemConflictWarning(for: combo) {
            Text(warning)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Mapping helpers

extension BlinkerCore.WindowPlacement {
    /// The window action that performs this placement.
    var action: ButtonAction {
        switch self {
        case .maximize: .maximize
        case .almostMaximize: .almostMaximize
        case .left: .tileLeft
        case .right: .tileRight
        case .top: .tileTop
        case .bottom: .tileBottom
        case .topLeft: .tileTopLeft
        case .topRight: .tileTopRight
        case .bottomLeft: .tileBottomLeft
        case .bottomRight: .tileBottomRight
        case .center: .centerWindow
        }
    }
}
