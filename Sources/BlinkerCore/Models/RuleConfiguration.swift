import Foundation

/// A stored choice, distinct from the optional action produced by rule resolution.
public enum RuleActionBinding: Hashable, Sendable {
    case inherit
    case system
    case action(ButtonAction)
}

public struct RuleActionSlot: Codable, Hashable, Sendable {
    public let button: TrafficButton
    public let variant: ClickVariant

    public init(button: TrafficButton, variant: ClickVariant) {
        self.button = button
        self.variant = variant
    }

    public static var all: Set<Self> {
        Set(TrafficButton.allCases.flatMap { button in
            ClickVariant.allCases.map { Self(button: button, variant: $0) }
        })
    }
}

/// Global defaults have no parent: a missing action always means system behavior.
public struct GlobalButtonRules: Codable, Equatable, Sendable {
    public var actions: [TrafficButton: [ClickVariant: ButtonAction]]

    public init(actions: [TrafficButton: [ClickVariant: ButtonAction]] = [:]) {
        self.actions = actions
    }

    public var hasConfiguredActions: Bool {
        actions.values.contains { !$0.isEmpty }
    }

    public func action(for button: TrafficButton, variant: ClickVariant = .left) -> ButtonAction? {
        actions[button]?[variant]
    }

    public mutating func setAction(_ action: ButtonAction?, button: TrafficButton,
                                   variant: ClickVariant = .left) {
        var variants = actions[button] ?? [:]
        variants[variant] = action
        actions[button] = variants.isEmpty ? nil : variants
    }
}

/// One value is read by the event thread, persisted, imported and placed on undo history.
public struct RuleConfiguration: Codable, Equatable, Sendable {
    public var rules: [AppRule]
    public var globalDefaults: GlobalButtonRules

    public init(rules: [AppRule] = [], globalDefaults: GlobalButtonRules = GlobalButtonRules()) {
        self.rules = rules
        self.globalDefaults = globalDefaults
    }
}

/// Shared on-disk envelope. Version 1 has no defaults; version 2 requires them.
struct RuleConfigurationArchive: Codable {
    static let currentVersion = 2
    let version: Int
    let rules: [AppRule]
    let globalDefaults: GlobalButtonRules?

    init(_ configuration: RuleConfiguration) {
        version = Self.currentVersion
        rules = configuration.rules
        globalDefaults = configuration.globalDefaults
    }

    init(legacyRules: [AppRule]) {
        version = 1
        rules = legacyRules
        globalDefaults = nil
    }
}
