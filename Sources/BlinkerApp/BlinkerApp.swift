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
            // Width floor for the rules tab's three columns, calibrated
            // on-screen after the split-view migration: with no explicit
            // floor the system opens at 900×450 and the grouped Form's
            // system insets clip the green-light column. 980 (the old
            // manual floor) and 1110 still clip or squeeze the sidebars
            // below their column minima; 1208×492 is the first size where
            // the green column renders complete with every column label
            // readable (verified by screenshot at a clean layout state).
            .frame(minWidth: 1208, minHeight: 492)
        }
        // The floor above becomes the window's minimum size.
        .windowResizability(.contentMinSize)
    }
}
