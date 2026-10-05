import Foundation

/// One paired Bluetooth device as listed by the operating system.
struct BluetoothDevice: Identifiable, Equatable, Sendable {
    /// The device address as reported (`AA:BB:CC:DD:EE:FF`).
    var id: String
    var name: String
    var kind: BluetoothDeviceKind
    var isConnected: Bool
    /// Inquiry residue without a pairing record; System Settings never lists
    /// these, so the panel can hide them.
    var isUnpairedGhost = false
    /// Battery channels from the same report; nil when the device reports none.
    var battery: BluetoothDeviceBattery?
    /// Signal strength in dBm from the same report, when the system has a
    /// measurement; a snapshot value, freshest for recently seen devices.
    var rssi: Int?
    /// A2DP codec while audio streams; undocumented system value, shown
    /// only for the identifiers macOS is known to negotiate, and only read
    /// after the Bluetooth grant (see BluetoothConnectionDetails).
    var audioCodec: BluetoothConnectionDetails.AudioCodec?

    /// Address reduced to uppercase hex digits, the deduplication key. Two
    /// spellings of one address (`aa-bb` vs `AA:BB`) fold to one row.
    static func normalizedAddress(_ address: String) -> String {
        address.filter(\.isHexDigit).uppercased()
    }
}

/// Per-channel charge. AirPods are why one device can carry four values.
struct BluetoothDeviceBattery: Equatable, Sendable {
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var hasAny: Bool {
        main != nil || left != nil || right != nil || caseLevel != nil
    }
}

/// A device seen over the air by the BLE battery scan. Identity is the
/// CoreBluetooth peripheral UUID, which shares no format with a classic
/// address — folding onto a paired row happens by exact name instead.
struct NearbyBluetoothBatteryDevice: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var batteryLevel: Int
    var model: String?
    var manufacturer: String?
    var lastUpdated: Date
}

/// Presentation ordering shared by the panel and the settings list: the
/// user's manual order wins; unlisted devices keep their natural order
/// (connected first, then name).
enum BluetoothDeviceOrdering {
    static func ordered(_ devices: [BluetoothDevice], order: [String]) -> [BluetoothDevice] {
        let natural = devices.enumerated().sorted { lhs, rhs in
            if lhs.element.isConnected != rhs.element.isConnected {
                return lhs.element.isConnected
            }
            let byName = lhs.element.name.localizedStandardCompare(rhs.element.name)
            return byName == .orderedSame ? lhs.offset < rhs.offset : byName == .orderedAscending
        }.map(\.element)
        // Re-enumerate: the fallback position must be the natural slot, not
        // the report's original slot.
        return natural.enumerated().sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.element.id) ?? (order.count + lhs.offset)
            let right = order.firstIndex(of: rhs.element.id) ?? (order.count + rhs.offset)
            return left < right
        }.map(\.element)
    }
}
