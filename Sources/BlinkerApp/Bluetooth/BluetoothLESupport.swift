// BLE candidate rules and nearby-device merge adapted from Status Trio,
// Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// See ThirdParty/StatusTrio for license and attribution.
import CoreBluetooth
import Foundation

/// Which advertisements the nearby battery scan may open a GATT session with.
///
/// Two routes lead to a connection. A peripheral listing the standard Battery
/// Service (180F) is asking to be read. An iPhone, iPad or Watch never
/// advertises 180F — it broadcasts its Continuity payload and only exposes the
/// Battery Service after connecting — so the second route recognizes Apple's
/// manufacturer payload. That route requires a name: CoreBluetooth only
/// reports one for a device this Mac already knows, which is what keeps the
/// scan to the user's devices instead of every stranger's phone in the room.
enum BluetoothLEAdvertisement {
    /// Apple's Bluetooth SIG company identifier, first on the wire.
    static let appleCompanyIdentifier: UInt8 = 0x4C

    /// Continuity message types an iOS device broadcasts while nearby:
    /// 0x10 Nearby Info and 0x0C Handoff. The byte after the company
    /// identifier is the message length, so the type is the third byte.
    static let continuityMessageTypes: Set<UInt8> = [0x10, 0x0C]

    private static let continuityMessageTypeOffset = 2

    static func advertisesBatteryService(_ serviceUUIDs: [CBUUID]?, batteryService: CBUUID) -> Bool {
        guard let serviceUUIDs else { return false }
        return serviceUUIDs.contains {
            $0.uuidString.caseInsensitiveCompare(batteryService.uuidString) == .orderedSame
        }
    }

    static func isAppleMobileDevice(manufacturerData: Data?) -> Bool {
        guard let manufacturerData,
              manufacturerData.count > continuityMessageTypeOffset else { return false }
        // Indices come from startIndex: a sliced Data keeps its buffer offsets.
        return manufacturerData[manufacturerData.startIndex] == appleCompanyIdentifier
            && continuityMessageTypes.contains(
                manufacturerData[manufacturerData.startIndex + continuityMessageTypeOffset]
            )
    }

    static func isCandidate(
        serviceUUIDs: [CBUUID]?,
        manufacturerData: Data?,
        name: String?,
        batteryService: CBUUID
    ) -> Bool {
        if advertisesBatteryService(serviceUUIDs, batteryService: batteryService) {
            return true
        }
        guard isAppleMobileDevice(manufacturerData: manufacturerData) else { return false }
        return !(name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum BluetoothLEParsing {
    static let batteryServiceUUID = CBUUID(string: "180F")
    static let batteryLevelUUID = CBUUID(string: "2A19")
    static let deviceInformationServiceUUID = CBUUID(string: "180A")
    static let modelNumberUUID = CBUUID(string: "2A24")
    static let manufacturerNameUUID = CBUUID(string: "2A29")

    /// A Battery Level characteristic is exactly one byte, 0...100.
    static func percentage(_ data: Data) -> Int? {
        guard data.count == 1, let value = data.first, value <= 100 else { return nil }
        return Int(value)
    }

    static func deviceInfo(_ data: Data) -> String? {
        guard let decoded = String(data: data, encoding: .utf8) else { return nil }
        let cleaned = decoded.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

/// The kind a Device Information model string implies, for Apple's mobile
/// family: an "iPhone17,2" seen over the air belongs on a phone row.
enum BluetoothMobileModel {
    static func kind(forModel model: String?) -> BluetoothDeviceKind? {
        guard let model else { return nil }
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("iphone") { return .phone }
        if value.hasPrefix("ipad") { return .tablet }
        if value.hasPrefix("watch") { return .watch }
        return nil
    }
}

/// Folds nearby battery readings onto the paired list. A nearby reading is
/// not a separate kind of device: an iPhone the profiler lists without a
/// class and the same iPhone seen over the air are one device on two
/// frequencies. The fold is by exact name — the only identity both sources
/// share — and only for Apple's mobile family; anything else stays a nearby
/// row. A paired row's own reading always wins over the air.
enum BluetoothNearbyMerge {
    static func merged(
        devices: [BluetoothDevice],
        nearby: [NearbyBluetoothBatteryDevice]
    ) -> (devices: [BluetoothDevice], remainingNearby: [NearbyBluetoothBatteryDevice]) {
        var merged = devices
        var remaining: [NearbyBluetoothBatteryDevice] = []
        for reading in nearby {
            guard let kind = BluetoothMobileModel.kind(forModel: reading.model),
                  !reading.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                remaining.append(reading)
                continue
            }
            if let index = merged.firstIndex(where: { matches($0.name, reading.name) }) {
                // The report's own class wins; only an unclassified row is corrected.
                if merged[index].kind == .unknown {
                    merged[index].kind = kind
                }
                if merged[index].battery == nil {
                    merged[index].battery = BluetoothDeviceBattery(main: reading.batteryLevel)
                }
            } else {
                merged.append(BluetoothDevice(
                    id: reading.id.uuidString,
                    name: reading.name,
                    kind: kind,
                    isConnected: false,
                    battery: BluetoothDeviceBattery(main: reading.batteryLevel)
                ))
            }
        }
        return (merged, remaining)
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !left.isEmpty && left == right
    }
}
