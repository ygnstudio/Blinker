import Foundation

/// Shared handoff between AX detection and main-thread rendering. Rebuilding
/// views does not cancel pending work; explicit hides invalidate older passes.
final class OverlayPresentationState {
    struct Pending {
        let presentation: OverlayPresentation
        let revision: UInt64
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var pending: Pending?
    private var scheduled = false
    private var displayed: OverlayLayout?

    var revision: UInt64 {
        lock.withLock { generation }
    }

    func isCurrent(_ revision: UInt64) -> Bool {
        lock.withLock { generation == revision }
    }

    func submit(_ presentation: OverlayPresentation, revision: UInt64) -> Bool {
        lock.withLock {
            guard generation == revision else { return false }
            pending = Pending(presentation: presentation, revision: revision)
            let needsDrain = !scheduled
            scheduled = true
            return needsDrain
        }
    }

    func takePending() -> Pending? {
        lock.withLock {
            defer { pending = nil; scheduled = false }
            return pending
        }
    }

    @discardableResult
    func publish(_ layout: OverlayLayout, revision: UInt64) -> Bool {
        lock.withLock {
            guard generation == revision else { return false }
            displayed = layout
            return true
        }
    }

    func displayedLayout(at point: CGPoint) -> OverlayLayout? {
        lock.withLock {
            guard let displayed,
                  let frame = HoverOverlayTrayPanel.frame(forDisplayFrames: displayed.allPanelFrames),
                  frame.contains(point) else { return nil }
            return displayed
        }
    }

    func shouldRemoveViews(revision: UInt64) -> Bool {
        lock.withLock { generation == revision && displayed == nil }
    }

    @discardableResult
    func invalidate() -> UInt64 {
        lock.withLock {
            generation &+= 1
            pending = nil
            displayed = nil
            // A previously scheduled main-queue drain still exists. It can
            // deliver a new submission made before that drain executes.
            return generation
        }
    }
}
