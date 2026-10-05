@testable import BlinkerApp
import XCTest

final class SystemBluetoothProfilerTests: XCTestCase {
    private func report(_ sections: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": sections])
    }

    private func entry(
        _ name: String,
        address: String,
        minorType: String? = nil,
        battery: [String: Any] = [:]
    ) -> [String: Any] {
        var properties: [String: Any] = ["device_address": address]
        if let minorType { properties["device_minorType"] = minorType }
        for (key, value) in battery { properties[key] = value }
        return [name: properties]
    }

    func testParsesDevicesFromBothCollections() throws {
        let json = try report([[
            "device_connected": [
                entry("Magic Keyboard", address: "AA:BB:CC:00:00:01", minorType: "Keyboard",
                      battery: ["device_batteryLevelMain": NSNumber(value: 82)]),
            ],
            "device_not_connected": [
                entry("AirPods Pro", address: "AA:BB:CC:00:00:02", minorType: "Headphones",
                      battery: [
                          "device_batteryLevelLeft": NSNumber(value: 80),
                          "device_batteryLevelRight": NSNumber(value: 90),
                          "device_batteryLevelCase": "95%",
                      ]),
            ],
        ]])
        let devices = SystemBluetoothProfiler.parse(json: json)
        XCTAssertEqual(devices?.count, 2)
        let keyboard = devices?.first { $0.name == "Magic Keyboard" }
        XCTAssertEqual(keyboard?.kind, .keyboard)
        XCTAssertEqual(keyboard?.isConnected, true)
        XCTAssertEqual(keyboard?.battery?.main, 82)
        XCTAssertEqual(keyboard?.isUnpairedGhost, false)
        let airPods = devices?.first { $0.name == "AirPods Pro" }
        XCTAssertEqual(airPods?.kind, .audio)
        XCTAssertEqual(airPods?.isConnected, false)
        XCTAssertEqual(airPods?.battery?.left, 80)
        XCTAssertEqual(airPods?.battery?.right, 90)
        XCTAssertEqual(airPods?.battery?.caseLevel, 95)
        XCTAssertNil(airPods?.battery?.main)
    }

    func testDuplicateAddressKeepsConnectedEntry() throws {
        // A connect caught mid-flight lists one address in both collections.
        let json = try report([[
            "device_connected": [
                entry("Mouse", address: "aa-bb-cc-00-00-03", minorType: "Mouse"),
            ],
            "device_not_connected": [
                entry("Mouse", address: "AA:BB:CC:00:00:03", minorType: "Mouse"),
            ],
        ]])
        let devices = SystemBluetoothProfiler.parse(json: json)
        XCTAssertEqual(devices?.count, 1)
        XCTAssertEqual(devices?.first?.isConnected, true)
    }

    func testEntriesWithoutMinorTypeAreGhosts() throws {
        let json = try report([[
            "device_not_connected": [
                entry("Unknown Beacon", address: "AA:BB:CC:00:00:04"),
                entry("Trackpad", address: "AA:BB:CC:00:00:05", minorType: "Trackpad"),
            ],
        ]])
        let devices = SystemBluetoothProfiler.parse(json: json)
        XCTAssertEqual(devices?.first { $0.name == "Unknown Beacon" }?.isUnpairedGhost, true)
        XCTAssertEqual(devices?.first { $0.name == "Trackpad" }?.isUnpairedGhost, false)
    }

    func testUnreadableReportIsNilButEmptyReportIsEmptyArray() throws {
        XCTAssertNil(SystemBluetoothProfiler.parse(json: Data("not json".utf8)))
        XCTAssertNil(SystemBluetoothProfiler.parse(json: Data("{}".utf8)))
        XCTAssertEqual(SystemBluetoothProfiler.parse(json: try report([[:]])), [])
        // The single-dictionary wrapper form is also accepted.
        let single = try JSONSerialization.data(
            withJSONObject: ["SPBluetoothDataType": ["device_connected": [
                entry("Keyboard", address: "AA:BB:CC:00:00:06", minorType: "Keyboard"),
            ]]]
        )
        XCTAssertEqual(SystemBluetoothProfiler.parse(json: single)?.count, 1)
    }

    func testEntriesMissingAddressOrNameAreDropped() throws {
        let json = try report([[
            "device_connected": [
                ["No Address": ["device_minorType": "Mouse"]],
                ["": ["device_address": "AA:BB:CC:00:00:07"]],
                entry("Valid", address: "AA:BB:CC:00:00:08", minorType: "Mouse"),
            ],
        ]])
        let devices = SystemBluetoothProfiler.parse(json: json)
        XCTAssertEqual(devices?.map(\.name), ["Valid"])
    }

    func testPercentageValidation() {
        XCTAssertEqual(SystemBluetoothProfiler.percentage(NSNumber(value: 85)), 85)
        XCTAssertEqual(SystemBluetoothProfiler.percentage("85%"), 85)
        XCTAssertEqual(SystemBluetoothProfiler.percentage(" 42 "), 42)
        XCTAssertEqual(SystemBluetoothProfiler.percentage(NSNumber(value: 0)), 0)
        XCTAssertEqual(SystemBluetoothProfiler.percentage(NSNumber(value: 100)), 100)
        XCTAssertNil(SystemBluetoothProfiler.percentage(NSNumber(value: 101)))
        XCTAssertNil(SystemBluetoothProfiler.percentage(NSNumber(value: -1)))
        XCTAssertNil(SystemBluetoothProfiler.percentage(NSNumber(value: 85.5)))
        XCTAssertNil(SystemBluetoothProfiler.percentage("high"))
        XCTAssertNil(SystemBluetoothProfiler.percentage(nil))
    }

    func testDeviceWithoutBatteryChannelsHasNoBattery() throws {
        let json = try report([[
            "device_connected": [
                entry("Phone", address: "AA:BB:CC:00:00:09", minorType: "Smart Phone"),
            ],
        ]])
        XCTAssertNil(SystemBluetoothProfiler.parse(json: json)?.first?.battery)
    }

    func testRSSIValidation() {
        XCTAssertEqual(SystemBluetoothProfiler.rssi(NSNumber(value: -67)), -67)
        XCTAssertEqual(SystemBluetoothProfiler.rssi("-89"), -89)
        XCTAssertEqual(SystemBluetoothProfiler.rssi(NSNumber(value: 0)), 0)
        XCTAssertEqual(SystemBluetoothProfiler.rssi(NSNumber(value: -100)), -100)
        XCTAssertEqual(SystemBluetoothProfiler.rssi(NSNumber(value: 20)), 20)
        XCTAssertNil(SystemBluetoothProfiler.rssi(NSNumber(value: 127)))
        XCTAssertNil(SystemBluetoothProfiler.rssi(NSNumber(value: -128)))
        XCTAssertNil(SystemBluetoothProfiler.rssi(NSNumber(value: -67.5)))
        XCTAssertNil(SystemBluetoothProfiler.rssi("loud"))
        XCTAssertNil(SystemBluetoothProfiler.rssi(nil))
    }

    func testReportRSSILandsOnTheDevice() throws {
        let json = try report([[
            "device_not_connected": [
                entry("Speaker", address: "AA:BB:CC:00:00:0A", minorType: "Speaker",
                      battery: ["device_rssi": NSNumber(value: -71)]),
                entry("Mouse", address: "AA:BB:CC:00:00:0B", minorType: "Mouse"),
            ],
        ]])
        let devices = SystemBluetoothProfiler.parse(json: json)
        XCTAssertEqual(devices?.first { $0.name == "Speaker" }?.rssi, -71)
        XCTAssertNil(devices?.first { $0.name == "Mouse" }?.rssi)
    }
}
