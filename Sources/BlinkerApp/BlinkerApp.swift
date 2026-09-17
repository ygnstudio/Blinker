import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SettingsPlaceholderScene()
    }
}

/// Placeholder scene that only satisfies SwiftUI's `Scene` requirement.
///
/// The real settings window is a plain `NSWindow` created and owned by the
/// app delegate (see `openSettings()`); this scene renders nothing.
///
/// Do NOT swap this for a suppressed `Window` scene: on macOS 26 a `Window`
/// with `.defaultLaunchBehavior(.suppressed)` stalls the SwiftUI launch so
/// `applicationDidFinishLaunching` never fires — no menu bar item, no
/// interceptor, nothing (verified 2026-09-16: zero subsystem log entries
/// after launch).
private struct SettingsPlaceholderScene: Scene {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
