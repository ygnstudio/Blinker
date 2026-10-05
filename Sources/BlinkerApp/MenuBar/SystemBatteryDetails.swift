import Foundation
import IOKit

/// Deep battery readings from the battery controller's IOKit properties:
/// cycle count, maximum capacity versus design, temperature and instantaneous
/// charge/discharge power. No permission is required; desktop Macs simply
/// have no `AppleSmartBattery` service and report nil throughout.
enum SystemBatteryDetails {
    /// One property read. Any field the controller does not publish stays
    /// nil and its panel row is hidden rather than guessed.
    struct Value: Equatable, Sendable {
        var cycleCount: Int?
        /// Current full-charge capacity as a percentage of design capacity.
        var healthPercent: Int?
        var temperatureCelsius: Double?
        /// Instantaneous power in watts; positive while charging, negative
        /// while discharging. nil when the current is too small to be
        /// meaningful or the sign cannot be determined.
        var powerWatts: Double?
    }

    static func read() -> Value? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return parse(properties: dictionary)
    }

    /// Pure parsing, separated from IOKit for tests. Units as published by
    /// AppleSmartBattery: temperature in 0.01 K, voltage in mV, current in mA
    /// (positive charging), capacities in mAh.
    static func parse(properties: [String: Any]) -> Value {
        let design = integer(properties["DesignCapacity"])
        let fullCharge = integer(properties["AppleRawMaxCapacity"])
            ?? integer(properties["NominalChargeCapacity"])
        var health: Int?
        if let design, design > 0, let fullCharge, fullCharge > 0 {
            health = min(100, max(0, Int((Double(fullCharge) / Double(design) * 100).rounded())))
        }
        let voltage = integer(properties["Voltage"])
        let amperage = integer(properties["InstantAmperage"])
            ?? integer(properties["Amperage"])
        var power: Double?
        if let voltage, voltage > 0, let amperage, abs(amperage) >= 10 {
            let watts = Double(voltage) * Double(abs(amperage)) / 1_000_000
            power = (amperage > 0 ? watts : -watts).rounded(toPlaces: 1)
        }
        return Value(
            cycleCount: integer(properties["CycleCount"]).flatMap { $0 >= 0 ? $0 : nil },
            healthPercent: health,
            temperatureCelsius: temperature(properties["Temperature"]),
            powerWatts: power
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            let double = number.doubleValue
            guard double.isFinite, double.rounded() == double,
                  double >= Double(Int.min), double <= Double(Int.max) else { return nil }
            return number.intValue
        case let value as Int:
            return value
        default:
            return nil
        }
    }

    /// The published unit varies by controller generation: centi-kelvin on
    /// some, deci-kelvin on Apple Silicon, centi-degrees on older hardware.
    /// Each candidate is tried in order against the battery's operating
    /// range; the first plausible reading wins and implausible raw values
    /// are dropped rather than mislabeled.
    static func temperature(_ raw: Any?) -> Double? {
        guard let value = integer(raw), value > 0 else { return nil }
        let number = Double(value)
        let candidates = [
            number / 100 - 273.15, // centi-kelvin
            number / 10 - 273.15, // deci-kelvin
            number / 100, // centi-degrees
        ]
        for candidate in candidates where (-30 ... 70).contains(candidate) {
            return candidate.rounded(toPlaces: 1)
        }
        return nil
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
