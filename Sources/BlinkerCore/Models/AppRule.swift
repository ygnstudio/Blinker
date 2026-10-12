/// A per-application remapping of the traffic light buttons.
///
/// Each action maps one button; a `nil` action means "keep the system
/// default behavior" for that button. The plain left click is stored in the
/// three legacy per-button fields; the enhanced click variants (right,
/// modifier clicks, long press) live in `extraVariantActions`, keyed by
/// button and then by variant.
public struct AppRule: Identifiable, Codable, Hashable, Sendable {
    public var id: String {
        bundleIdentifier
    }

    /// The target application's bundle identifier, e.g. `com.apple.Safari`.
    public let bundleIdentifier: String
    /// Human-readable application name shown in the settings UI.
    public var displayName: String
    /// Remapping for a plain left click on the red (close) button.
    /// `nil` keeps the default.
    public var closeAction: ButtonAction?
    /// Remapping for a plain left click on the yellow (minimize) button.
    public var minimizeAction: ButtonAction?
    /// Remapping for a plain left click on the green (zoom) button.
    public var zoomAction: ButtonAction?
    /// Actions for the enhanced click variants, keyed by button and then by
    /// variant (never `.left`, which the legacy fields above own).
    public var extraVariantActions: [TrafficButton: [ClickVariant: ButtonAction?]]
    /// Disabled rules are ignored by the engine but kept in storage.
    public var isEnabled: Bool
    /// Hover is independent of button remapping.
    public var isHoverEnabled: Bool
    /// Only explicitly listed slots inherit. Legacy missing fields decode to an empty set.
    public var inheritedSlots: Set<RuleActionSlot>

    public init(
        bundleIdentifier: String,
        displayName: String,
        closeAction: ButtonAction? = nil,
        minimizeAction: ButtonAction? = nil,
        zoomAction: ButtonAction? = nil,
        extraVariantActions: [TrafficButton: [ClickVariant: ButtonAction?]] = [:],
        isEnabled: Bool = true,
        isHoverEnabled: Bool = true,
        inheritedSlots: Set<RuleActionSlot> = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.closeAction = closeAction
        self.minimizeAction = minimizeAction
        self.zoomAction = zoomAction
        self.extraVariantActions = extraVariantActions
        self.isEnabled = isEnabled
        self.isHoverEnabled = isHoverEnabled
        self.inheritedSlots = inheritedSlots
    }

    /// Use for newly created exceptions. The ordinary initializer preserves legacy system semantics.
    public static func inheritingDefaults(bundleIdentifier: String, displayName: String) -> Self {
        Self(bundleIdentifier: bundleIdentifier, displayName: displayName, inheritedSlots: RuleActionSlot.all)
    }

    public func binding(for button: TrafficButton, variant: ClickVariant = .left) -> RuleActionBinding {
        if inheritedSlots.contains(RuleActionSlot(button: button, variant: variant)) {
            return .inherit
        }
        return action(for: button, variant: variant).map(RuleActionBinding.action) ?? .system
    }

    public mutating func setBinding(_ binding: RuleActionBinding, button: TrafficButton,
                                    variant: ClickVariant = .left) {
        switch binding {
        case .inherit:
            setAction(nil, button: button, variant: variant)
            inheritedSlots.insert(RuleActionSlot(button: button, variant: variant))
        case .system:
            setAction(nil, button: button, variant: variant)
        case let .action(action):
            setAction(action, button: button, variant: variant)
        }
    }

    // MARK: - Lookup

    /// The action configured for `button` under `variant`; `nil` keeps the
    /// system default behavior.
    public func action(for button: TrafficButton, variant: ClickVariant) -> ButtonAction? {
        guard variant != .left else {
            return legacyAction(for: button)
        }
        return extraVariantActions[button]?[variant] ?? nil
    }

    /// Whether any enhanced variant slot carries an action for this rule.
    public var hasExtraVariantActions: Bool {
        extraVariantActions.values.contains { !$0.isEmpty }
    }

    /// Stores `action` for `button` under `variant`. The plain left click is
    /// routed to the legacy per-button fields; `nil` restores the default.
    public mutating func setAction(
        _ action: ButtonAction?,
        button: TrafficButton,
        variant: ClickVariant
    ) {
        inheritedSlots.remove(RuleActionSlot(button: button, variant: variant))
        if variant == .left {
            switch button {
            case .close: closeAction = action
            case .minimize: minimizeAction = action
            case .zoom: zoomAction = action
            }
            return
        }
        var slots = extraVariantActions[button] ?? [:]
        slots[variant] = action
        extraVariantActions[button] = slots
    }

    private func legacyAction(for button: TrafficButton) -> ButtonAction? {
        switch button {
        case .close: closeAction
        case .minimize: minimizeAction
        case .zoom: zoomAction
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, displayName
        case closeAction, minimizeAction, zoomAction
        case extraVariantActions, isEnabled, isHoverEnabled, inheritedSlots
    }

    /// Custom decoding so rules persisted by versions without
    /// `extraVariantActions` still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        closeAction = try container.decodeIfPresent(ButtonAction.self, forKey: .closeAction)
        minimizeAction = try container.decodeIfPresent(ButtonAction.self, forKey: .minimizeAction)
        zoomAction = try container.decodeIfPresent(ButtonAction.self, forKey: .zoomAction)
        extraVariantActions = try container
            .decodeIfPresent(
                [TrafficButton: [ClickVariant: ButtonAction?]].self,
                forKey: .extraVariantActions
            ) ?? [:]
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isHoverEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHoverEnabled) ?? true
        inheritedSlots = try container
            .decodeIfPresent(Set<RuleActionSlot>.self, forKey: .inheritedSlots) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(closeAction, forKey: .closeAction)
        try container.encodeIfPresent(minimizeAction, forKey: .minimizeAction)
        try container.encodeIfPresent(zoomAction, forKey: .zoomAction)
        try container.encode(extraVariantActions, forKey: .extraVariantActions)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isHoverEnabled, forKey: .isHoverEnabled)
        if !inheritedSlots.isEmpty {
            try container.encode(inheritedSlots, forKey: .inheritedSlots)
        }
    }

}
