@testable import BlinkerApp
import XCTest

final class SystemBatteryDetailsTests: XCTestCase {
    func testFullReportParsesAllFields() {
        let value = SystemBatteryDetails.parse(properties: [
            "CycleCount": 117,
            "DesignCapacity": 4629,
            "AppleRawMaxCapacity": 4393,
            "Temperature": 2995,
            "Voltage": 13318,
            "Amperage": 475,
            "InstantAmperage": 475,
        ])
        XCTAssertEqual(value.cycleCount, 117)
        XCTAssertEqual(value.healthPercent, 95)
        XCTAssertEqual(value.temperatureCelsius ?? 0, 26.4, accuracy: 0.05)
        XCTAssertEqual(value.powerWatts ?? 0, 6.3, accuracy: 0.05)
    }

    func testDischargingCurrentProducesNegativePower() {
        let value = SystemBatteryDetails.parse(properties: [
            "Voltage": 11800,
            "Amperage": -2300,
        ])
        XCTAssertEqual(value.powerWatts ?? 0, -27.1, accuracy: 0.05)
        XCTAssertNil(value.cycleCount)
        XCTAssertNil(value.healthPercent)
        XCTAssertNil(value.temperatureCelsius)
    }

    func testTrickleCurrentHidesPower() {
        let value = SystemBatteryDetails.parse(properties: [
            "Voltage": 12000,
            "Amperage": 3,
        ])
        XCTAssertNil(value.powerWatts)
    }

    func testNominalCapacityIsHealthFallback() {
        let value = SystemBatteryDetails.parse(properties: [
            "DesignCapacity": 5000,
            "NominalChargeCapacity": 4000,
        ])
        XCTAssertEqual(value.healthPercent, 80)
    }

    func testHealthClampsToHundredAndSurvivesZeroDesign() {
        let above = SystemBatteryDetails.parse(properties: [
            "DesignCapacity": 4000,
            "AppleRawMaxCapacity": 4200,
        ])
        XCTAssertEqual(above.healthPercent, 100)
        let noDesign = SystemBatteryDetails.parse(properties: [
            "DesignCapacity": 0,
            "AppleRawMaxCapacity": 4200,
        ])
        XCTAssertNil(noDesign.healthPercent)
    }

    /// Controllers variously publish centi-kelvin, deci-kelvin (Apple
    /// Silicon) or centi-degrees; the first candidate inside the battery
    /// operating range wins, and implausible raw values are dropped.
    func testTemperatureUnitDisambiguation() {
        XCTAssertEqual(SystemBatteryDetails.temperature(29_950) ?? 0, 26.4, accuracy: 0.05)
        XCTAssertEqual(SystemBatteryDetails.temperature(2995) ?? 0, 26.4, accuracy: 0.05)
        XCTAssertEqual(SystemBatteryDetails.temperature(3500) ?? 0, 35.0, accuracy: 0.05)
        XCTAssertNil(SystemBatteryDetails.temperature(0))
        XCTAssertNil(SystemBatteryDetails.temperature(999_999))
        XCTAssertNil(SystemBatteryDetails.temperature("warm"))
    }

    func testMissingAndMalformedValuesStayUnknown() {
        let value = SystemBatteryDetails.parse(properties: [
            "CycleCount": "many",
            "DesignCapacity": -1,
            "Temperature": Double.nan,
            "Voltage": 0,
            "Amperage": 500,
        ])
        XCTAssertNil(value.cycleCount)
        XCTAssertNil(value.healthPercent)
        XCTAssertNil(value.temperatureCelsius)
        XCTAssertNil(value.powerWatts)
    }

    func testNegativeCycleCountIsRejected() {
        let value = SystemBatteryDetails.parse(properties: ["CycleCount": -4])
        XCTAssertNil(value.cycleCount)
    }
}
