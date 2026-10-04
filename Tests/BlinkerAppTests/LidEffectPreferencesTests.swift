@testable import BlinkerApp
import XCTest

@MainActor
final class LidEffectPreferencesTests: XCTestCase {
    private final class RecordingDefaults: UserDefaults, @unchecked Sendable {
        var writes = 0
        override func set(_ value: Any?, forKey defaultName: String) {
            writes += 1
            super.set(value, forKey: defaultName)
        }
    }

    private func withDefaults(_ body: (RecordingDefaults) throws -> Void) throws {
        let suite = "Blinker.LidEffectPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testDefaultsAreOptInAndLoadingDoesNotWrite() throws {
        try withDefaults { defaults in
            let preferences = LidEffectPreferences(defaults: defaults)
            XCTAssertEqual(preferences.configuration, LidEffectConfiguration())
            XCTAssertFalse(preferences.configuration.isEnabled)
            XCTAssertEqual(preferences.configuration.animationSpeed, 1)
            XCTAssertEqual(defaults.writes, 0)
        }
    }

    func testDuoAndGestureChoicesSurviveReload() throws {
        try withDefaults { defaults in
            let preferences = LidEffectPreferences(defaults: defaults)
            preferences.update {
                $0.isEnabled = true
                $0.referenceAngle = 125
                $0.sensitivity = 5
                $0.fullEffectSpan = 40
                $0.clearDelay = 2
                $0.holdsUntilReopened = true
                $0.tilt = 45
                $0.frost = 0.1
                $0.darkness = 0.2
                $0.blur = 0.3
                $0.edgeSoftness = 0.4
                $0.smoothingFrames = 8
                $0.animationSpeed = 1.5
            }
            XCTAssertEqual(LidEffectPreferences(defaults: defaults).configuration, preferences.configuration)
        }
    }

    func testEveryFloatingPointControlRejectsNonfiniteAndClampsToItsRange() {
        let fields: [(WritableKeyPath<LidEffectConfiguration, Double>, ClosedRange<Double>)] = [
            (\.referenceAngle, 20 ... 180), (\.sensitivity, 3 ... 15), (\.fullEffectSpan, 5 ... 90),
            (\.clearDelay, 0 ... 5), (\.tilt, 0 ... 80), (\.frost, 0 ... 1), (\.darkness, 0 ... 1),
            (\.blur, 0 ... 1), (\.edgeSoftness, 0 ... 1), (\.animationSpeed, 0.25 ... 2),
        ]
        for (field, range) in fields {
            var value = LidEffectConfiguration()
            let fallback = value[keyPath: field]
            for invalid in [Double.nan, .infinity, -.infinity] {
                value[keyPath: field] = invalid
                XCTAssertEqual(value.normalized()[keyPath: field], fallback)
            }
            value[keyPath: field] = range.lowerBound - 100
            XCTAssertEqual(value.normalized()[keyPath: field], range.lowerBound)
            value[keyPath: field] = range.upperBound + 100
            XCTAssertEqual(value.normalized()[keyPath: field], range.upperBound)
        }
        var value = LidEffectConfiguration()
        value.smoothingFrames = .min
        XCTAssertEqual(value.normalized().smoothingFrames, 1)
        value.smoothingFrames = .max
        XCTAssertEqual(value.normalized().smoothingFrames, 30)
    }

    func testMalformedOrInvalidSchemaFailsClosedWithoutReplacingSavedData() throws {
        try withDefaults { defaults in
            for data in [Data("broken JSON".utf8), Data(#"{"isEnabled":"yes"}"#.utf8)] {
                defaults.set(data, forKey: LidEffectPreferences.key)
                let count = defaults.writes
                let preferences = LidEffectPreferences(defaults: defaults)
                XCTAssertFalse(preferences.configuration.isEnabled)
                XCTAssertEqual(defaults.data(forKey: LidEffectPreferences.key), data)
                XCTAssertEqual(defaults.writes, count)
            }
        }
    }

    func testLoadingAndSavingNormalizeValuesWithoutWritingOnRead() throws {
        try withDefaults { defaults in
            var unsafe = LidEffectConfiguration()
            unsafe.referenceAngle = 999
            unsafe.fullEffectSpan = -100
            try defaults.set(JSONEncoder().encode(unsafe), forKey: LidEffectPreferences.key)
            let count = defaults.writes
            let preferences = LidEffectPreferences(defaults: defaults)
            XCTAssertEqual(preferences.configuration.referenceAngle, 180)
            XCTAssertEqual(preferences.configuration.fullEffectSpan, 5)
            XCTAssertEqual(defaults.writes, count)
            preferences.update { $0.blur = .nan; $0.isEnabled = true }
            let stored = try XCTUnwrap(defaults.data(forKey: LidEffectPreferences.key))
            XCTAssertEqual(try JSONDecoder().decode(LidEffectConfiguration.self, from: stored),
                           preferences.configuration)
        }
    }

    func testLegacySmallThresholdUsesNoiseFloorWithoutRewritingSavedChoices() throws {
        try withDefaults { defaults in
            for threshold in [1.0, 2.0, 3.0, 15.0] {
                var saved = LidEffectConfiguration()
                saved.isEnabled = true
                saved.sensitivity = threshold
                saved.referenceAngle = 120
                saved.fullEffectSpan = 75
                saved.clearDelay = 0.2
                saved.smoothingFrames = 30
                let data = try JSONEncoder().encode(saved)
                defaults.set(data, forKey: LidEffectPreferences.key)
                let count = defaults.writes
                let preferences = LidEffectPreferences(defaults: defaults)
                var expected = saved
                expected.sensitivity = max(3, threshold)
                XCTAssertEqual(preferences.configuration, expected)
                XCTAssertEqual(defaults.data(forKey: LidEffectPreferences.key), data)
                XCTAssertEqual(defaults.writes, count)
            }
        }
    }

    func testResetAndEquivalentUpdatesPreserveUnrelatedSettings() throws {
        try withDefaults { defaults in
            defaults.set("keep", forKey: "unrelated")
            let preferences = LidEffectPreferences(defaults: defaults)
            preferences.update { $0.isEnabled = true; $0.darkness = 0.8; $0.tilt = 999 }
            let count = defaults.writes
            preferences.update { $0.tilt = 1000 }
            XCTAssertEqual(defaults.writes, count)
            preferences.reset()
            XCTAssertEqual(preferences.configuration, LidEffectConfiguration())
            XCTAssertEqual(LidEffectPreferences(defaults: defaults).configuration, LidEffectConfiguration())
            XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
            let resetCount = defaults.writes
            preferences.reset()
            XCTAssertEqual(defaults.writes, resetCount)
        }
    }

    func testLegacyV1KeepsEverySavedChoiceAndDefaultsOnlyTheNewSpeed() throws {
        try withDefaults { defaults in
            let data = Data("""
            {"isEnabled":true,"referenceAngle":120,"sensitivity":9,"fullEffectSpan":75,
            "clearDelay":0.2,"holdsUntilReopened":true,"tilt":40,"frost":1,"darkness":0.7,
            "blur":0.8,"edgeSoftness":1,"smoothingFrames":30}
            """.utf8)
            defaults.set(data, forKey: LidEffectPreferences.key)
            let count = defaults.writes
            var expected = LidEffectConfiguration()
            expected.isEnabled = true
            expected.referenceAngle = 120
            expected.sensitivity = 9
            expected.fullEffectSpan = 75
            expected.clearDelay = 0.2
            expected.holdsUntilReopened = true
            expected.tilt = 40
            expected.frost = 1
            expected.darkness = 0.7
            expected.blur = 0.8
            expected.edgeSoftness = 1
            expected.smoothingFrames = 30
            let preferences = LidEffectPreferences(defaults: defaults)
            XCTAssertEqual(preferences.configuration, expected)
            XCTAssertEqual(preferences.configuration.animationSpeed, 1)
            XCTAssertEqual(defaults.data(forKey: LidEffectPreferences.key), data)
            XCTAssertEqual(defaults.writes, count, "Loading a legacy archive must not rewrite it")

            preferences.update { $0.animationSpeed = 0.5 }
            expected.animationSpeed = 0.5
            XCTAssertEqual(LidEffectPreferences(defaults: defaults).configuration, expected)
        }
    }

    func testAnimationSpeedRoundTripsWithoutChangingLegacySmoothing() throws {
        try withDefaults { defaults in
            let preferences = LidEffectPreferences(defaults: defaults)
            preferences.update { $0.smoothingFrames = 30 }
            for speed in [0.25, 1, 2] {
                preferences.update { $0.animationSpeed = speed }
                let reloaded = LidEffectPreferences(defaults: defaults).configuration
                XCTAssertEqual(reloaded.animationSpeed, speed)
                XCTAssertEqual(reloaded.smoothingFrames, 30)
            }
        }
    }

    func testRecommendedPresetPreservesOptInCalibrationAndUnrelatedSettings() throws {
        try withDefaults { defaults in
            defaults.set("keep", forKey: "unrelated")
            let preferences = LidEffectPreferences(defaults: defaults)
            for enabled in [false, true] {
                preferences.update {
                    $0.isEnabled = enabled
                    $0.referenceAngle = 125
                    $0.sensitivity = 3
                    $0.smoothingFrames = 30
                    $0.animationSpeed = 2
                    $0.darkness = 0.9
                    $0.holdsUntilReopened = true
                }
                preferences.applyRecommended()
                var expected = LidEffectConfiguration()
                expected.isEnabled = enabled
                expected.referenceAngle = 125
                XCTAssertEqual(preferences.configuration, expected)
                XCTAssertEqual(LidEffectPreferences(defaults: defaults).configuration, expected)
                XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
                let count = defaults.writes
                preferences.applyRecommended()
                XCTAssertEqual(defaults.writes, count)
            }
        }
    }
}
