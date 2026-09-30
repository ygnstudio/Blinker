import BlinkerCore
import SwiftUI

struct ExperimentalSettingsTab: View {
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var showingSaveWorkspaceSheet = false

    var body: some View {
        Form {
            Section {
                Toggle("启用工作区实验功能", isOn: $preferences.workspaceExperimentsEnabled)
            } footer: {
                Text("布局按窗口特征匹配，同应用的相似窗口可能配错。原桌面恢复使用非公开系统接口。已有布局会保留。")
            }
            workspaceSection.disabled(!preferences.workspaceExperimentsEnabled)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingSaveWorkspaceSheet) {
            SaveWorkspaceSheet(store: workspaceStore)
        }
    }

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
                info: String(
                    // swiftlint:disable:next line_length
                    localized: "把当前窗口排布存成命名预设，点「恢复」一键还原；最小化和其他桌面的窗口也会一并记录。开启「恢复时移回原桌面」后，窗口会一并回到保存时所在的桌面。同名保存会覆盖旧布局，已退出的应用会被跳过。"
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
