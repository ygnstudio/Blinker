@testable import BlinkerApp
import XCTest

/// The usage precedence that decides what a connected HID device really is.
///
/// The regression this pins: the Logitech `MX Keys` on the machine this was
/// written on reports `Mouse` in `device_minorType` while the system
/// enumerates `UsagePage 1 / Usage 6` for it — Generic Desktop keyboard, the
/// interface macOS loads a keyboard driver for. Trusting the report alone
/// draws a mouse glyph on the keyboard the user is typing on.
final class BluetoothHIDUsageClassifierTests: XCTestCase {
    private func usage(_ page: Int, _ usage: Int) -> BluetoothHIDUsage {
        BluetoothHIDUsage(usagePage: page, usage: usage)
    }

    func testCapabilitiesCollectEveryRecognizedInputRole() {
        let capabilities = BluetoothHIDCapabilities(usages: [
            usage(1, 2),       // mouse
            usage(1, 6),       // keyboard
            usage(0x0D, 0x05), // touch pad
            usage(1, 5),       // game pad
        ])

        XCTAssertTrue(capabilities.hasMouse)
        XCTAssertTrue(capabilities.hasKeyboard)
        XCTAssertTrue(capabilities.hasTrackpad)
        XCTAssertTrue(capabilities.hasGamepad)
    }

    func testUnknownUsagesProduceNoCapabilities() {
        let capabilities = BluetoothHIDCapabilities(usages: [usage(0x0C, 1), usage(1, 0x80)])

        XCTAssertFalse(capabilities.hasMouse)
        XCTAssertFalse(capabilities.hasKeyboard)
        XCTAssertFalse(capabilities.hasTrackpad)
        XCTAssertFalse(capabilities.hasGamepad)
    }

    func testTheKeyboardUsageIsAKeyboard() {
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 6)], declared: nil),
                       .keyboard)
    }

    func testTheKeypadUsageIsAKeyboard() {
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 7)], declared: nil),
                       .keyboard)
    }

    func testTheMouseUsageIsAMouse() {
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 2)], declared: nil),
                       .mouse)
    }

    func testThePointerAndMultiAxisUsagesAreAMouse() {
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 1)], declared: nil),
                       .mouse)
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 8)], declared: nil),
                       .mouse)
    }

    func testTheGamePadAndJoystickUsagesAreAGamepad() {
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 5)], declared: nil),
                       .gamepad)
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 4)], declared: nil),
                       .gamepad)
    }

    /// A trackpad enumerates as a pointer too, so the Digitizer page is what
    /// tells it apart from a mouse. Reading the pointer interface first would
    /// draw every trackpad as a mouse.
    func testTheTouchPadUsageOutranksThePointerUsageItAlsoPresents() {
        XCTAssertEqual(
            BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 2), usage(0x0D, 0x05)],
                                                    declared: nil),
            .trackpad
        )
        XCTAssertEqual(
            BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 2), usage(0x0D, 0x22)],
                                                    declared: nil),
            .trackpad
        )
    }

    func testADeclaredMouseOutranksAnAuxiliaryKeyboardInterface() {
        XCTAssertEqual(
            BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 2), usage(1, 6)],
                                                    declared: .mouse),
            .mouse
        )
    }

    func testAKeyboardOnlyUsageCorrectsAWronglyDeclaredMouse() {
        XCTAssertEqual(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 6)], declared: .mouse),
                       .keyboard)
    }

    func testADeclaredKeyboardOutranksItsPointerInterface() {
        XCTAssertEqual(
            BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 6), usage(1, 2)],
                                                    declared: .keyboard),
            .keyboard
        )
    }

    func testAmbiguousMouseAndKeyboardWithoutADeclarationAnswerNothing() {
        XCTAssertNil(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 2), usage(1, 6)],
                                                             declared: nil))
    }

    func testATrackpadOutranksAKeyboardOnTheSameDevice() {
        XCTAssertEqual(
            BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 6), usage(0x0D, 0x05)],
                                                    declared: nil),
            .trackpad
        )
    }

    /// Nothing here describes the device, so the declared class stands.
    func testUsagesThatDescribeNoInputDeviceAnswerNothing() {
        XCTAssertNil(BluetoothHIDUsageClassifier.refinedKind(from: [], declared: nil))
        XCTAssertNil(BluetoothHIDUsageClassifier.refinedKind(from: [usage(0x0C, 0x01)],
                                                             declared: nil))
        XCTAssertNil(BluetoothHIDUsageClassifier.refinedKind(from: [usage(1, 0x80)], declared: nil))
    }
}

/// The I/O Registry lookup stays limited to the four values needed to join
/// Bluetooth HID interfaces to paired devices and classify their usage.
final class BluetoothHIDRegistryPropertyReadTests: XCTestCase {
    func testBluetoothUsageReadsOnlyItsRequiredProperties() {
        var lookedUp: [String] = []
        let result = BluetoothHIDUsageReader.readUsage(from: 17) { _, key -> Any? in
            lookedUp.append(key as String)
            return switch key as String {
            case "Transport": "Bluetooth Low Energy"
            case "DeviceAddress": "d3-6d-6c-40-a3-2e"
            case "PrimaryUsagePage": 1
            case "PrimaryUsage": 6
            default: Optional<Any>.none
            }
        }

        XCTAssertEqual(lookedUp, ["Transport", "DeviceAddress", "PrimaryUsagePage", "PrimaryUsage"])
        XCTAssertEqual(result?.address, "d3-6d-6c-40-a3-2e")
        XCTAssertEqual(result?.usage, BluetoothHIDUsage(usagePage: 1, usage: 6))
    }

    func testNonBluetoothHIDServicesOnlyReadTransport() {
        var lookedUp: [String] = []
        let result = BluetoothHIDUsageReader.readUsage(from: 18) { _, key -> Any? in
            lookedUp.append(key as String)
            return "USB"
        }

        XCTAssertEqual(lookedUp, ["Transport"])
        XCTAssertNil(result)
    }
}
