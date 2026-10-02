import AppKit
import SwiftUI

/// Keeps the app file available for dragging while System Settings is active.
@MainActor
final class PermissionAssistantController: ObservableObject {
    private let permissions: PermissionController
    private var panel: NSPanel?

    init(permissions: PermissionController) {
        self.permissions = permissions
    }

    func show(for permission: AppPermission, reauthorizing: Bool = false) {
        let panel = panel ?? makePanel()
        panel.contentViewController = NSHostingController(rootView: PermissionAssistantView(
            permission: permission,
            reauthorizing: reauthorizing,
            permissions: permissions,
            onClose: { [weak self] in self?.panel?.close() }
        ))
        panel.title = permission.title
        panel.setContentSize(NSSize(width: 360, height: 400))
        if !panel.isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(
                    x: max(visible.minX, visible.maxX - panel.frame.width - 20),
                    y: max(visible.minY, visible.midY - panel.frame.height / 2)
                ))
            }
        }
        panel.makeKeyAndOrderFront(nil)
        if reauthorizing {
            permissions.openSettings(for: permission)
        } else {
            permissions.request(for: permission)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

private struct PermissionAssistantView: View {
    let permission: AppPermission
    let reauthorizing: Bool
    @ObservedObject var permissions: PermissionController
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(reauthorizing ? "重新授权" : "完成授权").font(.title2.bold())
                Spacer()
                PermissionStatus(granted: permissions.isGranted(permission))
            }
            ScrollView {
                instructions
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("重新检查权限") { permissions.refresh() }
                Spacer()
                Button("完成", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { permissions.refresh() }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reauthorizing
                ? "在系统列表中关闭再开启 Blinker。若仍无效，移除旧条目，再将下方应用拖入列表。"
                : "在系统设置中开启 Blinker。列表里没有时，可将下方应用拖入列表。")
                .font(.callout)
            VStack(spacing: 6) {
                DraggableAppIcon(appURL: permissions.appURL)
                Text("拖动此图标添加 Blinker").font(.callout)
            }
            .frame(maxWidth: .infinity)
            Text("拖入后仍需在系统设置中确认允许。若无法拖入，可在访达中显示应用，再通过列表下方的加号添加。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("打开系统设置…") { permissions.openSettings(for: permission) }
                Button("在访达中显示") { permissions.revealApp() }
                    .disabled(permissions.appURL == nil)
            }
            if permissions.settingsOpenFailed {
                Text("无法打开系统设置，请前往「隐私与安全性」并选择对应权限。")
                    .font(.caption).foregroundStyle(.orange)
            }
            if permission == .screenRecording {
                Text("若系统提示退出并重新打开，请按提示重启 Blinker，让录屏权限生效。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
