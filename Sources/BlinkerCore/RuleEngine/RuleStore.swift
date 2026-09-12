import Combine
import Foundation

/// Persists app rules in `UserDefaults` and publishes changes to the UI.
///
/// Thread safety: mutations are expected on the main thread (settings UI);
/// `snapshot` is guarded by a lock because the interceptor reads it from the
/// event tap thread.
public final class RuleStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    /// Published for SwiftUI observation; read via `snapshot` off the main thread.
    @Published public private(set) var rules: [AppRule] = []

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.rules"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        rules = Self.load(defaults: defaults, key: storageKey)
    }

    /// Thread-safe copy of the current rules for the rule engine.
    public var snapshot: [AppRule] {
        lock.withLock { rules }
    }

    public func upsert(_ rule: AppRule) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        lock.withLock {
            if let index = rules.firstIndex(where: { $0.bundleIdentifier == rule.bundleIdentifier }) {
                rules[index] = rule
            } else {
                rules.append(rule)
            }
        }
        persist()
    }

    public func remove(bundleIdentifier: String) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        lock.withLock {
            rules.removeAll { $0.bundleIdentifier == bundleIdentifier }
        }
        persist()
    }

    public func setEnabled(_ isEnabled: Bool, bundleIdentifier: String) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        lock.withLock {
            guard
                let index = rules.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier })
            else { return }
            rules[index].isEnabled = isEnabled
        }
        persist()
    }

    private func persist() {
        lock.withLock {
            if let data = try? JSONEncoder().encode(rules) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> [AppRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AppRule].self, from: data)) ?? []
    }
}
