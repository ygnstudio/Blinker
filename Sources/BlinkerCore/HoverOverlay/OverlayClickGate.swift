import AppKit
import CoreGraphics
import Foundation

/// Short-lived suppression gate shared by the hover overlay and the click
/// interceptor.
///
/// When a click is consumed by an overlay panel, the interceptor's event tap
/// still observes the raw event first (taps sit at the HID level, before
/// window routing). The gate makes the interceptor pass such a click through
/// so the mapped action can never execute twice.
///
/// Suppression is scoped to the consumed click's location: a global window
/// would also disarm remapping for a fast second click anywhere else on
/// screen (e.g. another window's traffic lights).
public enum OverlayClickGate {
    private static let lock = NSLock()
    private static var suppressedUntil: TimeInterval = 0
    /// Where the consumed click happened, in CG (top-left origin) global
    /// coordinates; `nil` means the suppression is global.
    private static var suppressedLocation: CGPoint?

    /// Radius (pt) around the consumed click within which the interceptor
    /// stands down — comfortably covers one enlarged chip.
    public static let suppressionRadius: CGFloat = 24

    /// How long clicks stay suppressed after an overlay panel consumes one.
    /// Derived from the long-press threshold so raising the threshold can
    /// never let a late mouse-up escape the protection window — keep the
    /// margin if the threshold changes.
    public static let suppressionMilliseconds: Int =
        Int(TrafficLightInterceptor.longPressThreshold * 1000) + 200

    /// Suppresses intercepted clicks for the given duration in milliseconds,
    /// scoped to `location` (CG global coordinates). Omitting the location
    /// keeps the suppression global.
    public static func suppressFor(milliseconds: Int, at location: CGPoint? = nil) {
        lock.withLock {
            suppressedUntil = Date().timeIntervalSince1970 + Double(milliseconds) / 1000
            suppressedLocation = location
        }
    }

    /// `true` while the interceptor must let clicks pass through, regardless
    /// of location.
    public static var isSuppressed: Bool {
        lock.withLock {
            Date().timeIntervalSince1970 < suppressedUntil
        }
    }

    /// `true` while the interceptor must let a click at `location` (CG
    /// global coordinates) pass through: within the suppression window and
    /// near the consumed click (or globally, when no location was recorded).
    public static func isSuppressed(at location: CGPoint) -> Bool {
        lock.withLock {
            guard Date().timeIntervalSince1970 < suppressedUntil else { return false }
            guard let suppressedLocation else { return true }
            let deltaX = location.x - suppressedLocation.x
            let deltaY = location.y - suppressedLocation.y
            return deltaX * deltaX + deltaY * deltaY <= suppressionRadius * suppressionRadius
        }
    }

    /// Suppresses near the current mouse position — the AppKit global point
    /// is converted into the CG (top-left origin) global coordinates the
    /// interceptor's events live in. Called from overlay panel mouse
    /// handlers, where the cursor sits on the consumed click.
    public static func suppressAtMouseLocation(forMilliseconds milliseconds: Int) {
        let appKitLocation = NSEvent.mouseLocation
        let cgLocation = CGPoint(
            x: appKitLocation.x,
            y: AXQuery.coordinatePivotY - appKitLocation.y
        )
        suppressFor(milliseconds: milliseconds, at: cgLocation)
    }

    /// Clears any pending suppression (used by tests).
    public static func reset() {
        lock.withLock {
            suppressedUntil = 0
            suppressedLocation = nil
        }
    }
}
