import Foundation

/// Temporary per-app exclusions. No preferences are overwritten when pausing.
public final class SessionPause: @unchecked Sendable {
    public static let shared = SessionPause()
    private let lock = NSLock()
    private var apps: Set<String> = []

    public init() {}

    public func contains(_ bundleID: String) -> Bool {
        lock.withLock { apps.contains(bundleID) }
    }

    public func toggle(_ bundleID: String) {
        lock.withLock {
            if !apps.insert(bundleID).inserted {
                apps.remove(bundleID)
            }
        }
    }

    public func clear() {
        lock.withLock { apps.removeAll() }
    }
}
