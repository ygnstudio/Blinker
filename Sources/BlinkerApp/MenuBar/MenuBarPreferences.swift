import Combine
import Foundation

/// Options shared by the real icon, its previews and the status panel.
struct MenuBarConfiguration: Codable, Equatable {
    enum Placement: String, Codable, CaseIterable { case menuBar, dock, both }
    enum DockBackground: String, Codable, CaseIterable { case system, light, dark, transparent }
    enum Stroke: String, Codable, CaseIterable {
        case light, regular, bold
        var scale: Double {
            switch self {
            case .light: 1
            case .regular: 1.25
            case .bold: 1.5
            }
        }
    }

    enum VolumeStyle: String, Codable, CaseIterable { case dots, arc }
    enum ClickAction: String, Codable, CaseIterable { case panel, rules }
    enum ScrollScope: String, Codable, CaseIterable { case panel, volumeControl }
    enum ScrollDirection: String, Codable, CaseIterable { case upward = "up", down }
    enum Section: String, Codable, CaseIterable {
        case battery, network, volume, bluetooth, quickActions, storage, performance
    }

    /// The status page's orderable blocks. Quick actions is a separate panel
    /// page: it is enabled or hidden, never reordered.
    static let statusSections: [Section] = [
        .battery, .network, .volume, .bluetooth, .storage, .performance,
    ]
    enum PanelDensity: String, Codable, CaseIterable { case comfortable, compact }

    var placement: Placement = .menuBar
    var dockBackground: DockBackground = .system
    var iconSize: Double = 20
    var stroke: Stroke = .regular
    var showsBatteryPercentage = true
    var showsChargingIndicator = true
    var showsPercentageWhenConnected = false
    var usesBatteryColors = true
    var batteryCriticalThreshold: Double = 20
    var batterySymbolScale: Double = 1
    var showsChargingEffect = true
    var showsChargingHeartbeat = true
    var wifiSymbolScale: Double = 1.6
    var showsWiFiForWired = false
    var showsWiFiForHotspot = false
    var showsWiFiForTemporary = false
    var showsWiFiForSharing = false
    var showsBatteryInCenter = false
    var volumeStyle: VolumeStyle = .dots
    /// Status icon: while the default input is muted, the volume readout
    /// becomes an orange mic-slash badge at the icon's bottom center.
    var showsMutedMicInIcon = true
    var replacesNetworkWithBluetooth = false
    var usesBluetoothVolumeColor = false
    var prioritizesNetworkErrors = true
    var bluetoothSymbolScale: Double = 1.6
    var refreshInterval: Double = 15
    var leftClick: ClickAction = .panel
    var sectionOrder: [Section] = statusSections
    var enabledSections: Set<Section> = Set(Section.allCases)
    var scrollAdjustsVolume = true
    var scrollScope: ScrollScope = .panel
    var scrollDirection: ScrollDirection = .upward
    var naturalScrolling = false
    var outputDeviceLimit = 5
    var alwaysShowsAllOutputDevices = false
    var outputDeviceOrder: [String] = []
    /// Panel network block: VPN/proxy row. Read-only probe, no permission.
    var showsVPNStatus = true
    /// Panel network block: Wi-Fi name row. Needs Location Services to un-redact
    /// the SSID, so it defaults off and the panel guides the grant in place.
    var showsWiFiName = false
    /// Panel volume block: default input device row with level and mute.
    var showsAudioInput = true
    /// Panel bluetooth block: per-device list management. Keys are addresses.
    var bluetoothDeviceLimit = 5
    var alwaysShowsAllBluetoothDevices = false
    var bluetoothDeviceOrder: [String] = []
    var hiddenBluetoothDevices: Set<String> = []
    /// Inquiry residue without a pairing record clutters the list; System
    /// Settings never shows it either, so the panel hides it by default.
    var hidesUnpairedBluetoothDevices = true
    /// Nearby BLE battery scan (A4). Default off: it carries the Bluetooth
    /// authorization prompt and periodic radio use.
    var scansNearbyBluetoothDevices = false
    /// Panel battery block: cycle count, health, temperature and power rows
    /// from the battery controller; unavailable fields simply stay hidden.
    var showsBatteryDetails = true
    /// Panel network block: averaged up/down throughput row.
    var showsNetworkActivity = true
    /// Panel network block: the machine's own IPv4 address row. Local only.
    var showsLocalIPAddress = true
    /// Panel network block: external address from a lookup endpoint. This is
    /// the only outbound request the panel can make, so it defaults off and
    /// settings name the endpoint.
    var showsPublicIPAddress = false
    /// Panel bluetooth block: signal-strength subtitles from the system
    /// report, when a measurement exists. No permission required.
    var showsBluetoothSignalStrength = true
    /// Panel bluetooth block: codec subtitles and per-device disconnect via
    /// IOBluetooth, which is gated by the same Bluetooth privacy grant as
    /// the nearby scan. Default off; enabling requests the grant in context.
    var enablesBluetoothDeviceControl = false
    /// Section spacing and padding in the status panel.
    var panelDensity: PanelDensity = .comfortable
    /// Quick actions section: microphone mute row for the default input.
    var showsQuickActionMicMute = true
    /// Quick actions section: display cleaning overlay entry.
    var showsQuickActionDisplayCleaning = true
    /// Quick actions section: keyboard cleaning overlay entry.
    var showsQuickActionKeyboardCleaning = true
    /// Quick actions section: empty-trash row for the boot volume's trash.
    var showsQuickActionEmptyTrash = true
    /// User-named Shortcut slots run from the panel. Blinker does not know
    /// what a shortcut does; 0...3 names, matched against the Shortcuts app.
    var shortcutSlots: [String] = []
    /// Panel storage block: the boot volume's capacity row.
    var showsInternalStorage = true
    /// Panel storage block: mounted external volumes with an eject action.
    var showsExternalVolumes = true
    /// Panel performance block: CPU load averaged over the refresh interval.
    var showsCPULoad = true
    /// Panel performance block: memory used vs. total.
    var showsMemoryUsage = true
    /// Panel performance block: swap in use.
    var showsSwapUsage = true
    /// Panel performance block: time since boot. Off by default — steady
    /// uptime is trivia for most, one toggle away for the curious.
    var showsUptime = false

    var showsMenuBar: Bool {
        placement != .dock
    }

    var showsDock: Bool {
        placement != .menuBar
    }

    /// Status page blocks in order; the quick actions page is not listed here.
    var visibleSections: [Section] {
        sectionOrder.filter { $0 != .quickActions && enabledSections.contains($0) }
    }

    func normalized() -> Self {
        var value = self
        func clamp(_ input: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            input.isFinite ? min(range.upperBound, max(range.lowerBound, input)) : fallback
        }
        value.iconSize = clamp(iconSize, 16 ... 36, fallback: 20)
        value.batteryCriticalThreshold = clamp(batteryCriticalThreshold, 0 ... 100, fallback: 20)
        value.batterySymbolScale = clamp(batterySymbolScale, 0.5 ... 2, fallback: 1)
        value.wifiSymbolScale = clamp(wifiSymbolScale, 1 ... 1.8, fallback: 1.6)
        value.bluetoothSymbolScale = clamp(bluetoothSymbolScale, 1 ... 1.8, fallback: 1.6)
        value.refreshInterval = clamp(refreshInterval, 5 ... 60, fallback: 15)
        value.outputDeviceLimit = min(20, max(1, outputDeviceLimit))
        value.bluetoothDeviceLimit = min(20, max(1, bluetoothDeviceLimit))
        var seen = Set<Section>()
        value.sectionOrder = (sectionOrder + Self.statusSections).filter {
            $0 != .quickActions && seen.insert($0).inserted
        }
        var devices = Set<String>()
        value.outputDeviceOrder = outputDeviceOrder.filter { !$0.isEmpty && devices.insert($0).inserted }
            .prefix(100).map { $0 }
        var addresses = Set<String>()
        value.bluetoothDeviceOrder = bluetoothDeviceOrder
            .filter { !$0.isEmpty && addresses.insert($0).inserted }
            .prefix(100).map { $0 }
        value.hiddenBluetoothDevices = Set(hiddenBluetoothDevices.filter { !$0.isEmpty }.prefix(100))
        var slots = Set<String>()
        value.shortcutSlots = shortcutSlots
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)) }
            .filter { !$0.isEmpty && slots.insert($0).inserted }
            .prefix(3).map { $0 }
        return value
    }
}

@MainActor
final class MenuBarPreferences: ObservableObject {
    static let shared = MenuBarPreferences()
    static let key = "menuBarConfiguration.v1"
    @Published private(set) var configuration: MenuBarConfiguration
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuration = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(MenuBarConfiguration.self, from: $0) }?
            .normalized() ?? MenuBarConfiguration()
    }

    func update(_ change: (inout MenuBarConfiguration) -> Void) {
        var value = configuration
        change(&value)
        value = value.normalized()
        guard value != configuration else { return }
        configuration = value
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func reset() {
        update { $0 = MenuBarConfiguration() }
    }
}
