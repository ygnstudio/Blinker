import BlinkerCore
import SwiftUI

/// Embeds in the window-management Form without creating another scroll container.
struct WorkspaceSettingsSection: View {
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject private var permissions: PermissionController
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var showingSaveWorkspaceSheet = false
    @State private var resultMessage: String?

    var body: some View {
        Section {
            Toggle("启用工作区实验功能", isOn: $preferences.workspaceExperimentsEnabled)
                .disabled(workspaceStore.isBusy)
            ForEach(workspaceStore.workspaces) { workspace in
                WorkspaceRowView(
                    workspace: workspace,
                    onRestore: { restore(workspace) },
                    onUpdate: { update(workspace) },
                    onRemove: { workspaceStore.remove(id: workspace.id) }
                )
                .disabled(!preferences.workspaceExperimentsEnabled || workspaceStore.isBusy)
            }
            Toggle(
                "恢复时移回原桌面",
                isOn: spaceRestoreBinding
            )
            .disabled(!preferences.workspaceExperimentsEnabled || workspaceStore.isBusy)
            Button {
                resultMessage = nil
                showingSaveWorkspaceSheet = true
            } label: {
                Label("保存当前布局…", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(!preferences.workspaceExperimentsEnabled || workspaceStore.isBusy)
            // The save action is a footer-style affordance of the section,
            // not a sibling setting of the toggle above — drop the divider
            // that separated them.
            .listRowSeparator(.hidden, edges: .top)
            Group {
                if let operation = workspaceStore.operation {
                    OperationProgress(message: operation == .saving || isUpdating(operation)
                        ? String(localized: "正在读取窗口布局…") : String(localized: "正在恢复窗口布局…"))
                } else {
                    Text(resultMessage ?? " ").font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(resultMessage == nil)
                }
            }
            .frame(minHeight: 18, alignment: .leading)
            .listRowSeparator(.hidden)
        } header: {
            Text("工作区（实验）")
        } footer: {
            Text("保存并恢复一组窗口的位置和大小。关闭此功能会保留已有布局；同应用的相似窗口可能匹配错误，移回原桌面使用非公开系统接口。")
        }
        .sheet(isPresented: $showingSaveWorkspaceSheet) {
            SaveWorkspaceSheet(store: workspaceStore)
        }
    }

    private func isUpdating(_ operation: WorkspaceStore.Operation) -> Bool {
        if case .updating = operation {
            return true
        }
        return false
    }

    private func restore(_ workspace: SavedWorkspace) {
        guard !workspaceStore.isBusy else { return }
        permissions.refresh()
        guard permissions.accessibilityGranted else {
            resultMessage = WorkspaceRestoreFeedback.message(count: 0, permissionGranted: false)
            return
        }
        resultMessage = nil
        workspaceStore.restore(id: workspace.id) { count in
            permissions.refresh()
            resultMessage = WorkspaceRestoreFeedback.message(
                count: count, permissionGranted: permissions.accessibilityGranted
            )
        }
    }

    private func update(_ workspace: SavedWorkspace) {
        guard !workspaceStore.isBusy else { return }
        resultMessage = nil
        workspaceStore.update(id: workspace.id) {
            resultMessage = String(localized: "布局已更新")
        }
    }

    private var spaceRestoreBinding: Binding<Bool> {
        Binding(
            get: { preferences.isWorkspaceSpaceRestoreEnabled },
            set: { preferences.isWorkspaceSpaceRestoreEnabled = $0 }
        )
    }
}

/// Classifies completion feedback without performing another window operation.
enum WorkspaceRestoreFeedback {
    static func message(count: Int, permissionGranted: Bool) -> String {
        if count > 0 {
            return String(localized: "已恢复 \(count) 个窗口")
        }
        if !permissionGranted {
            return String(localized: "需要辅助功能权限才能恢复窗口，请在「隐私与权限」中授权。")
        }
        return String(localized: "未能恢复任何窗口，请确认应用仍在运行，且窗口支持移动或调整大小。")
    }
}

// MARK: - Save-workspace sheet

/// A proper naming form for saving the current layout — a real sheet with
/// a description, replacing the bare Alert + TextField combination.
private struct SaveWorkspaceSheet: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存工作区")
                .font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameIsFocused)
                .disabled(store.isBusy)
            Text("记录当前可识别窗口的位置和大小，包括最小化和其他桌面的窗口；同名保存会覆盖旧布局。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Group {
                if store.isBusy {
                    OperationProgress(message: String(localized: "正在读取窗口布局…"))
                } else {
                    Text(" ").font(.caption).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 18, alignment: .leading)
            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .disabled(store.isBusy)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || store.isBusy)
            }
        }
        .padding(20)
        .frame(width: 320)
        .interactiveDismissDisabled(store.isBusy)
        .defaultFocus($nameIsFocused, true)
    }

    private func save() {
        guard !trimmedName.isEmpty, !store.isBusy else { return }
        store.saveCurrentLayout(named: trimmedName) { dismiss() }
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
