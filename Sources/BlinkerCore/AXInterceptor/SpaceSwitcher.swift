import CoreGraphics

/// Switches macOS desktops (Spaces) by synthesizing the system's ⌃← / ⌃→
/// shortcut. This rides on whatever the user's Mission Control shortcuts
/// are set to, so it degrades gracefully rather than crash — and it inherits
/// the Accessibility permission the app already requires.
public enum SpaceSwitcher {
    public enum Direction: String, Sendable {
        case previous
        case next

        /// `kVK_LeftArrow` / `kVK_RightArrow`.
        var keyCode: CGKeyCode {
            switch self {
            case .previous: 123
            case .next: 124
            }
        }
    }

    /// Posts a full key-down/key-up pair with the ⌃ modifier held.
    public static func switchDesktop(_ direction: Direction) {
        guard let keyDownEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: direction.keyCode,
            keyDown: true
        ), let keyUpEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: direction.keyCode,
            keyDown: false
        ) else { return }
        keyDownEvent.flags = .maskControl
        keyUpEvent.flags = .maskControl
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }
}
