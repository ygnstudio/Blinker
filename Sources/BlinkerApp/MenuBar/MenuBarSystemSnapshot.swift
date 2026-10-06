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

    /// Averaged interface throughput since the previous read.
    struct NetworkActivity: Equatable, Sendable {
        var downBytesPerSecond: Double
        var upBytesPerSecond: Double
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
    /// Cycle count, health, temperature and power; nil unless opted in and
    /// the machine has a battery controller.
    var batteryDetails: SystemBatteryDetails.Value?
    /// Throughput averaged over the last refresh interval; nil until two
    /// samples exist or while the row is disabled.
    var networkActivity: NetworkActivity?
    /// First active IPv4 address on a physical interface.
    var localIPAddress: String?
    /// External address as seen by the lookup endpoint; opt-in, fetched
    /// asynchronously with a TTL cache.
    var publicIPAddress: String?
    /// Boot volume capacity and mounted external volumes; nil while the
    /// storage section is hidden.
    var storage: SystemStorageInfo.Value?
    /// CPU load, memory, swap and uptime; nil while the performance
    /// section is hidden.
    var performance: SystemPerformance.Value?
    /// Top-level entries in the user's trash; nil while the quick actions
    /// page or its trash row is hidden.
    var trashItemCount: Int?
    /// Default input device mute for the status icon's mic indicator; nil
    /// while the indicator is disabled.
    var inputMuted: Bool?

    static let unknown = Self(battery: nil, network: .unknown, volume: nil)

    init(battery: Battery?, network: Network, volume: Volume?,
         wifiName: String? = nil, vpn: VPN? = nil,
         bluetoothDevices: [BluetoothDevice]? = nil,
         batteryDetails: SystemBatteryDetails.Value? = nil,
         networkActivity: NetworkActivity? = nil,
         localIPAddress: String? = nil, publicIPAddress: String? = nil,
         storage: SystemStorageInfo.Value? = nil,
         performance: SystemPerformance.Value? = nil,
         trashItemCount: Int? = nil, inputMuted: Bool? = nil) {
        self.battery = battery
        self.network = network
        self.volume = volume
        self.wifiName = wifiName
        self.vpn = vpn
        self.bluetoothDevices = bluetoothDevices
        self.batteryDetails = batteryDetails
        self.networkActivity = networkActivity
        self.localIPAddress = localIPAddress
        self.publicIPAddress = publicIPAddress
        self.storage = storage
        self.performance = performance
        self.trashItemCount = trashItemCount
        self.inputMuted = inputMuted
    }
}
