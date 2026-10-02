import SwiftUI

struct PermissionsSettingsTab: View {
    @EnvironmentObject private var permissions: PermissionController

    var body: some View {
        Form {
            Section {
                ForEach(AppPermission.allCases) { permission in
                    PermissionRow(permission: permission)
                }
                Button("重新检查权限") { permissions.refresh() }
            } header: {
                Text("系统权限")
            } footer: {
                Text("返回 Blinker 时会自动检查授权状态。授权助手可直接拖出当前应用，无需查找安装位置。")
            }

            Section {
                Text("授权后仍无法使用时，点击对应权限的「重新授权…」，按助手提示更新系统列表中的 Blinker。")
                Text("若系统提示退出并重新打开，请按提示重启 Blinker，让录屏权限生效。")
            } header: {
                Text("授权遇到问题")
            } footer: {
                Text("规则与窗口内容在本机处理，不上传数据，不收集使用统计。")
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }
}
