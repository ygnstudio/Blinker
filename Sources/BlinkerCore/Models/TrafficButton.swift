/// A window control button in a macOS title bar (close / minimize / zoom).
public enum TrafficButton: String, Codable, CaseIterable, Sendable {
    /// The red button. Native behavior closes the window.
    case close
    /// The yellow button. Native behavior minimizes the window.
    case minimize
    /// The green button. Native behavior toggles fullscreen.
    case zoom
}
