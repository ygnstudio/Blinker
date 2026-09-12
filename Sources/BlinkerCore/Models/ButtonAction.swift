/// An action a traffic button can be remapped to.
///
/// A rule stores `nil` for a button to keep the system default behavior.
public enum ButtonAction: String, Codable, CaseIterable, Sendable {
    /// Close the clicked window (native red-button behavior).
    case closeWindow
    /// Terminate the whole application (normal quit, preserves save prompts).
    case quitApp
    /// Minimize the clicked window.
    case minimize
    /// Hide the application.
    case hideApp
    /// Zoom the window to fill the screen without entering fullscreen.
    case maximize
    /// Toggle native fullscreen.
    case fullscreen
    /// Tile the window to the left half of the screen.
    case tileLeft
    /// Tile the window to the right half of the screen.
    case tileRight
    /// Swallow the click and do nothing.
    case none
}
