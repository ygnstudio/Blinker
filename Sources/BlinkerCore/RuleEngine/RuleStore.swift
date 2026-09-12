import Combine
import Foundation

/// Persists app rules in `UserDefaults` and publishes changes to the UI.
///
/// Thread safety: mutations are expected on the main thread (settings UI);
/// `snapshot` is guarded by a lock because the interceptor reads it from the
/// event tap thread. The lock only guards the internal `storage` array —
/// the `@Published` property is assigned *outside* the lock, so Combine
/// subscribers reading `rules` synchronously can never deadlock on it.
public final class RuleStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    /// Internal source of truth; every access is guarded by `lock`.
    private var storage: [AppRule] = []

    /// Published for SwiftUI observation; read on the main thread only.
    @Published public private(set) var rules: [AppRule] = []

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.rules"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        storage = Self.load(defaults: defaults, key: storageKey)
        rules = storage
    }

    /// Thread-safe copy of the current rules for the rule engine.
    public var snapshot: [AppRule] {
        lock.withLock { storage }
    }

    public func upsert(_ rule: AppRule) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        var updated: [AppRule] = []
        lock.withLock {
            var copy = storage
            if let index = copy.firstIndex(where: { $0.bundleIdentifier == rule.bundleIdentifier }) {
                copy[index] = rule
            } else {
                copy.append(rule)
            }
            storage = copy
            updated = copy
        }
        rules = updated
        persist(updated)
    }

    public func remove(bundleIdentifier: String) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        var updated: [AppRule] = []
        lock.withLock {
            let copy = storage.filter { $0.bundleIdentifier != bundleIdentifier }
            storage = copy
            updated = copy
        }
        rules = updated
        persist(updated)
    }

    public func setEnabled(_ isEnabled: Bool, bundleIdentifier: String) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        var updated: [AppRule] = []
        lock.withLock {
            var copy = storage
            if let index = copy.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
                copy[index].isEnabled = isEnabled
            }
            storage = copy
            updated = copy
        }
        rules = updated
        persist(updated)
    }

    private func persist(_ current: [AppRule]) {
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> [AppRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AppRule].self, from: data)) ?? []
    }
}
