import CoreGraphics
import Foundation

/// One intercepted left-button sequence. The event tap owns synchronization;
/// these transitions only inspect the original AX bounds and Quartz points.
struct TrafficLightPressState {
    struct Pending {
        let id = UUID()
        let bounds: CGRect
        let windowHit: AXQuery.WindowHit
        let shortAction: ButtonAction?
        let longAction: ButtonAction
        var didFireLong = false
    }

    struct Invocation {
        let action: ButtonAction
        let windowHit: AXQuery.WindowHit
    }

    struct Release {
        let swallowed: Bool
        let invocation: Invocation?
    }

    private(set) var pending: Pending?
    private var swallowedDown = false
    private var tracksLongPress = false

    mutating func begin(_ pending: Pending?) {
        self.pending = pending
        swallowedDown = true
        tracksLongPress = pending != nil
    }

    mutating func drag(to point: CGPoint) -> Bool {
        guard tracksLongPress else { return false }
        if let pending, !pending.bounds.contains(point) {
            self.pending = nil
        }
        // Leaving cancels permanently, but down was already intercepted:
        // consume the rest of this gesture, including its eventual mouse-up.
        return true
    }

    mutating func release(at point: CGPoint) -> Release {
        let press = pending
        let swallowed = swallowedDown
        reset()
        guard let press, !press.didFireLong, press.bounds.contains(point),
              let action = press.shortAction else {
            return Release(swallowed: swallowed, invocation: nil)
        }
        return Release(swallowed: swallowed,
                       invocation: Invocation(action: action, windowHit: press.windowHit))
    }

    mutating func deadline(for id: UUID, at point: CGPoint?) -> Invocation? {
        // DispatchWorkItem cancellation can race its execution. An old timer
        // must neither trigger nor cancel the next physical press.
        guard let press = pending, press.id == id, !press.didFireLong else { return nil }
        guard let point, press.bounds.contains(point) else {
            pending = nil
            return nil
        }
        pending?.didFireLong = true
        return Invocation(action: press.longAction, windowHit: press.windowHit)
    }

    mutating func reset() {
        pending = nil
        swallowedDown = false
        tracksLongPress = false
    }
}
