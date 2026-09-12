import BlinkerCore
import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Blinker", systemImage: "circle.circle") {
            SettingsLink { Text("设置…") }
            Divider()
            Button("退出 Blinker") { NSApp.terminate(nil) }
        }

        Settings {
            SettingsScreen(ruleStore: appDelegate.ruleStore)
        }
    }
}
