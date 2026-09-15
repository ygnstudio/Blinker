import BlinkerCore
import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsScreen(
                ruleStore: appDelegate.ruleStore,
                hoverSettingsStore: appDelegate.hoverOverlaySettingsStore,
                onApplyHoverSettings: appDelegate.applyHoverOverlaySettings,
                hotkeyManager: appDelegate.hotkeyManager,
                workspaceStore: appDelegate.workspaceStore,
                onSnapEnabledChange: appDelegate.applySnapEnabled,
                appDelegate: appDelegate
            )
        }
    }
}
