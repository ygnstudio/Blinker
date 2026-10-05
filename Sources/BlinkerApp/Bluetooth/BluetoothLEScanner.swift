// BLE battery scanning adapted from Status Trio, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: setEnabled/requestAccess surface instead of a
// controller-driven lifecycle; policy inlined.
// See ThirdParty/StatusTrio for license and attribution.
import CoreBluetooth
import Foundation

/// Scans for nearby BLE devices and reads their Battery Service over GATT.
/// Off by default (the toggle also carries the Bluetooth permission cost);
/// while enabled, a five-second scan window runs at most every 60 seconds.
/// Advertisements are only candidate filters — the level itself is always
/// read after connecting, which is the only route an iPhone offers at all.
@MainActor
final class BluetoothLEScanner: NSObject, ObservableObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var nearbyDevices: [NearbyBluetoothBatteryDevice] = []
    @Published private(set) var authorization: CBManagerAuthorization = CBManager.authorization
    @Published private(set) var isScanning = false

    private static let scanWindow: TimeInterval = 5
    private static let automaticScanInterval: TimeInterval = 60
    private static let successfulConnectionCooldown: TimeInterval = 60
    private static let failedConnectionCooldown: TimeInterval = 30
    private static let resultLifetime: TimeInterval = 1800
    private static let maxQueuedCandidates = 8
    private static let maxConcurrentConnections = 2
    private static let connectionTimeout: TimeInterval = 4

    nonisolated(unsafe) private var centralManager: CBCentralManager?
    private var isEnabled = false
    private var generation: UInt64 = 0
    private var scanWindowTask: Task<Void, Never>?
    private var automaticRefreshTask: Task<Void, Never>?
    // Session state is shared with the GATT extension file.
    var sessions: [UUID: PeripheralSession] = [:]
    private var queuedCandidates: [UUID] = []
    var candidatePeripherals: [UUID: CBPeripheral] = [:]
    var candidateNames: [UUID: String] = [:]
    private var retryAfter: [UUID: Date] = [:]
    private var lastScanStartedAt: Date?

    struct PeripheralSession {
        let peripheral: CBPeripheral
        let generation: UInt64
        let advertisedName: String?
        var timeoutTask: Task<Void, Never>?
        var pendingCharacteristicDiscoveries = 0
        var pendingReads: Set<CBUUID> = []
        var batteryLevel: Int?
        var model: String?
        var manufacturer: String?
    }

    deinit {
        scanWindowTask?.cancel()
        automaticRefreshTask?.cancel()
        let manager = centralManager
        let peripherals = sessions.values.map(\.peripheral)
        sessions.values.forEach { $0.timeoutTask?.cancel() }
        guard manager != nil || !peripherals.isEmpty else { return }
        Task { @MainActor in
            manager?.stopScan()
            for peripheral in peripherals {
                peripheral.delegate = nil
                manager?.cancelPeripheralConnection(peripheral)
            }
            manager?.delegate = nil
        }
    }

    // MARK: - Lifecycle

    /// The single external switch, driven by the panel configuration.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            authorization = CBManager.authorization
            guard authorization == .allowedAlways else { return }
            ensureCentralManager()
            if centralManager?.state == .poweredOn {
                startScanWindow(manual: true)
            }
        } else {
            stop()
        }
    }

    /// Instantiating the central is what shows the system prompt on macOS
    /// once the usage string exists; the state callback then refreshes
    /// `authorization`. No-op when the grant is already settled.
    func requestAccess() {
        ensureCentralManager()
    }

    /// A fresh scan outside the automatic cadence, e.g. the panel opening.
    func refresh() {
        guard isEnabled else { return }
        authorization = CBManager.authorization
        guard authorization == .allowedAlways else { return }
        ensureCentralManager()
        if centralManager?.state == .poweredOn {
            startScanWindow(manual: true)
        }
    }

    private func ensureCentralManager() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    private func stop() {
        generation &+= 1
        stopActiveWork(clearResults: true)
        retryAfter.removeAll()
        centralManager?.delegate = nil
        centralManager = nil
    }

    private func stopActiveWork(clearResults: Bool) {
        scanWindowTask?.cancel()
        scanWindowTask = nil
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        centralManager?.stopScan()
        isScanning = false
        for (_, session) in sessions {
            session.timeoutTask?.cancel()
            session.peripheral.delegate = nil
            centralManager?.cancelPeripheralConnection(session.peripheral)
        }
        sessions.removeAll()
        queuedCandidates.removeAll()
        candidatePeripherals.removeAll()
        candidateNames.removeAll()
        if clearResults {
            nearbyDevices = []
        }
    }

    // MARK: - Scan window

    private func startScanWindow(manual: Bool) {
        guard isEnabled, !isScanning,
              let centralManager, centralManager.state == .poweredOn else { return }
        let now = Date()
        if !manual, let last = lastScanStartedAt,
           now.timeIntervalSince(last) < Self.automaticScanInterval { return }
        lastScanStartedAt = now
        retryAfter = retryAfter.filter { $0.value > now }
        generation &+= 1
        let current = generation
        queuedCandidates.removeAll()
        candidatePeripherals.removeAll()
        candidateNames.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scheduleAutomaticRefresh()
        scanWindowTask?.cancel()
        scanWindowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.scanWindow))
            guard let self, !Task.isCancelled, generation == current, isEnabled, isScanning else {
                return
            }
            finishScanWindow()
        }
    }

    private func finishScanWindow() {
        scanWindowTask?.cancel()
        scanWindowTask = nil
        centralManager?.stopScan()
        isScanning = false
        // The scan window is the whole discovery budget: connections already
        // started may finish, the rest of the queue is dropped.
        queuedCandidates.removeAll()
        candidatePeripherals.removeAll(keepingCapacity: false)
        candidateNames.removeAll(keepingCapacity: false)
    }

    private func scheduleAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.automaticScanInterval))
            guard let self, !Task.isCancelled, isEnabled else { return }
            startScanWindow(manual: false)
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        authorization = CBManager.authorization
        switch central.state {
        case .poweredOn:
            if isEnabled {
                startScanWindow(manual: true)
            }
        case .unauthorized, .unsupported:
            if isEnabled {
                stopActiveWork(clearResults: true)
            } else {
                // A denied access request leaves nothing worth keeping alive.
                central.delegate = nil
                centralManager = nil
            }
        case .unknown, .resetting, .poweredOff:
            stopActiveWork(clearResults: false)
        @unknown default:
            stopActiveWork(clearResults: false)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        guard isEnabled, isScanning,
              BluetoothLEAdvertisement.isCandidate(
                  serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
                  manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                  name: advertisedName,
                  batteryService: BluetoothLEParsing.batteryServiceUUID
              ) else { return }
        let identifier = peripheral.identifier
        guard sessions[identifier] == nil,
              !queuedCandidates.contains(identifier),
              retryAfter[identifier] == nil,
              queuedCandidates.count < Self.maxQueuedCandidates else { return }
        peripheral.delegate = self
        queuedCandidates.append(identifier)
        candidatePeripherals[identifier] = peripheral
        candidateNames[identifier] = advertisedName
        startQueuedConnections()
    }

    private func startQueuedConnections() {
        guard isEnabled, let centralManager, centralManager.state == .poweredOn else { return }
        while sessions.count < Self.maxConcurrentConnections, !queuedCandidates.isEmpty {
            let identifier = queuedCandidates.removeFirst()
            guard let peripheral = candidatePeripherals[identifier] else { continue }
            let current = generation
            var session = PeripheralSession(
                peripheral: peripheral,
                generation: current,
                advertisedName: candidateNames[identifier] ?? peripheral.name,
                timeoutTask: nil
            )
            session.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.connectionTimeout))
                guard let self, !Task.isCancelled,
                      let active = sessions[identifier], active.generation == current else { return }
                // A level read before the timeout still counts as answered.
                completeSession(for: identifier, succeeded: active.batteryLevel != nil)
            }
            sessions[identifier] = session
            centralManager.connect(peripheral, options: nil)
        }
    }

    // MARK: - Seams for the GATT extension (BluetoothLEScanner+GATT.swift)

    func connect(_ peripheral: CBPeripheral) {
        centralManager?.connect(peripheral, options: nil)
    }

    func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func recordCooldown(for identifier: UUID, succeeded: Bool) {
        retryAfter[identifier] = Date().addingTimeInterval(
            succeeded ? Self.successfulConnectionCooldown : Self.failedConnectionCooldown
        )
    }

    func emitNearby(_ session: PeripheralSession) {
        guard let level = session.batteryLevel else { return }
        let now = Date()
        var current = Dictionary(uniqueKeysWithValues: nearbyDevices.map { ($0.id, $0) })
            .filter { now.timeIntervalSince($0.value.lastUpdated) <= Self.resultLifetime }
        current[session.peripheral.identifier] = NearbyBluetoothBatteryDevice(
            id: session.peripheral.identifier,
            name: session.advertisedName ?? session.peripheral.name ?? "",
            batteryLevel: level,
            model: session.model,
            manufacturer: session.manufacturer,
            lastUpdated: now
        )
        nearbyDevices = current.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func startNextQueuedConnections() {
        startQueuedConnections()
    }
}
