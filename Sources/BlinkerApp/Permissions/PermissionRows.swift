import SwiftUI

/// A synchronous check gets a completion cue, never an artificial loading delay.
struct PermissionCheckButton: View {
    @EnvironmentObject private var permissions: PermissionController
    @State private var didCheck = false

    var body: some View {
        HStack(spacing: 6) {
            Button("重新检查权限") {
                permissions.refresh()
                didCheck = true
            }
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .opacity(didCheck ? 1 : 0)
                .accessibilityHidden(!didCheck)
                .accessibilityLabel("已完成检查")
                .help("已完成检查")
        }
    }
}

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
    var allowsManagement = true
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
            if allowsManagement || !permissions.isGranted(permission) {
                Button(permissions.isGranted(permission) ? "管理权限…" : "授权…") {
                    assistant.show(for: permission)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: LocalizedStringKey {
        switch permission {
        case .accessibility:
            "用于识别红绿灯、切换与管理窗口。未授权时可以先浏览设置。"
        case .screenRecording:
            "可选，用于窗口缩略图和开合盖屏幕特效。画面只在内存中处理，不录音、不保存录像。"
        }
    }
}
