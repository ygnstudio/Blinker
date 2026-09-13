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
    /// Tile the window to the top half of the screen.
    case tileTop
    /// Tile the window to the bottom half of the screen.
    case tileBottom
    /// Tile the window to the top-left quarter of the screen.
    case tileTopLeft
    /// Tile the window to the top-right quarter of the screen.
    case tileTopRight
    /// Tile the window to the bottom-left quarter of the screen.
    case tileBottomLeft
    /// Tile the window to the bottom-right quarter of the screen.
    case tileBottomRight
    /// Center the window on its screen, keeping its current size.
    case centerWindow
    /// Zoom the window to nearly fill the screen, leaving a breathing margin.
    case almostMaximize
    /// Move the window to the next display, keeping its size.
    case moveToNextDisplay
    /// Swallow the click and do nothing.
    case none
    /// Overlay-only: opens the window-management HUD (placement grid +
    /// workspace restore) anchored to the enlarged traffic lights. Not
    /// offered in rule pickers; acts on the hovered window, never the
    /// frontmost one.
    case windowManagerPanel
}
