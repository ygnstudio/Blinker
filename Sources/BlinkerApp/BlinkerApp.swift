import AppKit

/// AppKit owns application/window lifetime; SwiftUI owns each window's content.
/// No placeholder scene or hidden launch window is needed for a menu-bar utility.
@main
enum BlinkerApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
