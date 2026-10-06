import SwiftUI

struct PermissionsSettingsTab: View {
    @EnvironmentObject private var permissions: PermissionController
    @EnvironmentObject private var assistant: PermissionAssistantController

    var body: some View {
        Form {
            Section {
                ForEach(AppPermission.allCases) { permission in
                    PermissionRow(permission: permission)
                }
                PermissionCheckButton()
            } header: {
                Text("系统权限")
            } footer: {
                Text("返回 Blinker 时会自动检查授权状态。授权助手可直接拖出当前应用，无需查找安装位置。")
            }

            Section {
                DisclosureGroup("授权后仍无法使用") {
                    Button("重新授权辅助功能…") {
                        assistant.show(for: .accessibility, reauthorizing: true)
                    }
                    Button("重新授权屏幕录制…") {
                        assistant.show(for: .screenRecording, reauthorizing: true)
                    }
                    Button("重新授权输入监控…") {
                        assistant.show(for: .inputMonitoring, reauthorizing: true)
                    }
                    Text("授权助手会引导你更新系统列表中的 Blinker，不会自动重置权限。")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("若系统提示退出并重新打开，请按提示重启 Blinker，让录屏权限生效。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("本机数据") {
                Text("规则与窗口内容在本机处理，不上传数据，不收集使用统计。")
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }
}
