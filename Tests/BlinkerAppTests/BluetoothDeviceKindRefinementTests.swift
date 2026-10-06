@testable import BlinkerApp
import XCTest

/// What the correction is allowed to change, and what it must leave alone.
final class BluetoothDeviceKindRefinementTests: XCTestCase {
    private let keyboardUsage = BluetoothHIDUsage(usagePage: 1, usage: 6)
    private let mouseUsage = BluetoothHIDUsage(usagePage: 1, usage: 2)

    private func device(
        address: String = "D3:6D:6C:40:A3:2E",
        name: String = "MX Keys",
        kind: BluetoothDeviceKind,
        connected: Bool = true
    ) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: kind, isConnected: connected)
    }

    /// The MX Keys regression, end to end: the report says mouse, the
    /// Registry says keyboard, and the keyboard wins.
    func testAWronglyDeclaredMouseIsCorrectedToAKeyboard() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .mouse)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        XCTAssertEqual(refined.first?.kind, .keyboard)
        XCTAssertEqual(refined.first?.name, "MX Keys")
    }

    func testADeclaredMouseStaysMouseWhenItAlsoPresentsAKeyboardInterface() {
        for usages in [[mouseUsage, keyboardUsage], [keyboardUsage, mouseUsage]] {
            let refined = BluetoothDeviceKindRefinement.apply(
                to: [device(kind: .mouse)],
                hidUsages: ["D36D6C40A32E": usages]
            )

            XCTAssertEqual(refined.first?.kind, .mouse)
        }
    }

    func testAnUnknownKindStaysUnknownWhenMouseAndKeyboardAreAmbiguous() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .unknown)],
            hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
        )

        XCTAssertEqual(refined.first?.kind, .unknown)
    }

    func testADeclaredKeyboardStaysKeyboardWithItsPointerInterface() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .keyboard)],
            hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
        )

        XCTAssertEqual(refined.first?.kind, .keyboard)
    }

    func testADisconnectedDeviceIgnoresStaleHIDUsages() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .mouse, connected: false)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        XCTAssertEqual(refined.first?.kind, .mouse)
    }

    /// The Registry writes an address `d3-6d-6c-40-a3-2e` and the report
    /// writes the same device `D3:6D:6C:40:A3:2E`; the join normalizes both
    /// sides through the one normalization the app keys devices by.
    func testTheAddressIsJoinedAcrossBothSpellings() {
        XCTAssertEqual(BluetoothDevice.normalizedAddress("d3-6d-6c-40-a3-2e"), "D36D6C40A32E")

        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(address: "d3:6d:6c:40:a3:2e", kind: .mouse)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        XCTAssertEqual(refined.first?.kind, .keyboard)
    }

    /// A device the report could not classify at all is corrected into the
    /// peripheral family rather than left generic.
    func testAnUnclassifiedDeviceIsCorrectedToo() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .unknown)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        XCTAssertEqual(refined.first?.kind, .keyboard)
    }

    /// An audio device, a phone or a computer is never reclassified: each can
    /// expose a HID interface without being an input peripheral.
    func testOtherFamiliesAreNeverReclassified() {
        for kind: BluetoothDeviceKind in [.audio, .laptop, .phone, .tablet, .printer] {
            let refined = BluetoothDeviceKindRefinement.apply(
                to: [device(kind: kind)],
                hidUsages: ["D36D6C40A32E": [keyboardUsage]]
            )

            XCTAssertEqual(refined.first?.kind, kind)
        }
    }

    /// A paired but disconnected device has no Registry node, so its declared
    /// class stands — the same answer the app gave before this correction
    /// existed.
    func testADeviceTheRegistryDoesNotKnowKeepsItsDeclaredClass() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .mouse)],
            hidUsages: [:]
        )

        XCTAssertEqual(refined.first?.kind, .mouse)
    }

    /// A declared keyboard the Registry also calls a keyboard is left exactly
    /// as it was.
    func testAgreementChangesNothing() {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .keyboard)],
            hidUsages: ["D36D6C40A32E": [keyboardUsage]]
        )

        XCTAssertEqual(refined.first?.kind, .keyboard)
    }

    func testEveryDeviceInTheListKeepsItsPlace() {
        let devices = [
            device(address: "AA:BB:CC:DD:EE:FF", name: "AirPods", kind: .audio),
            // Declared a mouse, and corrected to the keyboard it is.
            device(address: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .mouse),
            device(address: "E3:58:42:F3:6D:02", name: "M585/M590", kind: .mouse),
        ]
        let refined = BluetoothDeviceKindRefinement.apply(
            to: devices,
            hidUsages: [
                "D36D6C40A32E": [keyboardUsage],
                "E35842F36D02": [mouseUsage],
            ]
        )

        XCTAssertEqual(refined.map(\.name), ["AirPods", "MX Keys", "M585/M590"])
        XCTAssertEqual(refined.map(\.kind), [.audio, .keyboard, .mouse])
    }
}

/// The profiler's own wiring: the correction runs, and the Registry is not
/// walked when the report carries nothing it could correct.
final class SystemBluetoothProfilerRefinementTests: XCTestCase {
    private let keyboardUsage = BluetoothHIDUsage(usagePage: 1, usage: 6)

    private let mouseAndKeyboardReport = """
    {"SPBluetoothDataType": [{"device_connected": [
      {"MX Keys": {"device_address": "D3:6D:6C:40:A3:2E", "device_minorType": "Mouse"}}
    ]}]}
    """

    private let audioOnlyReport = """
    {"SPBluetoothDataType": [{"device_connected": [
      {"AirPods": {"device_address": "AC:90:85:C2:9C:1F", "device_minorType": "Headphones"}}
    ]}]}
    """

    private func profiler(
        report: String,
        hidUsageProvider: @escaping () -> [String: [BluetoothHIDUsage]]
    ) -> SystemBluetoothProfiler {
        SystemBluetoothProfiler(
            minimumInterval: 0,
            outputProvider: { _ in Data(report.utf8) },
            hidUsageProvider: hidUsageProvider
        )
    }

    func testTheProfilerCorrectsADeclaredClassFromTheRegistry() {
        let profiler = profiler(report: mouseAndKeyboardReport) {
            ["D36D6C40A32E": [self.keyboardUsage]]
        }

        let devices = profiler.readDevices()

        XCTAssertEqual(devices?.first?.kind, .keyboard)
    }

    /// A second source is consulted only where the first left a question the
    /// app can answer: an all-audio report never triggers the Registry walk.
    func testTheRegistryIsNotWalkedWhenNothingNeedsCorrecting() {
        var walkCount = 0
        let profiler = profiler(report: audioOnlyReport) {
            walkCount += 1
            return [:]
        }

        let devices = profiler.readDevices()

        XCTAssertEqual(walkCount, 0)
        XCTAssertEqual(devices?.first?.kind, .audio)
    }

    /// A report whose only peripheral-class device is not connected cannot be
    /// refined, so the walk is skipped too.
    func testTheRegistryIsNotWalkedForDisconnectedPeripherals() {
        let report = """
        {"SPBluetoothDataType": [{"device_not_connected": [
          {"MX Keys": {"device_address": "D3:6D:6C:40:A3:2E", "device_minorType": "Mouse"}}
        ]}]}
        """
        var walkCount = 0
        let profiler = profiler(report: report) {
            walkCount += 1
            return [:]
        }

        let devices = profiler.readDevices()

        XCTAssertEqual(walkCount, 0)
        XCTAssertEqual(devices?.first?.kind, .mouse)
    }
}
