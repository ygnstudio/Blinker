import Combine
import Foundation

/// Persists named rule profiles in `UserDefaults` and publishes changes.
///
/// A profile is a complete, named rule table (see `RuleProfile`); exactly
/// one is active. Every mutation API inherited from the single-table days —
/// `upsert`, `remove`, `setEnabled`, `snapshot`, `rules` — operates on the
/// active profile, so the rule engine and the event-tap layer are unaware
/// that profiles exist.
///
/// Thread safety: mutations are expected on the main thread (settings UI);
/// `snapshot` is guarded by a lock because the interceptor reads it from the
/// event tap thread. The lock only guards the internal `storage` array —
/// the `@Published` properties are assigned *outside* the lock, so Combine
/// subscribers reading them synchronously can never deadlock on it.
public final class RuleStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey: String
    /// Legacy single-table key, read once for migration.
    private let legacyKey: String
    private let defaultProfileName: String
    private let lock = NSLock()

    /// Internal source of truth; every access is guarded by `lock`.
    private var storage: [RuleProfile] = []
    private var activeID: UUID?

    /// Rules of the active profile; published for SwiftUI observation and
    /// read on the main thread only.
    @Published public private(set) var rules: [AppRule] = []

    /// All profiles, oldest first; published for the switcher UI.
    @Published public private(set) var profiles: [RuleProfile] = []

    /// Identifier of the active profile.
    @Published public private(set) var activeProfileID: UUID?

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.ruleProfiles",
        legacyKey: String = "com.ygnstudio.blinker.rules",
        defaultProfileName: String = "默认"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.legacyKey = legacyKey
        self.defaultProfileName = defaultProfileName

        let loaded = Self.load(
            defaults: defaults,
            key: storageKey,
            legacyKey: legacyKey,
            defaultProfileName: defaultProfileName
        )
        storage = loaded.profiles
        activeID = loaded.activeID
        profiles = storage
        activeProfileID = activeID
        rules = activeProfile?.rules ?? []
    }

    // MARK: - Active profile access

    private var activeProfile: RuleProfile? {
        // Caller holds `lock` or runs before publication; main-thread UI
        // reads go through `activeProfileID` + `profiles` instead.
        storage.first { $0.id == activeID }
    }

    /// The active profile, for display purposes.
    public var activeProfileName: String {
        lock.withLock { activeProfile?.name } ?? defaultProfileName
    }

    /// Thread-safe copy of the active profile's rules for the rule engine.
    public var snapshot: [AppRule] {
        lock.withLock { activeProfile?.rules ?? [] }
    }

    // MARK: - Rule mutations (active profile only)

    public func upsert(_ rule: AppRule) {
        mutateActive { $0.rules.upsert(rule) }
    }

    public func remove(bundleIdentifier: String) {
        mutateActive { profile in
            profile.rules.removeAll { $0.bundleIdentifier == bundleIdentifier }
        }
    }

    public func setEnabled(_ isEnabled: Bool, bundleIdentifier: String) {
        mutateActive { profile in
            guard let index = profile.rules.firstIndex(where: {
                $0.bundleIdentifier == bundleIdentifier
            }) else { return }
            profile.rules[index].isEnabled = isEnabled
        }
    }

    // MARK: - Profile management

    /// Creates an empty profile and switches to it.
    public func createProfile(named name: String) {
        mutateProfiles {
            let profile = RuleProfile(name: name)
            storage.append(profile)
            activeID = profile.id
        }
    }

    /// Duplicates `id` (or the active profile when `id` is `nil`) under a
    /// "- 副本" suffixed name and switches to the copy.
    public func duplicateProfile(id: UUID? = nil) {
        mutateProfiles {
            guard let source = storage.first(where: { $0.id == (id ?? activeID) }) else { return }
            let copy = RuleProfile(name: source.name + " - 副本", rules: source.rules)
            storage.append(copy)
            activeID = copy.id
        }
    }

    public func renameProfile(id: UUID, to name: String) {
        mutateProfiles {
            guard let index = storage.firstIndex(where: { $0.id == id }) else { return }
            storage[index].name = name
        }
    }

    /// Deletes a profile and switches to its nearest neighbor. The last
    /// remaining profile cannot be deleted.
    public func deleteProfile(id: UUID) {
        mutateProfiles {
            guard storage.count > 1,
                  let index = storage.firstIndex(where: { $0.id == id })
            else { return }
            storage.remove(at: index)
            if activeID == id {
                activeID = storage[max(0, index - 1)].id
            }
        }
    }

    /// Switches the active profile; the engine picks up the new table on the
    /// next click through `snapshot`.
    public func switchProfile(to id: UUID) {
        mutateProfiles {
            guard storage.contains(where: { $0.id == id }) else { return }
            activeID = id
        }
    }

    // MARK: - Mutation plumbing

    /// Applies `transform` to the active profile under the lock, then
    /// republishes and persists. `transform` must only touch `profile.rules`
    /// — profile identity is owned by the profile-level APIs.
    private func mutateActive(_ transform: (inout RuleProfile) -> Void) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        var updatedRules: [AppRule] = []
        lock.withLock {
            guard let index = storage.firstIndex(where: { $0.id == activeID }) else { return }
            transform(&storage[index])
            updatedRules = storage[index].rules
        }
        rules = updatedRules
        persist()
    }

    /// Applies `transform` to the whole profile list under the lock, then
    /// republishes everything and persists.
    private func mutateProfiles(_ transform: () -> Void) {
        assert(Thread.isMainThread, "RuleStore mutations must happen on the main thread")
        var updatedProfiles: [RuleProfile] = []
        var updatedActiveID: UUID?
        var updatedRules: [AppRule] = []
        lock.withLock {
            transform()
            // Never allow an empty list or a dangling active pointer.
            if storage.isEmpty {
                storage = [RuleProfile(name: defaultProfileName)]
            }
            if activeID == nil || !storage.contains(where: { $0.id == activeID }) {
                activeID = storage[0].id
            }
            updatedProfiles = storage
            updatedActiveID = activeID
            updatedRules = activeProfile?.rules ?? []
        }
        profiles = updatedProfiles
        activeProfileID = updatedActiveID
        rules = updatedRules
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let profilesCopy: [RuleProfile] = lock.withLock { storage }
        guard let activeIDCopy: UUID = lock.withLock({ activeID }) else { return }
        let archive = ProfileArchive(profiles: profilesCopy, activeProfileID: activeIDCopy)
        if let data = try? JSONEncoder().encode(archive) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// Loads the profile archive; falls back to migrating the legacy
    /// single-table blob into one default-named profile.
    private static func load(
        defaults: UserDefaults,
        key: String,
        legacyKey: String,
        defaultProfileName: String
    ) -> (profiles: [RuleProfile], activeID: UUID?) {
        guard
            let data = defaults.data(forKey: key),
            let archive = try? JSONDecoder().decode(ProfileArchive.self, from: data),
            !archive.profiles.isEmpty
        else {
            // Migration: wrap whatever the old format held into one profile.
            let legacyRules: [AppRule] = if let data = defaults.data(forKey: legacyKey) {
                (try? JSONDecoder().decode([AppRule].self, from: data)) ?? []
            } else {
                []
            }
            let profile = RuleProfile(name: defaultProfileName, rules: legacyRules)
            return ([profile], profile.id)
        }
        return (archive.profiles, archive.activeProfileID)
    }
}

// MARK: - Rule list helper

private extension [AppRule] {
    mutating func upsert(_ rule: AppRule) {
        if let index = firstIndex(where: { $0.bundleIdentifier == rule.bundleIdentifier }) {
            self[index] = rule
        } else {
            append(rule)
        }
    }
}
