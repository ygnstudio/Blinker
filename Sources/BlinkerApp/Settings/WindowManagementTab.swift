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
                title: String(localized: "半屏"),
                actions: [.tileLeft, .tileRight, .tileTop, .tileBottom]
            )
            hotkeyGroupSection(
                title: String(localized: "四分屏"),
                actions: [
                    .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight
                ]
            )
            hotkeyGroupSection(
                title: String(localized: "整窗"),
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
                "恢复时移回原桌面",
                isOn: spaceRestoreBinding
            )
            Button {
                showingSaveWorkspaceSheet = true
            } label: {
                Label("保存当前布局…", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            // The save action is a footer-style affordance of the section,
            // not a sibling setting of the toggle above — drop the divider
            // that separated them.
            .listRowSeparator(.hidden, edges: .top)
        } header: {
            SectionHeader(
                title: String(localized: "工作区"),
                // swiftlint:disable:next line_length
                info: String(localized: "把当前窗口排布存成命名预设，点「恢复」一键还原；最小化和其他桌面的窗口也会一并记录。开启「恢复时移回原桌面」后，窗口会一并回到保存时所在的桌面。同名保存会覆盖旧布局，已退出的应用会被跳过。")
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
                panelButton("上一个桌面", icon: "chevron.left.circle") {
                    SpaceSwitcher.switchDesktop(.previous)
                }
                panelButton("下一个桌面", icon: "chevron.right.circle") {
                    SpaceSwitcher.switchDesktop(.next)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("开启拖拽贴靠", isOn: snapBinding)
        } header: {
            SectionHeader(
                title: String(localized: "桌面与贴靠"),
                info: desktopAndSnapInfo
            )
        }
    }

    private var desktopAndSnapInfo: String {
        let desktop = String(localized: "桌面切换通过模拟系统快捷键 ⌃← / ⌃→ 完成；若你在系统设置中改过「调度中心」快捷键，将以系统设置为准。")
        let snap = String(localized: "拖拽贴靠：按住窗口标题栏拖到屏幕边缘或角落，出现预览框后松手即贴靠——左右边缘贴半屏，上边缘最大化，四角贴四分之一屏。")
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
            Toggle("开启全局快捷键", isOn: hotkeysEnabledBinding)
        } header: {
            SectionHeader(
                title: String(localized: "全局快捷键"),
                // swiftlint:disable:next line_length
                info: String(localized: "在任意应用下按键即可对最前面的窗口执行动作。点击右侧录制新的快捷键，Esc 取消，减号清除。窗口动作默认方案为 ⌃⌥ 加方向键与 U/I/J/K；悬停放大开关的快捷键在「悬停放大」页配置。")
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
            Text("保存工作区")
                .font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("记录当前所有可见窗口的位置和大小；同名保存会覆盖旧布局。")
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                Button("保存", action: save)
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.body)
                Text(String(localized: "\(workspace.entries.count) 个窗口"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("恢复", action: onRestore)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Menu {
                Button(
                    "用当前布局覆盖",
                    action: onUpdate
                )
                Divider()
                Button(
                    "删除",
                    role: .destructive,
                    action: onRemove
                )
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .controlSize(.small)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
            .accessibilityLabel("更多操作")
        }
    }
}
