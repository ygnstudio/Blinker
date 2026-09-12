import BlinkerCore
import AppKit
import SwiftUI

/// Owns the long-lived app state: the rule store and the event interceptor.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let ruleStore = RuleStore()

    private var interceptor: TrafficLightInterceptor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.prompt()
            return
        }
        startInterceptor()
    }

    /// Starts (or restarts, e.g. after the permission was granted) interception.
    func startInterceptor() {
        guard AccessibilityPermission.isTrusted else { return }
        let engine = RuleEngine { [weak ruleStore] in ruleStore?.snapshot ?? [] }
        let interceptor = TrafficLightInterceptor(ruleEngine: engine)
        guard interceptor.start() else { return }
        self.interceptor = interceptor
    }
}
