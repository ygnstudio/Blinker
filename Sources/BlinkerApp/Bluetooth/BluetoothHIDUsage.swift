// HID usage reading and kind correction adapted from Status Trio,
// Copyright 2026 lingyired. Apache-2.0; upstream
// d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: the classifier answers the flattened
// BluetoothDeviceKind directly instead of a nested PeripheralForm.
// See ThirdParty/StatusTrio for license and attribution.
import Foundation
import IOKit

/// One HID interface a device presents, as the I/O Registry describes it.
///
/// `usagePage` 1 is Generic Desktop, where the usages that name an input
/// device live: 2 mouse, 4 joystick, 5 game pad, 6 keyboard, 7 keypad,
/// 8 multi-axis. `usagePage` 0x0D is Digitizer, whose 5 is a touch pad — a
/// trackpad also enumerates as a pointer, so the page is what tells the two
/// apart.
struct BluetoothHIDUsage: Equatable, Sendable {
    let usagePage: Int
    let usage: Int
}

/// Reads the HID usages of every Bluetooth device the system has enumerated.
///
/// The class wording in the system profiler's report is the manufacturer's
/// claim about its product and it can be wrong: a Logitech keyboard reports
/// `Mouse` in `device_minorType`, while the usage it presents is Generic
/// Desktop keyboard — the one macOS actually loads a keyboard driver for.
/// The I/O Registry carries that usage and nothing else in the app reads it.
///
/// The walk runs inside this process: `IORegistryEntryCreateCFProperties`
/// over the services `IOServiceMatching` returns. There is no `ioreg` or
/// `hidutil` subprocess to hang the way `system_profiler` can, no Bluetooth
/// grant is involved, and the app is not sandboxed, so the Registry is
/// readable without a permission of any kind.
///
/// Only connected devices have a node. A paired but disconnected device keeps
/// the class the report declared, which is the same answer the app gave
/// before this reader existed.
enum BluetoothHIDUsageReader {
    /// Keyed by `BluetoothDevice.normalizedAddress`, the one normalization
    /// the app joins devices by, so a Registry address written
    /// `d3-6d-6c-40-a3-2e` and a report address written `D3:6D:6C:40:A3:2E`
    /// meet on the same key.
    static func read() -> [String: [BluetoothHIDUsage]] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var usages: [String: [BluetoothHIDUsage]] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let value = readUsage(from: service, using: registryProperty) else {
                continue
            }
            let key = BluetoothDevice.normalizedAddress(value.address)
            guard !key.isEmpty else { continue }
            usages[key, default: []].append(value.usage)
        }
        return usages
    }

    /// Reads only the four Registry values used to filter and classify a
    /// Bluetooth HID service. Transport is checked first so built-in and USB
    /// services avoid the other property lookups entirely.
    static func readUsage(
        from service: io_registry_entry_t,
        using readProperty: (io_registry_entry_t, CFString) -> Any?
    ) -> (address: String, usage: BluetoothHIDUsage)? {
        guard let transport = readProperty(service, "Transport" as CFString) as? String,
              transport.lowercased().contains("bluetooth"),
              let address = readProperty(service, "DeviceAddress" as CFString) as? String,
              let usagePage = readProperty(service, "PrimaryUsagePage" as CFString) as? Int,
              let usage = readProperty(service, "PrimaryUsage" as CFString) as? Int else {
            return nil
        }
        return (address, BluetoothHIDUsage(usagePage: usagePage, usage: usage))
    }

    private static func registryProperty(_ service: io_registry_entry_t, _ key: CFString) -> Any? {
        guard let property = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)
        else {
            return nil
        }
        return property.takeRetainedValue()
    }
}

/// Input roles observed across a device's HID interfaces.
struct BluetoothHIDCapabilities: Equatable, Sendable {
    let hasMouse: Bool
    let hasKeyboard: Bool
    let hasTrackpad: Bool
    let hasGamepad: Bool

    private enum UsagePage {
        static let genericDesktop = 1
        static let digitizer = 0x0D
    }

    private enum GenericDesktopUsage {
        static let pointer = 1
        static let mouse = 2
        static let joystick = 4
        static let gamePad = 5
        static let keyboard = 6
        static let keypad = 7
        static let multiAxisController = 8
    }

    private enum DigitizerUsage {
        static let touchPad = 0x05
        static let finger = 0x22
    }

    init(usages: [BluetoothHIDUsage]) {
        func has(_ page: Int, _ usage: Int) -> Bool {
            usages.contains { $0.usagePage == page && $0.usage == usage }
        }

        hasMouse = has(UsagePage.genericDesktop, GenericDesktopUsage.pointer)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.mouse)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.multiAxisController)
        hasKeyboard = has(UsagePage.genericDesktop, GenericDesktopUsage.keyboard)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.keypad)
        hasTrackpad = has(UsagePage.digitizer, DigitizerUsage.touchPad)
            || has(UsagePage.digitizer, DigitizerUsage.finger)
        hasGamepad = has(UsagePage.genericDesktop, GenericDesktopUsage.joystick)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.gamePad)
    }
}

/// Turns the usages a device presents into the peripheral it is.
///
/// Pure, so role selection is unit-tested rather than inferred from a live
/// Mac's device list. Specialized roles take precedence, while a device with
/// both mouse and keyboard capabilities needs its declared kind to
/// disambiguate.
enum BluetoothHIDUsageClassifier {
    /// `nil` when nothing here describes the device or a mouse/keyboard
    /// combination has no declared kind to resolve the ambiguity. Only
    /// peripheral answers are ever produced — the correction can move a
    /// device inside the peripheral family, never into another one.
    static func refinedKind(
        from usages: [BluetoothHIDUsage],
        declared: BluetoothDeviceKind?
    ) -> BluetoothDeviceKind? {
        let capabilities = BluetoothHIDCapabilities(usages: usages)

        if capabilities.hasTrackpad { return .trackpad }
        if capabilities.hasGamepad { return .gamepad }

        if capabilities.hasMouse && capabilities.hasKeyboard {
            if declared == .mouse || declared == .keyboard {
                return declared
            }
            return nil
        }
        if capabilities.hasKeyboard { return .keyboard }
        if capabilities.hasMouse { return .mouse }
        return nil
    }
}

extension BluetoothDeviceKind {
    /// An audio device, a phone or a computer is never reclassified: each
    /// can expose a HID interface (remote control, audio buttons) without
    /// being an input peripheral, so the report's wording stays
    /// authoritative for them. Unknown kinds accept the correction — the
    /// Registry answer is better than none.
    var acceptsHIDRefinement: Bool {
        switch self {
        case .keyboard, .mouse, .trackpad, .gamepad, .peripheral, .unknown: true
        case .laptop, .desktop, .computer, .phone, .tablet, .watch, .audio,
             .printer, .scanner, .camera, .display, .imaging, .toy, .health: false
        }
    }
}

/// Corrects the class a connected HID device declared.
///
/// `BluetoothHIDUsageClassifier` combines the interfaces with the declared
/// kind; this decides whether that answer may be used. The report's wording
/// stays authoritative for unsupported kinds and disconnected devices.
enum BluetoothDeviceKindRefinement {
    static func apply(
        to devices: [BluetoothDevice],
        hidUsages: [String: [BluetoothHIDUsage]]
    ) -> [BluetoothDevice] {
        devices.map { device in
            guard device.isConnected, device.kind.acceptsHIDRefinement else {
                return device
            }
            guard let kind = BluetoothHIDUsageClassifier.refinedKind(
                from: hidUsages[BluetoothDevice.normalizedAddress(device.id)] ?? [],
                declared: device.kind
            ) else {
                return device
            }
            var corrected = device
            corrected.kind = kind
            return corrected
        }
    }
}
