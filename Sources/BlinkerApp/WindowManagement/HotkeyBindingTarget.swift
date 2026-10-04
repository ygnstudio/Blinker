import BlinkerCore

extension HotkeyManager {
    /// Shared identity for recording, conflict feedback and Carbon registration.
    enum BindingTarget: Equatable {
        case windowAction(ButtonAction)
        case hoverToggle
        case desktopToggle

        var registrationKey: String {
            switch self {
            case let .windowAction(action): action.rawValue
            case .hoverToggle: "hoverToggle"
            case .desktopToggle: "desktopToggle"
            }
        }

        /// Command IDs stay outside the window-action table's index + 1 range.
        var hotKeyID: UInt32 {
            switch self {
            case let .windowAction(action):
                UInt32(HotkeyManager.bindableActions.firstIndex(of: action)?.advanced(by: 1) ?? 0)
            case .hoverToggle: 0x484F // 'HO'
            case .desktopToggle: 0x4454 // 'DT'
            }
        }
    }
}
