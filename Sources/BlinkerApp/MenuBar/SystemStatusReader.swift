// Monitoring design adapted from Status Trio, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: minimal local values; the Wi-Fi name is read only
// behind an explicit opt-in and a Location Services grant.
// See ThirdParty/StatusTrio for license and attribution.
import CoreWLAN
import Foundation
import IOKit.ps
import SystemConfiguration

@MainActor
final class SystemStatusReader: SystemStatusReading {
    var onChange: (@MainActor @Sendable () -> Void)?
    private let queue: DispatchQueue
    private let audio: SystemAudioStatusReader
    private let bluetooth = SystemBluetoothProfiler()
    private let networkSampler = NetworkThroughputSampler()
    private let performanceSampler = SystemPerformanceSampler()
    private let publicIP = PublicIPProbe()
    private let lifetime = SystemStatusReaderLifetime()

    init() {
        let queue = DispatchQueue(label: "Blinker.MenuBar.SystemRead", qos: .utility)
        self.queue = queue
        audio = SystemAudioStatusReader(queue: queue)
    }

    func read(
        path: SystemNetworkPath?,
        options: SystemStatusReadOptions,
        completion: @escaping @MainActor @Sendable (MenuBarSystemSnapshot) -> Void
    ) {
        let generation = lifetime.activate()
        let audio = audio
        let bluetooth = bluetooth
        let networkSampler = networkSampler
        let performanceSampler = performanceSampler
        let publicIP = publicIP
        let lifetime = lifetime
        let changed: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in self?.onChange?() }
        }
        queue.async {
            guard lifetime.isActive(generation) else {
                Task { @MainActor in completion(.unknown) }
                return
            }
            let battery = Self.readBattery()
            let network = Self.readNetwork(path: path)
            let vpn = options.includeVPN ? SystemVPNProbe.read() : nil
            var devices = options.includeBluetoothDevices ? bluetooth.readDevices() : nil
            if options.includeBluetoothDeviceControl, let listed = devices {
                devices = BluetoothConnectionDetails.attachingCodecs(to: listed)
            }
            let batteryDetails = options.includeBatteryDetails ? SystemBatteryDetails.read() : nil
            let additions = Self.readPanelAdditions(options: options, networkSampler: networkSampler,
                                                    performanceSampler: performanceSampler)
            let publicAddress: String? = options.includePublicIPAddress ? publicIP.cachedValue() : nil
            if options.includePublicIPAddress {
                publicIP.refreshIfNeeded(onChange: changed)
            }
            let volume = audio.read(onChange: changed)
            let inputMuted = options.includeInputMute ? audio.inputMuted() : nil
            let wifiName = options.includeWiFiName ? Self.readWiFiName(network: network) : nil
            // A stop during synchronous IPC cannot interrupt the system call.
            // Retire listeners before returning instead of starting another worker.
            if !lifetime.isActive(generation) {
                audio.stop()
            }
            let result = MenuBarSystemSnapshot(battery: battery, network: network, volume: volume,
                                               wifiName: wifiName,
                                               vpn: vpn,
                                               bluetoothDevices: devices,
                                               batteryDetails: batteryDetails,
                                               networkActivity: additions.networkActivity,
                                               localIPAddress: additions.localIPAddress,
                                               publicIPAddress: publicAddress,
                                               storage: additions.storage,
                                               performance: additions.performance,
                                               trashItemCount: additions.trashItemCount,
                                               inputMuted: inputMuted)
            Task { @MainActor in completion(result) }
        }
    }

    func stop() {
        guard lifetime.stopAndQueueCleanup() else { return }
        let audio = audio
        let lifetime = lifetime
        queue.async {
            audio.stop()
            lifetime.finishedCleanup()
        }
    }

    deinit {
        let audio = audio
        queue.async { audio.stop() }
    }

    /// Optional panel blocks with no system listener of their own. The
    /// network sampler is read exactly once per cycle: its throughput is a
    /// delta between reads, so a second call would corrupt the baseline.
    private nonisolated static func readPanelAdditions(
        options: SystemStatusReadOptions,
        networkSampler: NetworkThroughputSampler,
        performanceSampler: SystemPerformanceSampler
    ) -> SystemStatusPanelAdditions {
        let networkReading = networkSampler.read(
            includeActivity: options.includeNetworkActivity,
            includeAddress: options.includeLocalIPAddress
        )
        return SystemStatusPanelAdditions(
            storage: options.includeStorage ? SystemStorageInfo.read() : nil,
            performance: performanceSampler.read(include: options.includePerformance),
            trashItemCount: options.includeTrash ? SystemTrashInfo.itemCount() : nil,
            networkActivity: networkReading.activity,
            localIPAddress: networkReading.localIPv4
        )
    }

    private nonisolated static func readBattery() -> MenuBarSystemSnapshot.Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let value = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any],
                let battery = battery(from: value, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
            else { continue }
            return battery
        }
        return nil
    }

    nonisolated static func battery(from value: [String: Any], lowPower: Bool) -> MenuBarSystemSnapshot
        .Battery? {
        guard value[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              value[kIOPSIsPresentKey] as? Bool != false else { return nil }
        var percentage: Int?
        if let current = value[kIOPSCurrentCapacityKey] as? NSNumber,
           let maximum = value[kIOPSMaxCapacityKey] as? NSNumber,
           maximum.doubleValue > 0, current.doubleValue >= 0 {
            let ratio = current.doubleValue / maximum.doubleValue
            if ratio.isFinite {
                percentage = Int((min(1, max(0, ratio)) * 100).rounded())
            }
        }
        return .init(percentage: percentage,
                     isCharging: value[kIOPSIsChargingKey] as? Bool ?? false,
                     isConnectedToPower: value[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                     isLowPower: lowPower)
    }

    private nonisolated static func readNetwork(path: SystemNetworkPath?) -> MenuBarSystemSnapshot.Network {
        // A wired default route remains wired even if Wi-Fi is switched off.
        if path?.isSatisfied == true, path?.usesWired == true {
            return .wired
        }
        guard let interface = CWWiFiClient.shared().interface() else {
            return path?.isSatisfied == false ? .disconnected : .unknown
        }
        let powerOn = interface.powerOn()
        let associated = interface.serviceActive()
        // Sharing is only meaningful on an active Wi-Fi service, matching upstream.
        let sharing = powerOn && associated && Self.internetSharingActive()
        return network(path: path, powerOn: powerOn, associated: associated,
                       adHoc: interface.interfaceMode() == .IBSS,
                       rssi: interface.rssiValue(), sharing: sharing)
    }

    nonisolated static func network(path: SystemNetworkPath?, powerOn: Bool,
                                    associated: Bool, adHoc: Bool = false, rssi: Int?,
                                    sharing: Bool = false) -> MenuBarSystemSnapshot.Network {
        if let path, path.isSatisfied, path.usesWired {
            return .wired
        }
        guard powerOn else { return .off }
        guard let path else { return .unknown }
        guard path.isSatisfied else { return .disconnected }
        guard path.usesWiFi, associated else { return .unknown }
        return specialState(path: path, adHoc: adHoc, rssi: rssi, sharing: sharing)
    }

    /// Connection-type detail on a satisfied Wi-Fi path. Upstream priority:
    /// sharing, then ad-hoc, then the expensive-path hotspot.
    private nonisolated static func specialState(
        path: SystemNetworkPath, adHoc: Bool, rssi: Int?, sharing: Bool
    ) -> MenuBarSystemSnapshot.Network {
        if sharing { return .sharing }
        if adHoc { return .temporary }
        let strength = wifiStrength(rssi: rssi)
        return path.isExpensive ? .personalHotspot(strength: strength) : .wifi(strength: strength)
    }

    nonisolated static func wifiStrength(rssi: Int?) -> Int {
        switch rssi {
        case .some((-60) ... -1): 3
        case .some(-78 ... -61): 2
        case .some(-88 ... -79): 1
        default: 0
        }
    }

    /// The SSID is only read for Wi-Fi-family states where a name exists, and
    /// only after the monitor has confirmed location authorization. Reads the
    /// associated interface; never triggers a scan. Blank names normalize to nil.
    private nonisolated static func readWiFiName(
        network: MenuBarSystemSnapshot.Network
    ) -> String? {
        switch network {
        case .wifi, .personalHotspot, .temporary, .sharing:
            break
        case .unknown, .off, .disconnected, .wired:
            return nil
        }
        guard let raw = CWWiFiClient.shared().interface()?.ssid() else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Internet Sharing state from the dynamic store. The `com.apple.nat` key is
    /// undocumented, so a missing or unreadable value means not sharing.
    private nonisolated static func internetSharingActive() -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "Blinker" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "com.apple.nat" as CFString),
              let nat = (value as? [String: Any])?["NAT"] as? [String: Any]
        else { return false }
        switch nat["Enabled"] {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.intValue == 1
        default: return false
        }
    }
}

/// Optional panel readings bundled so the main read stays a flat list of
/// system sources. A nil field means its row is hidden and the read was
/// skipped this cycle.
struct SystemStatusPanelAdditions: Sendable {
    var storage: SystemStorageInfo.Value?
    var performance: SystemPerformance.Value?
    var trashItemCount: Int?
    var networkActivity: MenuBarSystemSnapshot.NetworkActivity?
    var localIPAddress: String?
}

/// Only this small cross-queue state is shared. Hardware and listener storage
/// remain confined to the reader's serial queue. Cleanup also coalesces.
final class SystemStatusReaderLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var generation: UInt64 = 0
    private var cleanupQueued = false

    func activate() -> UInt64 {
        lock.withLock {
            active = true
            return generation
        }
    }

    func isActive(_ expected: UInt64) -> Bool {
        lock.withLock { active && generation == expected }
    }

    func stopAndQueueCleanup() -> Bool {
        lock.withLock {
            active = false
            generation &+= 1
            guard !cleanupQueued else { return false }
            cleanupQueued = true
            return true
        }
    }

    func finishedCleanup() {
        lock.withLock { cleanupQueued = false }
    }
}
