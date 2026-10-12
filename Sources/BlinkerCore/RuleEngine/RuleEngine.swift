/// Resolves stored bindings against one atomic configuration snapshot per lookup.
public struct RuleEngine: Sendable {
    private let isAppPaused: @Sendable (String) -> Bool
    private let configurationProvider: @Sendable () -> RuleConfiguration

    /// Compatibility entry point: an old array provider has system-only global defaults.
    public init(
        isAppPaused: @escaping @Sendable (String) -> Bool = { _ in false },
        rulesProvider: @escaping @Sendable () -> [AppRule]
    ) {
        self.init(isAppPaused: isAppPaused, configurationProvider: {
            RuleConfiguration(rules: rulesProvider())
        })
    }

    public init(
        isAppPaused: @escaping @Sendable (String) -> Bool = { _ in false },
        configurationProvider: @escaping @Sendable () -> RuleConfiguration
    ) {
        self.isAppPaused = isAppPaused
        self.configurationProvider = configurationProvider
    }

    /// Includes unlisted applications only when a global action actually requires interception.
    public func hasRule(forBundleIdentifier bundleIdentifier: String) -> Bool {
        guard !isAppPaused(bundleIdentifier) else { return false }
        let configuration = configurationProvider()
        if let rule = configuration.rules.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return rule.isEnabled
        }
        return configuration.globalDefaults.hasConfiguredActions
    }

    /// Global button defaults never widen the configured application's hover scope.
    public func allowsHover(for bundleIdentifier: String, allWindows: Bool) -> Bool {
        guard !isAppPaused(bundleIdentifier) else { return false }
        let rule = configurationProvider().rules.first { $0.bundleIdentifier == bundleIdentifier }
        return (rule?.isHoverEnabled ?? true) && (allWindows || rule != nil)
    }

    /// nil passes through; ButtonAction.none is a configured intercepted no-op.
    public func action(
        forBundleIdentifier bundleIdentifier: String,
        button: TrafficButton,
        variant: ClickVariant = .left
    ) -> ButtonAction? {
        guard !isAppPaused(bundleIdentifier) else { return nil }
        let configuration = configurationProvider()
        guard let rule = configuration.rules.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return configuration.globalDefaults.action(for: button, variant: variant)
        }
        // A disabled exception suppresses defaults too, rather than falling through to a global action.
        guard rule.isEnabled else { return nil }
        switch rule.binding(for: button, variant: variant) {
        case .inherit: return configuration.globalDefaults.action(for: button, variant: variant)
        case .system: return nil
        case let .action(action): return action
        }
    }
}
