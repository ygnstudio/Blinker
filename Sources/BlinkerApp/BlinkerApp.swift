import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The real settings window is a plain NSWindow created and owned by
        // the app delegate (see `openSettings()`). The old placeholder was a
        // `Settings` scene, which the system instantiated into a real
        // 500×500 empty window that could surface at any time; a suppressed
        // `Window` scene satisfies the Scene requirement without ever
        // showing.
        Window("Blinker", id: "placeholder") {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }
}
