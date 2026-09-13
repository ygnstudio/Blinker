/// Resolves which action a traffic button click should perform for a given app.
///
/// The engine is a pure lookup: applications without a matching enabled rule
/// fall through to the system default behavior.
public struct RuleEngine: Sendable {
    private let rulesProvider: @Sendable () -> [AppRule]

    /// - Parameter rulesProvider: Supplies the current rule list on demand,
    ///   so the engine always sees the latest configuration without caching.
    public init(rulesProvider: @escaping @Sendable () -> [AppRule]) {
        self.rulesProvider = rulesProvider
    }

    /// Cheap check used to discard clicks from apps without any enabled rule.
    public func hasRule(forBundleIdentifier bundleIdentifier: String) -> Bool {
        rulesProvider().contains { $0.bundleIdentifier == bundleIdentifier && $0.isEnabled }
    }

    /// Returns the remapped action for a button click of the given variant,
    /// or `nil` to pass the click through to the system.
    public func action(
        forBundleIdentifier bundleIdentifier: String,
        button: TrafficButton,
        variant: ClickVariant = .left
    ) -> ButtonAction? {
        guard
            let rule = rulesProvider().first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.isEnabled
            })
        else { return nil }

        return rule.action(for: button, variant: variant)
    }
}
