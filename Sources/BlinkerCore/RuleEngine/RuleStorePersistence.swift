import Foundation

/// Migration never overwrites the original blob until a valid explicit edit is committed.
enum RuleStorePersistence {
    struct Loaded {
        let configuration: RuleConfiguration
        let futureVersion: Int?
    }

    private struct VersionHeader: Decodable {
        let version: Int
    }

    static func futureVersion(in data: Data) -> Int? {
        guard let header = try? JSONDecoder().decode(VersionHeader.self, from: data),
              header.version > RuleConfigurationArchive.currentVersion else { return nil }
        return header.version
    }

    static func load(defaults: UserDefaults, key: String, profileArchiveKey: String) -> Loaded {
        let data = defaults.data(forKey: key)
        if let data {
            // Do not fall back to an obsolete profile, quarantine or write over a newer store.
            if let version = futureVersion(in: data) {
                return Loaded(configuration: RuleConfiguration(), futureVersion: version)
            }
            if let document = try? RuleTransfer.decodeStoredConfiguration(data) {
                if document.globalDefaults == nil { backup(data, key: key, defaults: defaults) }
                return Loaded(configuration: RuleConfiguration(
                    rules: document.rules, globalDefaults: document.globalDefaults ?? GlobalButtonRules()
                ), futureVersion: nil)
            }
            if let rules = try? JSONDecoder().decode([AppRule].self, from: data),
               RuleTransfer.validRules(rules), rules.allSatisfy({ $0.inheritedSlots.isEmpty }) {
                backup(data, key: key, defaults: defaults)
                return Loaded(configuration: RuleConfiguration(rules: rules), futureVersion: nil)
            }
            quarantineCorruptBlob(data, forKey: key, in: defaults, category: "rules")
        }
        if let archiveData = defaults.data(forKey: profileArchiveKey),
           let archive = try? JSONDecoder().decode(ProfileArchive.self, from: archiveData),
           let active = archive.profiles.first(where: { $0.id == archive.activeProfileID }),
           RuleTransfer.validRules(active.rules), active.rules.allSatisfy({ $0.inheritedSlots.isEmpty }) {
            backup(archiveData, key: profileArchiveKey, defaults: defaults)
            return Loaded(configuration: RuleConfiguration(rules: active.rules), futureVersion: nil)
        }
        return Loaded(configuration: RuleConfiguration(), futureVersion: nil)
    }

    private static func backup(_ data: Data, key: String, defaults: UserDefaults) {
        let backupKey = key + ".legacy-backup"
        if defaults.data(forKey: backupKey) == nil { defaults.set(data, forKey: backupKey) }
    }
}
