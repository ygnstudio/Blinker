import SwiftUI

struct DesktopQuickActionRow: View {
    @ObservedObject var coordinator: DesktopActionsCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "menubar.dock.rectangle").frame(width: 18)
                Text("桌面窗口")
                Spacer(minLength: 8)
                Button(coordinator.desktop.isDesktopShown ? String(localized: "恢复窗口")
                    : String(localized: "显示桌面")) { coordinator.toggleDesktop() }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.isPaused || coordinator.desktop.isBusy)
            }
            .frame(minHeight: 28)
            if coordinator.desktop.isBusy {
                OperationProgress(message: String(localized: "正在调整窗口…"))
            } else if coordinator.isPaused {
                Text("窗口增强已暂停，请先恢复运行。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if coordinator.desktop.lastFailureCount > 0 {
                Text("有 \(coordinator.desktop.lastFailureCount) 个窗口未能完成操作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
