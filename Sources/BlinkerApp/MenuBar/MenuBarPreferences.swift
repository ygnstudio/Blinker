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
    enum Section: String, Codable, CaseIterable { case battery, network, volume }

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
    var replacesNetworkWithBluetooth = false
    var usesBluetoothVolumeColor = false
    var prioritizesNetworkErrors = true
    var bluetoothSymbolScale: Double = 1.6
    var refreshInterval: Double = 15
    var leftClick: ClickAction = .panel
    var sectionOrder: [Section] = Section.allCases
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

    var showsMenuBar: Bool {
        placement != .dock
    }

    var showsDock: Bool {
        placement != .menuBar
    }

    var visibleSections: [Section] {
        sectionOrder.filter { enabledSections.contains($0) }
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
        var seen = Set<Section>()
        value.sectionOrder = (sectionOrder + Section.allCases).filter { seen.insert($0).inserted }
        var devices = Set<String>()
        value.outputDeviceOrder = outputDeviceOrder.filter { !$0.isEmpty && devices.insert($0).inserted }
            .prefix(100).map { $0 }
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
