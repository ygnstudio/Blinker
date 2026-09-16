import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The native settings scene: the system owns the window (sizing,
        // state restoration, appearance, ⌘,), while the menu bar item and
        // the status-menu entry open it via `openSettings()` — the scene's
        // standard `showSettingsWindow:` action.
        Settings {
            SettingsView(
                ruleStore: appDelegate.ruleStore,
                hoverSettingsStore: appDelegate.hoverOverlaySettingsStore,
                onApplyHoverSettings: appDelegate.applyHoverOverlaySettings,
                hotkeyManager: appDelegate.hotkeyManager,
                workspaceStore: appDelegate.workspaceStore,
                onSnapEnabledChange: appDelegate.applySnapEnabled,
                appDelegate: appDelegate
            )
        }
        // The floor is carried by the content: the splitview column minima
        // plus the matrix's own minimum width (see RulesTab/ActionPicker).
        .windowResizability(.contentMinSize)
    }
}
