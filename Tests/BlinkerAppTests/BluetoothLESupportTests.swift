@testable import BlinkerApp
import CoreBluetooth
import XCTest

final class BluetoothLESupportTests: XCTestCase {
    private let batteryService = BluetoothLEParsing.batteryServiceUUID

    // MARK: Parsing

    func testPercentageByte() {
        XCTAssertEqual(BluetoothLEParsing.percentage(Data([0])), 0)
        XCTAssertEqual(BluetoothLEParsing.percentage(Data([100])), 100)
        XCTAssertNil(BluetoothLEParsing.percentage(Data([101])))
        XCTAssertNil(BluetoothLEParsing.percentage(Data([50, 60])))
        XCTAssertNil(BluetoothLEParsing.percentage(Data()))
    }

    func testDeviceInfoString() {
        XCTAssertEqual(BluetoothLEParsing.deviceInfo(Data("iPhone17,2\0".utf8)), "iPhone17,2")
        XCTAssertEqual(BluetoothLEParsing.deviceInfo(Data("  Watch7,1  ".utf8)), "Watch7,1")
        XCTAssertNil(BluetoothLEParsing.deviceInfo(Data(" \0 ".utf8)))
        XCTAssertNil(BluetoothLEParsing.deviceInfo(Data([0xFF, 0xFE])))
    }

    // MARK: Advertisement candidates

    func testBatteryServiceAdvertisementIsCandidateWithoutName() {
        XCTAssertTrue(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: [batteryService], manufacturerData: nil, name: nil,
            batteryService: batteryService
        ))
        // UUID comparison is case-insensitive.
        XCTAssertTrue(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: [CBUUID(string: "180f")], manufacturerData: nil, name: nil,
            batteryService: batteryService
        ))
    }

    func testAppleMobilePayloadNeedsKnownName() {
        // Nearby Info (0x10) and Handoff (0x0C), company id 0x4C.
        let continuity = Data([0x4C, 0x00, 0x10, 0x05, 0x00])
        XCTAssertTrue(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: nil, manufacturerData: continuity, name: "Yan's iPhone",
            batteryService: batteryService
        ))
        // A stranger's phone advertises the same payload but reports no name.
        XCTAssertFalse(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: nil, manufacturerData: continuity, name: nil,
            batteryService: batteryService
        ))
        XCTAssertFalse(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: nil, manufacturerData: continuity, name: "  ",
            batteryService: batteryService
        ))
    }

    func testNonAppleOrTruncatedPayloadsAreNotCandidates() {
        XCTAssertFalse(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: nil, manufacturerData: Data([0x4C]), name: "X",
            batteryService: batteryService
        ))
        XCTAssertFalse(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: nil, manufacturerData: Data([0x4C, 0x00]), name: "X",
            batteryService: batteryService
        ))
        XCTAssertFalse(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: nil, manufacturerData: Data([0x4C, 0x00, 0x09]), name: "X",
            batteryService: batteryService
        ))
        XCTAssertFalse(BluetoothLEAdvertisement.isCandidate(
            serviceUUIDs: nil, manufacturerData: Data([0xFF, 0x00, 0x10]), name: "X",
            batteryService: batteryService
        ))
    }

    // MARK: Mobile model

    func testMobileModelKinds() {
        XCTAssertEqual(BluetoothMobileModel.kind(forModel: "iPhone17,2"), .phone)
        XCTAssertEqual(BluetoothMobileModel.kind(forModel: "iPad14,3"), .tablet)
        XCTAssertEqual(BluetoothMobileModel.kind(forModel: "Watch7,1"), .watch)
        XCTAssertNil(BluetoothMobileModel.kind(forModel: "MacBookPro18,3"))
        XCTAssertNil(BluetoothMobileModel.kind(forModel: nil))
        XCTAssertNil(BluetoothMobileModel.kind(forModel: "  "))
    }

    // MARK: Merge

    private func nearby(
        name: String, level: Int, model: String? = nil
    ) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(id: UUID(), name: name, batteryLevel: level,
                                     model: model, manufacturer: nil, lastUpdated: Date())
    }

    private func device(
        name: String, kind: BluetoothDeviceKind, battery: BluetoothDeviceBattery? = nil
    ) -> BluetoothDevice {
        BluetoothDevice(id: "AA:BB:CC:00:00:01", name: name, kind: kind,
                        isConnected: true, battery: battery)
    }

    func testFoldsOntoSameNamedUnclassifiedRow() {
        let paired = [device(name: "Yan's iPhone", kind: .unknown)]
        let reading = nearby(name: "yan's iphone", level: 74, model: "iPhone17,2")
        let result = BluetoothNearbyMerge.merged(devices: paired, nearby: [reading])
        XCTAssertEqual(result.devices.count, 1)
        XCTAssertEqual(result.devices[0].kind, .phone)
        XCTAssertEqual(result.devices[0].battery?.main, 74)
        XCTAssertTrue(result.remainingNearby.isEmpty)
    }

    func testReportClassAndReportLevelAlwaysWin() {
        let paired = [device(name: "iPad", kind: .tablet,
                             battery: BluetoothDeviceBattery(main: 60))]
        let reading = nearby(name: "iPad", level: 20, model: "iPad14,3")
        let result = BluetoothNearbyMerge.merged(devices: paired, nearby: [reading])
        XCTAssertEqual(result.devices[0].battery?.main, 60)
    }

    func testUnlistedAppleMobileDeviceGetsItsOwnRow() {
        let result = BluetoothNearbyMerge.merged(
            devices: [],
            nearby: [nearby(name: "Watch", level: 55, model: "Watch7,1")]
        )
        XCTAssertEqual(result.devices.count, 1)
        XCTAssertEqual(result.devices[0].kind, .watch)
        XCTAssertEqual(result.devices[0].isConnected, false)
        XCTAssertEqual(result.devices[0].battery?.main, 55)
        XCTAssertTrue(result.remainingNearby.isEmpty)
    }

    func testNonAppleOrNamelessReadingsStayNearby() {
        let thermometer = nearby(name: "Thermo", level: 90, model: "TP-700")
        let nameless = nearby(name: " ", level: 10, model: "iPhone17,2")
        let result = BluetoothNearbyMerge.merged(devices: [], nearby: [thermometer, nameless])
        XCTAssertTrue(result.devices.isEmpty)
        XCTAssertEqual(result.remainingNearby.count, 2)
    }

    // MARK: Ordering

    func testOrderingPutsManualOrderFirstThenConnectedThenName() {
        let mouse = BluetoothDevice(id: "A", name: "Zulu", kind: .mouse, isConnected: false)
        let keyboard = BluetoothDevice(id: "B", name: "Alpha", kind: .keyboard, isConnected: true)
        let headset = BluetoothDevice(id: "C", name: "Beta", kind: .audio, isConnected: true)
        let ordered = BluetoothDeviceOrdering.ordered([mouse, keyboard, headset], order: ["A"])
        XCTAssertEqual(ordered.map(\.id), ["A", "B", "C"])
        // Without a manual order: connected first, then by name.
        let natural = BluetoothDeviceOrdering.ordered([mouse, headset, keyboard], order: [])
        XCTAssertEqual(natural.map(\.id), ["B", "C", "A"])
    }
}
