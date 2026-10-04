import BlinkerCore
import SwiftUI

/// Window placement preferences and the optional saved-workspace experiment.
struct WindowManagementTab: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @EnvironmentObject private var desktopActions: DesktopActionsCoordinator
    @EnvironmentObject private var permissions: PermissionController
    @EnvironmentObject private var permissionAssistant: PermissionAssistantController
    let onSnapEnabledChange: (Bool) -> Void
    let onOpenShortcuts: () -> Void

    var body: some View {
        Form {
            Section {
                Button("配置窗口快捷键…", action: onOpenShortcuts)
            } header: {
                Text("布局与快捷键")
            } footer: {
                Text("窗口布局和显示桌面的快捷键统一在「快捷键」中设置，与拖拽贴靠分别启用。")
            }
            dockSection
            desktopSection
            Section {
                Toggle("开启拖拽贴靠", isOn: snapBinding)
            } header: {
                Text("拖拽贴靠（可选）")
            } footer: {
                Text("默认关闭。启用前请确认不会与系统或其他窗口管理工具的拖拽贴靠重复。")
            }
            WorkspaceSettingsSection()
        }
        .formStyle(.grouped)
    }

    private var dockSection: some View {
        Section {
            Toggle("点击 Dock 图标收起窗口", isOn: $preferences.isDockClickMinimizeEnabled)
            if preferences.isDockClickMinimizeEnabled {
                if !permissions.accessibilityGranted {
                    Button("授权辅助功能…") { permissionAssistant.show(for: .accessibility) }
                } else if desktopActions.isPaused {
                    Text("全局暂停期间不处理 Dock 点击。").foregroundStyle(.secondary)
                } else if !desktopActions.dock.isAvailable {
                    HStack {
                        Text("Dock 点击监听未启动。").foregroundStyle(.secondary)
                        Spacer()
                        Button("重试") { desktopActions.retryDock() }
                    }
                }
            }
        } header: {
            Text("Dock 点击")
        } footer: {
            Text("点击前台应用的 Dock 图标，收起它在当前桌面的普通窗口；再次点击恢复。其他应用的打开方式保持系统默认。")
        }
    }

    private var desktopSection: some View {
        Section {
            HStack {
                Button(desktopActions.desktop.isDesktopShown ? String(localized: "恢复窗口")
                    : String(localized: "显示桌面")) { desktopActions.toggleDesktop() }
                    .disabled(desktopActions.isPaused || desktopActions.desktop.isBusy)
                if desktopActions.desktop.isBusy {
                    OperationProgress(message: String(localized: "正在调整窗口…"))
                }
                Spacer()
            }
            if desktopActions.desktop.lastFailureCount > 0 {
                Text("有 \(desktopActions.desktop.lastFailureCount) 个窗口未能完成操作。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("显示桌面与恢复")
        } footer: {
            Text("收起当前桌面的普通窗口，再次执行只恢复本次收起的窗口。原本最小化和全屏的窗口保持原状；切换桌面后不再恢复上一桌面的窗口。")
        }
    }

    private var snapBinding: Binding<Bool> {
        Binding(
            get: { preferences.isSnapEnabled },
            // The coordinator owns both persistence and applying the live snapper state.
            set: onSnapEnabledChange
        )
    }
}
