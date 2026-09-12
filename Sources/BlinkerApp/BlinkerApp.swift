import BlinkerCore
import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra("Blinker", systemImage: "circle.circle") {
            InterceptorStatusRow(appDelegate: appDelegate)
            Divider()
            Button("设置…") {
                appDelegate.bringToFront()
                openSettings()
            }
            Button("重新检查权限") {
                appDelegate.attemptStartInterceptor()
            }
            .disabled(appDelegate.isIntercepting)
            Divider()
            Button("退出 Blinker") { NSApp.terminate(nil) }
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
