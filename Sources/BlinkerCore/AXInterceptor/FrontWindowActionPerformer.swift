import AppKit

/// Performs window actions on the frontmost application's focused window.
///
/// Shared entry point for every mouse-free action path — the window
/// management tab's instant panel and the global hotkeys. Requires the
/// Accessibility permission but nothing else, so it works even while click
/// interception is paused.
public final class FrontWindowActionPerformer {
    private let performer: WindowActionPerforming

    public init(performer: WindowActionPerforming) {
        self.performer = performer
    }

    /// - Returns: `false` when there is no frontmost app or no focused AX
    ///   window to act on.
    @discardableResult
    public func perform(_ action: ButtonAction) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AXQuery.focusedWindowElement(processIdentifier: app.processIdentifier)
        else { return false }
        performer.perform(
            action,
            button: .close,
            window: window,
            processIdentifier: app.processIdentifier
        )
        return true
    }
}
