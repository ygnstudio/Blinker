/// A per-application remapping of the traffic light buttons.
///
/// `closeAction` maps the red button, `zoomAction` maps the green button.
/// A `nil` action means "keep the system default behavior" for that button.
public struct AppRule: Identifiable, Codable, Hashable, Sendable {
    public var id: String {
        bundleIdentifier
    }

    /// The target application's bundle identifier, e.g. `com.apple.Safari`.
    public let bundleIdentifier: String
    /// Human-readable application name shown in the settings UI.
    public var displayName: String
    /// Remapping for the red (close) button. `nil` keeps the default.
    public var closeAction: ButtonAction?
    /// Remapping for the green (zoom) button. `nil` keeps the default.
    public var zoomAction: ButtonAction?
    /// Disabled rules are ignored by the engine but kept in storage.
    public var isEnabled: Bool

    public init(
        bundleIdentifier: String,
        displayName: String,
        closeAction: ButtonAction? = nil,
        zoomAction: ButtonAction? = nil,
        isEnabled: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.closeAction = closeAction
        self.zoomAction = zoomAction
        self.isEnabled = isEnabled
    }
}
