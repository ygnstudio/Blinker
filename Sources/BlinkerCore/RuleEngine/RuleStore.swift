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
    /// Archive key written by the (since removed) profile-era build; read
    /// once for migration.
    private let profileArchiveKey: String
    private let lock = NSLock()

    /// Internal source of truth; every access is guarded by `lock`.
    private var storage: [AppRule] = []

    /// Published for SwiftUI observation; read on the main thread only.
    @Published public private(set) var rules: [AppRule] = []

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.rules",
        profileArchiveKey: String = "com.ygnstudio.blinker.ruleProfiles"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.profileArchiveKey = profileArchiveKey
        storage = Self.load(
            defaults: defaults,
            key: storageKey,
            profileArchiveKey: profileArchiveKey
        )
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
        storeEncoded(current, forKey: storageKey, in: defaults, category: "rules")
    }

    /// Loads the flat rule table. A build briefly stored rules as named
    /// profiles; unwrap that archive's active profile so no configuration
    /// was lost, then fall back to the plain blob. An undecodable blob is
    /// quarantined under a backup key before starting empty, so the next
    /// save cannot silently erase the remains.
    private static func load(
        defaults: UserDefaults,
        key: String,
        profileArchiveKey: String
    ) -> [AppRule] {
        let data = defaults.data(forKey: key)
        if let rules = data.flatMap({ try? JSONDecoder().decode([AppRule].self, from: $0) }) {
            return rules
        }
        let archiveData = defaults.data(forKey: profileArchiveKey)
        let archive = archiveData.flatMap { try? JSONDecoder().decode(ProfileArchive.self, from: $0) }
        if let active = archive?.profiles.first(where: { $0.id == archive?.activeProfileID }) {
            return active.rules
        }
        if let data {
            quarantineCorruptBlob(data, forKey: key, in: defaults, category: "rules")
        }
        return []
    }
}

/// The persisted archive format of the removed profile-era RuleStore: every
/// named profile plus which one was active. Kept only as a migration source.
struct ProfileArchive: Codable, Equatable, Sendable {
    var profiles: [RuleProfile]
    var activeProfileID: UUID
}
