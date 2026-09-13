import BlinkerCore
import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some Scene {
        MenuBarExtra("Blinker", systemImage: "circle.circle") {
            InterceptorStatusRow(appDelegate: appDelegate)
            Divider()
            Button(tr("设置…", "Settings…")) {
                appDelegate.bringToFront()
                openSettings()
            }
            Button(
                appDelegate.isIntercepting
                    ? tr("暂停拦截", "Pause Interception")
                    : tr("恢复拦截", "Resume Interception")
            ) {
                appDelegate.toggleInterception()
            }
            .disabled(!appDelegate.isIntercepting && appDelegate.status == .noPermission)
            Button(tr("重新检查权限", "Re-check Permission")) {
                appDelegate.attemptStartInterceptor()
            }
            .disabled(appDelegate.isIntercepting)
            Divider()
            Button(tr("退出 Blinker", "Quit Blinker")) { NSApp.terminate(nil) }
        }

        Settings {
            SettingsScreen(
                ruleStore: appDelegate.ruleStore,
                hoverSettingsStore: appDelegate.hoverOverlaySettingsStore,
                onApplyHoverSettings: appDelegate.applyHoverOverlaySettings
            )
        }
    }
}
