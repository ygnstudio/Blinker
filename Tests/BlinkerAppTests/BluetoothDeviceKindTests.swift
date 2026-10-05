@testable import BlinkerApp
import XCTest

final class BluetoothDeviceKindTests: XCTestCase {
    private func kind(_ properties: [String: Any]) -> BluetoothDeviceKind {
        BluetoothDeviceKindResolver.kind(properties: properties)
    }

    func testExactMinorWording() {
        XCTAssertEqual(kind(["device_minorType": "Keyboard"]), .keyboard)
        XCTAssertEqual(kind(["device_minorType": "Mouse"]), .mouse)
        XCTAssertEqual(kind(["device_minorType": "Trackpad"]), .trackpad)
        XCTAssertEqual(kind(["device_minorType": "Headphones"]), .audio)
        XCTAssertEqual(kind(["device_minorType": "Smart Phone"]), .phone)
        XCTAssertEqual(kind(["device_minorType": "Laptop"]), .laptop)
        XCTAssertEqual(kind(["device_minorType": "Desktop"]), .desktop)
        XCTAssertEqual(kind(["device_minorType": "Tablet"]), .tablet)
        XCTAssertEqual(kind(["device_minorType": "Watch"]), .watch)
        XCTAssertEqual(kind(["device_minorType": "Gamepad"]), .gamepad)
        XCTAssertEqual(kind(["device_minorType": "Printer"]), .printer)
        XCTAssertEqual(kind(["device_minorType": "Toy"]), .toy)
        XCTAssertEqual(kind(["device_minorType": "Health"]), .health)
    }

    func testLegacyStringKeysAndNormalization() {
        // Older macOS reports the *_string variants; wording is punctuation-
        // and case-insensitive.
        XCTAssertEqual(kind(["device_minorClassOfDevice_string": "Smart Phone"]), .phone)
        XCTAssertEqual(kind(["device_minorType": "wearable-headset"]), .audio)
        XCTAssertEqual(kind(["device_minorType": "HANDS-FREE"]), .audio)
    }

    func testSubstringRuleOrderKeepsHeadsetsOffPhones() {
        // `headphone` must be tested before `phone`.
        XCTAssertEqual(kind(["device_minorType": "Headphone Adapter"]), .audio)
        XCTAssertEqual(kind(["device_minorType": "Earphones Pro"]), .audio)
        XCTAssertEqual(kind(["device_minorType": "Cellular Hotspot"]), .phone)
    }

    func testMajorWordingIsFallbackOnly() {
        XCTAssertEqual(kind(["device_majorType": "Audio"]), .audio)
        XCTAssertEqual(kind(["device_majorClassOfDevice_string": "Peripheral"]), .peripheral)
        // A specific minor wording wins over a generic major one.
        XCTAssertEqual(kind([
            "device_majorType": "Peripheral",
            "device_minorType": "Keyboard",
        ]), .keyboard)
    }

    func testUnrecognizedWordingIsUnknown() {
        XCTAssertEqual(kind(["device_minorType": "Warp Drive"]), .unknown)
        XCTAssertEqual(kind([:]), .unknown)
        XCTAssertEqual(kind(["device_minorType": 42]), .unknown)
        XCTAssertEqual(kind(["device_minorType": "   "]), .unknown)
    }

    func testEveryKindHasASymbol() {
        for kind in BluetoothDeviceKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind) has no icon")
        }
    }
}
