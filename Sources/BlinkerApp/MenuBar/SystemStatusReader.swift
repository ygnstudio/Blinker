// Monitoring design adapted from Status Trio, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: minimal local values, no identifying network/device data.
// See ThirdParty/StatusTrio for license and attribution.
import CoreWLAN
import Foundation
import IOKit.ps

@MainActor
final class SystemStatusReader: SystemStatusReading {
    var onChange: (@MainActor @Sendable () -> Void)?
    private let queue: DispatchQueue
    private let audio: SystemAudioStatusReader
    private let lifetime = SystemStatusReaderLifetime()

    init() {
        let queue = DispatchQueue(label: "Blinker.MenuBar.SystemRead", qos: .utility)
        self.queue = queue
        audio = SystemAudioStatusReader(queue: queue)
    }

    func read(
        path: SystemNetworkPath?,
        completion: @escaping @MainActor @Sendable (MenuBarSystemSnapshot) -> Void
    ) {
        let generation = lifetime.activate()
        let audio = audio
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
            let volume = audio.read(onChange: changed)
            // A stop during synchronous IPC cannot interrupt the system call.
            // Retire listeners before returning instead of starting another worker.
            if !lifetime.isActive(generation) {
                audio.stop()
            }
            let result = MenuBarSystemSnapshot(battery: battery, network: network, volume: volume)
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
        return network(path: path, powerOn: interface.powerOn(),
                       associated: interface.serviceActive(), rssi: interface.rssiValue())
    }

    nonisolated static func network(path: SystemNetworkPath?, powerOn: Bool,
                                    associated: Bool, rssi: Int?) -> MenuBarSystemSnapshot.Network {
        if let path, path.isSatisfied, path.usesWired {
            return .wired
        }
        guard powerOn else { return .off }
        guard let path else { return .unknown }
        guard path.isSatisfied else { return .disconnected }
        guard path.usesWiFi, associated else { return .unknown }
        let strength = switch rssi {
        case .some((-60) ... -1): 3
        case .some(-78 ... -61): 2
        case .some(-88 ... -79): 1
        default: 0
        }
        return .wifi(strength: strength)
    }
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
