@testable import BlinkerApp
import XCTest

/// IOBluetooth calls are unreachable from tests: the Bluetooth privacy gate
/// terminates processes without a usage description outright. Everything
/// here stays on the pure or injected surface.
final class BluetoothConnectionDetailsTests: XCTestCase {
    func testCodecMappingCoversKnownIdentifiersOnly() {
        XCTAssertEqual(BluetoothConnectionDetails.AudioCodec.mapped(from: 0), .sbc)
        XCTAssertEqual(BluetoothConnectionDetails.AudioCodec.mapped(from: 2), .aac)
        XCTAssertEqual(BluetoothConnectionDetails.AudioCodec.mapped(from: 4), .aptX)
        for unknown in [-1, 1, 3, 5, 6, 255] {
            XCTAssertNil(BluetoothConnectionDetails.AudioCodec.mapped(from: unknown))
        }
    }

    func testAttachingCodecsEnrichesConnectedDevicesViaInjectedLookup() {
        let devices = [
            BluetoothDevice(id: "AA:BB:CC:DD:EE:01", name: "耳机", kind: .audio,
                            isConnected: true),
            BluetoothDevice(id: "AA:BB:CC:DD:EE:02", name: "键盘", kind: .keyboard,
                            isConnected: false),
        ]
        let merged = BluetoothConnectionDetails.attachingCodecs(to: devices) { address in
            address == "AA:BB:CC:DD:EE:01" ? .aac : .sbc
        }
        XCTAssertEqual(merged[0].audioCodec, .aac)
        XCTAssertNil(merged[1].audioCodec, "Disconnected devices are never looked up")
        XCTAssertEqual(merged[0].name, devices[0].name)
        XCTAssertEqual(merged[1], devices[1])
    }

    func testAttachingCodecsWithoutReadingKeepsListUntouched() {
        let devices = [
            BluetoothDevice(id: "AA:BB:CC:DD:EE:01", name: "耳机", kind: .audio,
                            isConnected: true),
        ]
        let merged = BluetoothConnectionDetails.attachingCodecs(to: devices) { _ in nil }
        XCTAssertEqual(merged, devices)
    }
}
