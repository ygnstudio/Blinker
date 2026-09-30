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
    private var undoHistory: [[AppRule]] = []
    private var redoHistory: [[AppRule]] = []
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

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
        var updated = snapshot
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            updated[index] = rule
        } else {
            updated.append(rule)
        }
        commit(updated)
    }

    public func remove(bundleIdentifier: String) {
        commit(snapshot.filter { $0.id != bundleIdentifier })
    }

    public func setEnabled(_ isEnabled: Bool, bundleIdentifier: String) {
        guard var rule = snapshot.first(where: { $0.id == bundleIdentifier }) else { return }
        rule.isEnabled = isEnabled
        upsert(rule)
    }

    /// Import merges by application ID; the entire import is one undoable edit.
    public func merge(_ imported: [AppRule]) {
        var updated = snapshot
        var indices = Dictionary(uniqueKeysWithValues: updated.enumerated().map {
            ($0.element.id, $0.offset)
        })
        for rule in imported {
            if let index = indices[rule.id] {
                updated[index] = rule
            } else {
                indices[rule.id] = updated.count
                updated.append(rule)
            }
        }
        commit(updated)
    }

    public func reset(bundleIdentifier: String) {
        guard let rule = snapshot.first(where: { $0.id == bundleIdentifier }) else { return }
        upsert(AppRule(bundleIdentifier: rule.id, displayName: rule.displayName))
    }

    public func undo() {
        assert(Thread.isMainThread)
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(snapshot)
        publish(previous)
    }

    public func redo() {
        assert(Thread.isMainThread)
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(snapshot)
        publish(next)
    }

    private func commit(_ updated: [AppRule]) {
        assert(Thread.isMainThread)
        guard updated != snapshot else { return }
        undoHistory.append(snapshot)
        undoHistory = Array(undoHistory.suffix(50))
        redoHistory = []
        publish(updated)
    }

    private func publish(_ updated: [AppRule]) {
        lock.withLock { storage = updated }
        rules = updated
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
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
        if let data,
           let rules = try? JSONDecoder().decode([AppRule].self, from: data),
           RuleTransfer.validRules(rules) {
            return rules
        }
        let archiveData = defaults.data(forKey: profileArchiveKey)
        let archive = archiveData.flatMap { try? JSONDecoder().decode(ProfileArchive.self, from: $0) }
        if let active = archive?.profiles.first(where: { $0.id == archive?.activeProfileID }),
           RuleTransfer.validRules(active.rules) {
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
