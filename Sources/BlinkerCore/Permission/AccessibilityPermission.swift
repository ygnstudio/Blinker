import ApplicationServices

/// Checks and prompts for the Accessibility permission Blinker requires.
public enum AccessibilityPermission {
    /// Whether the app currently has Accessibility permission.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system dialog offering to open System Settings.
    public static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
