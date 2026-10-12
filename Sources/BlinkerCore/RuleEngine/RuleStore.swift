import Combine
import Foundation

/// Main-thread mutations publish and persist one complete configuration transaction.
/// The event thread obtains that same rules/defaults pair under one lock.
public final class RuleStore: ObservableObject {
    public enum WriteIssue: LocalizedError, Equatable {
        case unsupportedVersion(Int)
        case invalidConfiguration
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                String(localized: "规则由更新版本保存，当前只读；请使用兼容版本，原文件不会被覆盖。", bundle: .module)
            case .invalidConfiguration:
                String(localized: "规则配置无效，原配置未更改。", bundle: .module)
            case .encodingFailed:
                String(localized: "无法保存规则配置，原配置未更改。", bundle: .module)
            }
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var storage: RuleConfiguration
    private var undoHistory: [RuleConfiguration] = []
    private var redoHistory: [RuleConfiguration] = []
    @Published public private(set) var configuration: RuleConfiguration
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false
    @Published public private(set) var isReadOnly: Bool
    @Published public private(set) var writeIssue: WriteIssue?

    public var rules: [AppRule] { configuration.rules }
    public var globalDefaults: GlobalButtonRules { configuration.globalDefaults }

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.rules",
        profileArchiveKey: String = "com.ygnstudio.blinker.ruleProfiles"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        let loaded = RuleStorePersistence.load(defaults: defaults, key: storageKey,
                                               profileArchiveKey: profileArchiveKey)
        storage = loaded.configuration
        configuration = loaded.configuration
        isReadOnly = loaded.futureVersion != nil
        writeIssue = loaded.futureVersion.map(WriteIssue.unsupportedVersion)
    }

    public var configurationSnapshot: RuleConfiguration {
        lock.withLock { storage }
    }

    /// Compatibility accessor. New engines/exporters must use configurationSnapshot.
    public var snapshot: [AppRule] { configurationSnapshot.rules }

    public func upsert(_ rule: AppRule) {
        var updated = configurationSnapshot
        if let index = updated.rules.firstIndex(where: { $0.id == rule.id }) {
            updated.rules[index] = rule
        } else {
            updated.rules.append(rule)
        }
        commit(updated)
    }

    /// Removing an exception returns this application to the global button defaults.
    public func remove(bundleIdentifier: String) {
        var updated = configurationSnapshot
        updated.rules.removeAll { $0.id == bundleIdentifier }
        commit(updated)
    }

    public func setEnabled(_ isEnabled: Bool, bundleIdentifier: String) {
        guard var rule = snapshot.first(where: { $0.id == bundleIdentifier }) else { return }
        rule.isEnabled = isEnabled
        upsert(rule)
    }

    @discardableResult
    public func updateGlobalDefaults(_ globalDefaults: GlobalButtonRules) -> Bool {
        var updated = configurationSnapshot
        updated.globalDefaults = globalDefaults
        return commit(updated)
    }

    /// Existing reset deliberately means explicit system actions, never implicit inheritance.
    public func reset(bundleIdentifier: String) {
        guard let rule = snapshot.first(where: { $0.id == bundleIdentifier }) else { return }
        var reset = AppRule(bundleIdentifier: rule.id, displayName: rule.displayName)
        reset.isHoverEnabled = rule.isHoverEnabled
        upsert(reset)
    }

    public func merge(_ imported: [AppRule]) {
        merge(RuleTransfer.Document(rules: imported))
    }

    /// Rules plus any supplied global defaults are a single undoable import.
    @discardableResult
    public func merge(_ imported: RuleTransfer.Document) -> Bool {
        guard RuleTransfer.validRules(imported.rules) else {
            writeIssue = .invalidConfiguration
            return false
        }
        var updated = configurationSnapshot
        var indices = Dictionary(uniqueKeysWithValues: updated.rules.enumerated().map {
            ($0.element.id, $0.offset)
        })
        for rule in imported.rules {
            if let index = indices[rule.id] {
                updated.rules[index] = rule
            } else {
                indices[rule.id] = updated.rules.count
                updated.rules.append(rule)
            }
        }
        if let globalDefaults = imported.globalDefaults { updated.globalDefaults = globalDefaults }
        return commit(updated)
    }

    @discardableResult
    public func replaceConfiguration(_ configuration: RuleConfiguration) -> Bool {
        commit(configuration)
    }

    public func undo() {
        assert(Thread.isMainThread)
        guard let previous = undoHistory.last, preparePersistence(previous) else { return }
        undoHistory.removeLast()
        redoHistory.append(configurationSnapshot)
        publish(previous)
    }

    public func redo() {
        assert(Thread.isMainThread)
        guard let next = redoHistory.last, preparePersistence(next) else { return }
        redoHistory.removeLast()
        undoHistory.append(configurationSnapshot)
        publish(next)
    }

    @discardableResult
    private func commit(_ updated: RuleConfiguration) -> Bool {
        assert(Thread.isMainThread)
        guard writable() else { return false }
        guard RuleTransfer.validRules(updated.rules) else {
            writeIssue = .invalidConfiguration
            return false
        }
        guard updated != configurationSnapshot else {
            writeIssue = nil
            return false
        }
        guard preparePersistence(updated) else { return false }
        undoHistory.append(configurationSnapshot)
        undoHistory = Array(undoHistory.suffix(50))
        redoHistory = []
        publish(updated)
        return true
    }

    /// Encode before committing memory/history. UserDefaults receives a single versioned value.
    private func preparePersistence(_ updated: RuleConfiguration) -> Bool {
        guard writable() else { return false }
        do {
            let data = try JSONEncoder().encode(RuleConfigurationArchive(updated))
            defaults.set(data, forKey: storageKey)
            return true
        } catch {
            writeIssue = .encodingFailed
            return false
        }
    }

    /// Re-check before exporting so an externally written future version is
    /// never replaced by an export of this process's older in-memory snapshot.
    /// This only refreshes protection state; it does not modify persisted data.
    public func refreshPersistenceStatus() {
        assert(Thread.isMainThread)
        _ = writable()
    }

    private func writable() -> Bool {
        if let data = defaults.data(forKey: storageKey),
           let version = RuleStorePersistence.futureVersion(in: data) {
            isReadOnly = true
            canUndo = false
            canRedo = false
            writeIssue = .unsupportedVersion(version)
        }
        return !isReadOnly
    }

    private func publish(_ updated: RuleConfiguration) {
        lock.withLock { storage = updated }
        configuration = updated
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
        writeIssue = nil
    }
}

/// Legacy profile format remains a migration source, never a new persistence target.
struct ProfileArchive: Codable, Equatable, Sendable {
    var profiles: [RuleProfile]
    var activeProfileID: UUID
}
