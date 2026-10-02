import SwiftUI

struct PermissionStatus: View {
    let granted: Bool

    var body: some View {
        Label(granted ? String(localized: "已授权") : String(localized: "未授权"),
              systemImage: granted ? "checkmark.circle.fill" : "circle")
            .font(.callout)
            .foregroundStyle(granted ? Color.green : Color.secondary)
            .fixedSize()
    }
}

/// Settings and onboarding use the same status and user-initiated actions.
struct PermissionRow: View {
    let permission: AppPermission
    @EnvironmentObject private var permissions: PermissionController
    @EnvironmentObject private var assistant: PermissionAssistantController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(permission.title).font(.headline)
                Spacer()
                PermissionStatus(granted: permissions.isGranted(permission))
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(permissions.isGranted(permission) ? "管理权限…" : "授权…") {
                    assistant.show(for: permission)
                }
                Button("重新授权…") { assistant.show(for: permission, reauthorizing: true) }
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: LocalizedStringKey {
        switch permission {
        case .accessibility:
            "用于识别红绿灯、切换与管理窗口。未授权时可以先浏览设置。"
        case .screenRecording:
            "可选，仅用于窗口缩略图。未授权时仍可使用图标和标题，图片只缓存在内存中。"
        }
    }
}
