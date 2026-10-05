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
        /// Expensive Wi-Fi path, the personal-hotspot heuristic.
        case personalHotspot(strength: Int)
        /// Ad-hoc (IBSS) Wi-Fi.
        case temporary
        /// This Mac shares its connection (Internet Sharing NAT active).
        case sharing
    }

    struct Volume: Equatable, Sendable {
        var scalar: Double?
        var isMuted: Bool
        var isBluetooth: Bool = false
        var symbolName: String?
    }

    /// VPN/proxy presence for the panel row. nil when nothing is active.
    struct VPN: Equatable, Sendable {
        /// Active tunnel interface names (`utun4`, `ppp0`, …), sorted.
        var tunnels: [String] = []
        /// Name of the connected system VPN service, when one is up.
        var serviceName: String?
        /// Active system-wide proxy endpoint (`host:port`), when configured.
        var proxyEndpoint: String?

        var isTunnelConnected: Bool {
            !tunnels.isEmpty || serviceName != nil
        }

        var isActive: Bool {
            isTunnelConnected || proxyEndpoint != nil
        }
    }

    /// nil also covers desktop Macs without an internal battery.
    var battery: Battery?
    var network: Network
    var volume: Volume?
    /// Current Wi-Fi network name; nil unless authorized and connected.
    var wifiName: String?
    /// Active VPN/proxy; nil when there is nothing to report.
    var vpn: VPN?
    /// Paired Bluetooth devices for the panel block. nil means the list was
    /// not read this cycle (section hidden) or has never been read
    /// successfully; an empty array means the machine has no paired devices.
    var bluetoothDevices: [BluetoothDevice]?

    static let unknown = Self(battery: nil, network: .unknown, volume: nil)

    init(battery: Battery?, network: Network, volume: Volume?,
         wifiName: String? = nil, vpn: VPN? = nil,
         bluetoothDevices: [BluetoothDevice]? = nil) {
        self.battery = battery
        self.network = network
        self.volume = volume
        self.wifiName = wifiName
        self.vpn = vpn
        self.bluetoothDevices = bluetoothDevices
    }
}
