import AppKit

/// SF Symbol name for each extra-button action; `nil` actions are never
/// rendered so `.none` needs no symbol. Public so the settings preview can
/// render the same chips the overlay draws.
public extension ButtonAction {
    var extraSymbolName: String? {
        switch self {
        case .closeWindow: "xmark"
        case .quitApp: "power"
        case .minimize: "minus"
        case .hideApp: "eye.slash"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .almostMaximize: "rectangle.inset.filled"
        case .fullscreen: "arrow.up.backward.and.arrow.down.forward"
        case .tileLeft: "rectangle.lefthalf.inset.filled"
        case .tileRight: "rectangle.righthalf.inset.filled"
        case .tileTop: "rectangle.tophalf.inset.filled"
        case .tileBottom: "rectangle.bottomhalf.inset.filled"
        case .tileTopLeft: "rectangle.topleftthird.inset.filled"
        case .tileTopRight: "rectangle.toprightthird.inset.filled"
        case .tileBottomLeft: "rectangle.bottomleftthird.inset.filled"
        case .tileBottomRight: "rectangle.bottomrightthird.inset.filled"
        case .centerWindow: "rectangle.center.inset.filled"
        case .moveToNextDisplay: "display.2"
        case .none: nil
        case .windowManagerPanel: "rectangle.grid.3x3"
        }
    }
}
