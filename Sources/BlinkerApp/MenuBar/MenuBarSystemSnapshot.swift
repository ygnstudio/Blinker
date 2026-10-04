import Foundation

/// Only the local values needed by the three-in-one menu bar icon.
/// Unknown readings remain unknown rather than displaying a healthy default.
struct MenuBarSystemSnapshot: Equatable, Sendable {
    struct Battery: Equatable, Sendable {
        var percentage: Int?
        var isCharging: Bool
        var isConnectedToPower: Bool
        var isLowPower: Bool
    }

    enum Network: Equatable, Sendable {
        case unknown
        case off
        case disconnected
        case wifi(strength: Int)
        case wired
    }

    struct Volume: Equatable, Sendable {
        var scalar: Double?
        var isMuted: Bool
        var isBluetooth: Bool = false
        var symbolName: String?
    }

    /// nil also covers desktop Macs without an internal battery.
    var battery: Battery?
    var network: Network
    var volume: Volume?

    static let unknown = Self(battery: nil, network: .unknown, volume: nil)
}
