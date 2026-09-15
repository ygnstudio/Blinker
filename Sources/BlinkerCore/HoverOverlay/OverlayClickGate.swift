import Foundation

/// Short-lived suppression gate shared by the hover overlay and the click
/// interceptor.
///
/// When a click is consumed by an overlay panel, the interceptor's event tap
/// still observes the raw event first (taps sit at the HID level, before
/// window routing). The gate makes the interceptor pass such a click through
/// so the mapped action can never execute twice.
public enum OverlayClickGate {
    private static let lock = NSLock()
    private static var suppressedUntil: TimeInterval = 0

    /// How long clicks stay suppressed after an overlay panel consumes one.
    /// Derived from the long-press threshold so raising the threshold can
    /// never let a late mouse-up escape the protection window — keep the
    /// margin if the threshold changes.
    public static let suppressionMilliseconds: Int =
        Int(TrafficLightInterceptor.longPressThreshold * 1000) + 200

    /// Suppresses intercepted clicks for the given duration in milliseconds.
    public static func suppressFor(milliseconds: Int) {
        lock.withLock {
            suppressedUntil = Date().timeIntervalSince1970 + Double(milliseconds) / 1000
        }
    }

    /// `true` while the interceptor must let clicks pass through.
    public static var isSuppressed: Bool {
        lock.withLock {
            Date().timeIntervalSince1970 < suppressedUntil
        }
    }

    /// Clears any pending suppression (used by tests).
    public static func reset() {
        lock.withLock { suppressedUntil = 0 }
    }
}
