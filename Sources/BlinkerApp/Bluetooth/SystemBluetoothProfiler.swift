// Paired-device reading adapted from Status Trio, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: one folded device model, a bounded subprocess with a
// last-good cache instead of watchdog queue generations, no HID refinement.
// See ThirdParty/StatusTrio for license and attribution.
import Foundation

/// Reads the operating system's paired-device database via
/// `system_profiler -json SPBluetoothDataType`. Like upstream, this avoids a
/// Bluetooth inquiry entirely: the profiler reports the names the system
/// currently uses (IOBluetooth caches stale names after a rename), and the
/// battery channels come from the same report. Thread-safe; one instance is
/// shared by the serial reader queue.
final class SystemBluetoothProfiler: @unchecked Sendable {
    private let lock = NSLock()
    private var lastDevices: [BluetoothDevice]?
    private var lastRead: Date?
    /// A hung profiler must never blank the icon: after this bound the
    /// subprocess is terminated and the previous list stands.
    private let timeout: TimeInterval
    /// Event bursts coalesce; the subprocess spawns at most this often.
    private let minimumInterval: TimeInterval

    init(timeout: TimeInterval = 4, minimumInterval: TimeInterval = 5) {
        self.timeout = timeout
        self.minimumInterval = minimumInterval
    }

    /// The current paired-device list. A read failure keeps the previous list;
    /// `nil` only means no read has ever succeeded.
    func readDevices() -> [BluetoothDevice]? {
        lock.lock()
        defer { lock.unlock() }
        if let lastRead, Date().timeIntervalSince(lastRead) < minimumInterval {
            return lastDevices
        }
        lastRead = Date()
        guard let data = Self.readProfilerOutput(timeout: timeout),
              let devices = Self.parse(json: data) else {
            return lastDevices
        }
        lastDevices = devices
        return devices
    }

    // MARK: - Subprocess

    private final class ResultBox: @unchecked Sendable {
        var data = Data()
        var status: Int32 = -1
    }

    static func readProfilerOutput(timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            box.status = process.terminationStatus
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        return box.status == 0 ? box.data : nil
    }

    // MARK: - Parsing (pure)

    /// `nil` means the report could not be read at all; an empty array means
    /// the machine has no paired devices. The two stay distinct so a failure
    /// is never displayed as an empty list.
    static func parse(json: Data) -> [BluetoothDevice]? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            return nil
        }
        let sections: [[String: Any]]
        if let array = root["SPBluetoothDataType"] as? [[String: Any]] {
            sections = array
        } else if let single = root["SPBluetoothDataType"] as? [String: Any] {
            sections = [single]
        } else {
            return nil
        }
        var devices: [BluetoothDevice] = []
        // Connected entries are read first, so a connect caught mid-flight —
        // one address in both collections — keeps the live row.
        var listedAddresses: Set<String> = []
        for section in sections {
            for collectionKey in ["device_connected", "device_not_connected"] {
                guard let entries = section[collectionKey] as? [[String: Any]] else { continue }
                for entry in entries {
                    for (name, value) in entry {
                        guard let device = device(
                            name: name,
                            properties: value as? [String: Any],
                            connected: collectionKey == "device_connected",
                            listedAddresses: &listedAddresses
                        ) else { continue }
                        devices.append(device)
                    }
                }
            }
        }
        return devices
    }

    private static func device(
        name: String,
        properties: [String: Any]?,
        connected: Bool,
        listedAddresses: inout Set<String>
    ) -> BluetoothDevice? {
        guard let properties,
              let address = properties["device_address"] as? String,
              !address.isEmpty,
              !name.isEmpty else { return nil }
        let key = BluetoothDevice.normalizedAddress(address)
        if !key.isEmpty {
            guard listedAddresses.insert(key).inserted else { return nil }
        }
        return BluetoothDevice(
            id: address,
            name: name,
            kind: BluetoothDeviceKindResolver.kind(properties: properties),
            isConnected: connected,
            isUnpairedGhost: isGhost(properties: properties),
            battery: battery(properties: properties)
        )
    }

    /// No minor-type wording at all means the entry is inquiry residue, not a
    /// pairing record; System Settings' "My Devices" never lists these.
    private static func isGhost(properties: [String: Any]) -> Bool {
        properties["device_minorType"] == nil
            && properties["device_minorClassOfDevice_string"] == nil
    }

    private static func battery(properties: [String: Any]) -> BluetoothDeviceBattery? {
        let value = BluetoothDeviceBattery(
            main: percentage(properties["device_batteryLevelMain"])
                ?? percentage(properties["device_batteryLevel"]),
            left: percentage(properties["device_batteryLevelLeft"]),
            right: percentage(properties["device_batteryLevelRight"]),
            caseLevel: percentage(properties["device_batteryLevelCase"])
        )
        return value.hasAny ? value : nil
    }

    /// Levels arrive as `NSNumber` or a percent-suffixed string; anything
    /// non-integral or outside 0...100 is not a charge.
    static func percentage(_ value: Any?) -> Int? {
        let number: Double
        switch value {
        case let value as NSNumber:
            number = value.doubleValue
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed.hasSuffix("%")
                ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                : trimmed
            guard let parsed = Double(body) else { return nil }
            number = parsed
        default:
            return nil
        }
        guard number.isFinite, number.rounded() == number, (0 ... 100).contains(number) else {
            return nil
        }
        return Int(number)
    }
}
