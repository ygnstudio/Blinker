import AppKit

/// Performs window actions on the frontmost application's focused window.
///
/// Shared entry point for every mouse-free action path — the window
/// management tab's instant panel and the global hotkeys. Requires the
/// Accessibility permission but nothing else, so it works even while click
/// interception is paused.
public final class FrontWindowActionPerformer {
    private let performer: WindowActionPerforming
    /// Serial queue for the AX work: hotkeys fire on the main thread and the
    /// focused-window query is synchronous IPC (capped at the shared 250 ms
    /// messaging timeout) that must not stall the UI.
    private let workQueue = DispatchQueue(
        label: "com.ygnstudio.blinker.front-window",
        qos: .userInitiated
    )

    public init(performer: WindowActionPerforming) {
        self.performer = performer
    }

    /// Queues `action` for the frontmost app's focused window. The frontmost
    /// app is captured synchronously (it would be stale by the time the
    /// queued work runs); the focused-window lookup and the action itself
    /// run on the serial work queue.
    ///
    /// - Returns: `false` when there is no frontmost app to act on. A
    ///   missing focused AX window is discovered on the work queue and
    ///   simply results in no action.
    @discardableResult
    public func perform(_ action: ButtonAction) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        workQueue.async { [performer] in
            guard
                let window = AXQuery.focusedWindowElement(processIdentifier: app.processIdentifier)
            else { return }
            performer.perform(
                action,
                button: .close,
                window: window,
                processIdentifier: app.processIdentifier
            )
        }
        return true
    }
}
