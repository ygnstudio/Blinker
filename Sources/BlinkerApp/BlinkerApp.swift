import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The real settings window is a plain NSWindow created and owned by
        // the app delegate (see `openSettings()`); this placeholder only
        // satisfies the Scene requirement.
        Settings { EmptyView() }
    }
}
