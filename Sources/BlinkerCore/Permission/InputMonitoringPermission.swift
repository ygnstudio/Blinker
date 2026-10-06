import CoreGraphics

/// Checks and prompts for Input Monitoring, which the keyboard-lock event tap
/// needs to receive keyboard events at all (Accessibility alone only lets the
/// tap suppress them). Mirrors `AccessibilityPermission`.
public enum InputMonitoringPermission {
    /// Whether the app may currently receive keyboard events via an event tap.
    public static var isGranted: Bool {
        CGPreflightListenEventAccess()
    }

    /// Shows the system prompt offering to grant Input Monitoring. The grant
    /// can require an app relaunch before preflight reports it.
    @discardableResult
    public static func request() -> Bool {
        CGRequestListenEventAccess()
    }
}
