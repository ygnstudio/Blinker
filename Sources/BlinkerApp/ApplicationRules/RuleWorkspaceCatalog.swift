import BlinkerCore
import Foundation

struct RuleWorkspaceApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String?
    let hasRule: Bool
}

/// Discovery does not mutate persisted rules. Selection is independent of filtering.
enum RuleWorkspaceCatalog {
    static func applications(installed: [InstalledApp], rules: [AppRule]) -> [RuleWorkspaceApplication] {
        var result = Dictionary(uniqueKeysWithValues: installed.map {
            ($0.id, RuleWorkspaceApplication(id: $0.id, name: $0.name, path: $0.path, hasRule: false))
        })
        for rule in rules {
            result[rule.id] = RuleWorkspaceApplication(
                id: rule.id, name: rule.displayName, path: result[rule.id]?.path, hasRule: true
            )
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func filtered(_ apps: [RuleWorkspaceApplication], query: String,
                         onlyConfigured: Bool) -> [RuleWorkspaceApplication] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter {
            (!onlyConfigured || $0.hasRule) && (query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query))
        }
    }

    static func selection(_ selected: String?, in apps: [RuleWorkspaceApplication]) -> String? {
        if let selected, apps.contains(where: { $0.id == selected }) { return selected }
        return apps.first(where: \.hasRule)?.id ?? apps.first?.id
    }
}
