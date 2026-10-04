@testable import BlinkerApp
import XCTest

final class LidEffectGestureTests: XCTestCase {
    private var enabled: LidEffectConfiguration {
        var value = LidEffectConfiguration()
        value.isEnabled = true
        // These regression trajectories exercise the original explicit settings.
        value.sensitivity = 3
        value.fullEffectSpan = 30
        return value
    }

    private struct Observation {
        let time: Double
        let angle: Double
        let progress: Double
        let openingSeed: Double?
    }

    private func replay(_ angles: [Double], interval: Double = 0.05,
                        configuration: LidEffectConfiguration? = nil) -> [Observation] {
        var gesture = LidEffectGesture()
        return angles.enumerated().map { index, angle in
            let time = Double(index) * interval
            let progress = gesture.update(angle: angle, time: time, configuration: configuration ?? enabled)
            return Observation(time: time, angle: angle, progress: progress,
                               openingSeed: gesture.openingStartProgress)
        }
    }

    @discardableResult
    private func activate(_ gesture: inout LidEffectGesture, angle: Double = 90,
                          configuration: LidEffectConfiguration? = nil) -> Double {
        let configuration = configuration ?? enabled
        _ = gesture.update(angle: 110, time: 0, configuration: configuration)
        _ = gesture.update(angle: angle, time: 0.05, configuration: configuration)
        return gesture.update(angle: angle, time: 0.2, configuration: configuration)
    }

    private func assertQuiet(
        _ observations: [Observation],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for value in observations {
            XCTAssertEqual(value.progress, 0, "Unexpected effect at \(value.time)", file: file, line: line)
            XCTAssertNil(value.openingSeed, "Unexpected opening at \(value.time)", file: file, line: line)
        }
    }

    func testOneDegreeJitterDoesNotStartEitherDirection() {
        for anchor in [80.0, 110.0] {
            let jitter = [anchor] + Array(repeating: [anchor - 1, anchor + 1, anchor], count: 30)
                .flatMap { $0 }
            assertQuiet(replay(jitter))
            // Rejecting noise must not lock out a subsequent deliberate gesture.
            let closing = (1 ... 12).map { anchor - Double($0) }
            XCTAssertGreaterThan(replay(jitter + closing).last!.progress, 0)
        }
    }

    func testConfiguredExcursionStillAppliesBelowReference() {
        var configuration = enabled
        configuration.sensitivity = 15
        let jitter = [80.0] + Array(repeating: [79.0, 81.0, 80.0], count: 20).flatMap { $0 }
        assertQuiet(replay(jitter, configuration: configuration))
        let closing = (1 ... 20).map { 80 - Double($0) }
        XCTAssertGreaterThan(replay(jitter + closing, configuration: configuration).last!.progress, 0)
    }

    func testSingleSampleSpikeDoesNotBecomeAReverseOpeningGesture() {
        for spike in [60.0, 100.0] {
            let readings = [80.0, spike] + Array(repeating: 80.0, count: 12)
            assertQuiet(replay(readings))
            let opening = (1 ... 12).map { 80 + Double($0) }
            XCTAssertTrue(replay(readings + opening).contains { $0.openingSeed != nil })
        }
    }

    func testOneQuantizedReverseDoesNotBlockFollowingRealClosing() throws {
        let angles = [110.0, 103, 104] + (1 ... 20).map { 104 - Double($0) * 2 }
        XCTAssertGreaterThan(try XCTUnwrap(replay(angles).last?.progress), 0)
    }

    func testSmallStepsAccumulateFromMovementStart() {
        let observations = replay((0 ... 28).map { 110 - Double($0) * 0.25 })
        XCTAssertEqual(observations[12].progress, 0)
        XCTAssertGreaterThan(observations[20].progress, 0)
    }

    func testCachedReadingsCannotStartOrConfirm() {
        var gesture = LidEffectGesture()
        _ = gesture.update(angle: 110, time: 0, configuration: enabled)
        XCTAssertEqual(
            gesture.update(angle: 90, time: 0.05, configuration: enabled, isFreshReading: false),
            0
        )
        XCTAssertEqual(gesture.update(angle: 90, time: 0.21, configuration: enabled), 0)
        XCTAssertEqual(gesture.update(angle: 90, time: 0.4, configuration: enabled, isFreshReading: false), 0)
        XCTAssertNil(gesture.openingStartProgress)
        XCTAssertGreaterThan(gesture.update(angle: 90, time: 0.45, configuration: enabled), 0)
    }

    func testAReadGapCannotConfirmASingleFreshStep() {
        var gesture = LidEffectGesture()
        _ = gesture.update(angle: 80, time: 0, configuration: enabled)
        XCTAssertEqual(gesture.update(angle: 100, time: 10, configuration: enabled), 0)
        XCTAssertNil(gesture.openingStartProgress)
    }

    func testFastOpeningBeyondReferenceStillProvidesObservedStart() {
        let observations = replay((0 ... 5).map { 80 + Double($0) * 8 })
        let seeded = observations.filter { $0.openingSeed != nil }
        XCTAssertEqual(seeded.count, 1)
        XCTAssertEqual(seeded.first?.openingSeed ?? -1, 0.9, accuracy: 0.0001)
        XCTAssertEqual(seeded.first?.progress, 0)
        XCTAssertGreaterThanOrEqual(seeded.first?.angle ?? 0, 107)
    }

    func testFastOpeningAtReportedSettingsDoesNotDisappear() {
        var configuration = enabled
        configuration.referenceAngle = 115
        configuration.fullEffectSpan = 75
        configuration.clearDelay = 0.2
        let observations = replay([90, 100, 110, 120, 130], configuration: configuration)
        let seeds = observations.compactMap(\.openingSeed)
        XCTAssertEqual(seeds.count, 1)
        XCTAssertEqual(seeds.first ?? -1, 22.0 / 75, accuracy: 0.0001)
    }

    func testOpeningSeedIsOneShotAndNeverInventsEffectAboveReference() {
        var gesture = LidEffectGesture()
        _ = gesture.update(angle: 80, time: 0, configuration: enabled)
        _ = gesture.update(angle: 90, time: 0.05, configuration: enabled)
        _ = gesture.update(angle: 100, time: 0.2, configuration: enabled)
        XCTAssertEqual(gesture.openingStartProgress ?? -1, 0.9, accuracy: 0.0001)
        _ = gesture.update(angle: 100, time: 0.21, configuration: enabled, isFreshReading: false)
        XCTAssertNil(gesture.openingStartProgress)
        _ = gesture.update(angle: 105, time: 0.25, configuration: enabled)
        XCTAssertNil(gesture.openingStartProgress)
        assertQuiet(replay([120, 125, 130, 135, 140]))
    }

    func testContinuousClosingOpeningAcrossReferenceNeedsNoStablePause() {
        let closing = (0 ... 10).map { 130 - Double($0) * 5 }
        let opening = (1 ... 7).map { 80 + Double($0) * 5 }
        let nextClosing = (1 ... 11).map { 115 - Double($0) * 5 }
        let nextOpening = (1 ... 10).map { 60 + Double($0) * 5 }
        let observations = replay(closing + opening + nextClosing + nextOpening)
        XCTAssertTrue(observations[0 ..< 11].contains { $0.progress > 0 })
        XCTAssertTrue(observations[11 ..< 18].contains { $0.progress > 0 })
        XCTAssertTrue(observations[18 ..< 29].contains { $0.progress > 0 })
        XCTAssertTrue(observations[29...].contains { $0.progress > 0 })
    }

    func testSlowReversalWithQuantizedReadingsKeepsFollowingMotion() {
        for delay in [0.0, 0.2, 0.6] {
            var configuration = enabled
            configuration.clearDelay = delay
            let start = [110.0] + Array(repeating: 90.0, count: 5)
            let reverse = (6 ... 80).map { 90 + Double(($0 - 1) / 5) }
            let observations = replay(start + reverse, configuration: configuration)
            for observation in observations where observation.time >= 0.2 {
                XCTAssertGreaterThan(
                    observation.progress,
                    0,
                    "Slow reverse interrupted at \(observation.time)"
                )
            }
        }
    }

    func testStopThenOpenCanRearmWhileMoving() throws {
        let start = [110.0] + Array(repeating: 90.0, count: 18)
        let opening = (1 ... 16).map { 90 + Double($0) }
        let observations = replay(start + opening)
        XCTAssertEqual(observations[18].progress, 0)
        XCTAssertTrue(observations[19...].contains { $0.openingSeed != nil })
        XCTAssertGreaterThan(try XCTUnwrap(observations.last?.progress), 0)
    }

    func testSmallActiveReboundCannotKeepExtendingActivityOrRestart() {
        var configuration = enabled
        configuration.clearDelay = 0.2
        let initial = [110.0] + Array(repeating: 90.0, count: 5)
        let wobble = Array(repeating: [89.0, 91.0], count: 30).flatMap { $0 }
        let observations = replay(initial + wobble, configuration: configuration)
        for observation in observations where observation.time > 1 {
            XCTAssertEqual(observation.progress, 0)
            XCTAssertNil(observation.openingSeed)
        }
        let freshMotion = (1 ... 10).map { 91 - Double($0) }
        XCTAssertGreaterThan(
            replay(initial + wobble + freshMotion, configuration: configuration).last!.progress,
            0
        )
    }

    func testSlowOpeningAndClosingRemainActiveUntilActualStop() {
        for direction in [-1.0, 1.0] {
            var configuration = enabled
            configuration.clearDelay = 0
            let angles = (0 ... 20).map { 80 + Double($0) * direction }
            let observations = replay(angles, interval: 0.25, configuration: configuration)
            for observation in observations where observation.time >= 1 {
                XCTAssertGreaterThan(observation.progress, 0)
            }
            var gesture = LidEffectGesture()
            for (index, angle) in angles.enumerated() {
                _ = gesture.update(angle: angle, time: Double(index) * 0.25, configuration: configuration)
            }
            XCTAssertGreaterThan(
                gesture.update(angle: angles.last, time: 5.29, configuration: configuration),
                0
            )
            XCTAssertEqual(gesture.update(angle: angles.last, time: 5.31, configuration: configuration), 0)
        }
    }
}

extension LidEffectGestureTests {
    func testRecommendedDefaultsRejectTwoDegreeJitterAndAcceptDeliberateMotion() throws {
        var configuration = LidEffectConfiguration()
        configuration.isEnabled = true
        for anchor in [80.0, 110.0] {
            let jitter = [anchor] + Array(repeating: [anchor - 2, anchor + 2, anchor], count: 30)
                .flatMap { $0 }
            assertQuiet(replay(jitter, configuration: configuration))
            let closing = (1 ... 10).map { anchor - Double($0) }
            let continued = replay(jitter + closing, configuration: configuration)
            XCTAssertGreaterThan(try XCTUnwrap(continued.last?.progress), 0)
        }
        let opening = replay((0 ... 10).map { 80 + Double($0) }, configuration: configuration)
        XCTAssertGreaterThan(try XCTUnwrap(opening.last?.progress), 0)
        XCTAssertEqual(opening.compactMap(\.openingSeed).count, 1)
        let fastOpening = replay([80, 100, 120, 130, 135, 140], configuration: configuration)
        let seeds = fastOpening.compactMap(\.openingSeed)
        XCTAssertEqual(seeds.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(seeds.first), 0)
        XCTAssertEqual(fastOpening.last?.progress, 0)
    }

    func testIntegrationJitterClearAndLaterOpeningPreservesFirstTwoFreshReadings() {
        var configuration = enabled
        configuration.referenceAngle = 120
        configuration.clearDelay = 0.2
        var gesture = LidEffectGesture()
        @discardableResult
        func feed(_ angle: Double, _ time: Double, fresh: Bool = true) -> Double {
            gesture.update(angle: angle, time: time, configuration: configuration, isFreshReading: fresh)
        }
        feed(100, 0)
        for index in 1 ... 20 {
            XCTAssertEqual(
                feed(index.isMultiple(of: 2) ? 101 : 99, Double(index) * 0.05),
                0
            )
        }
        XCTAssertEqual(feed(90, 1.05), 0)
        XCTAssertEqual(feed(90, 1.21, fresh: false), 0)
        XCTAssertEqual(feed(90, 1.31, fresh: false), 0)
        XCTAssertGreaterThan(feed(90, 1.36), 0)
        XCTAssertEqual(feed(90, 1.7), 0)
        for index in 0 ... 30 {
            XCTAssertEqual(
                feed(index.isMultiple(of: 2) ? 91 : 89, 1.75 + Double(index) * 0.05),
                0
            )
        }
        XCTAssertEqual(feed(90, 3.3), 0)
        XCTAssertEqual(feed(90, 3.65), 0)
        XCTAssertEqual(feed(94, 3.7), 0)
        let opening = feed(94, 3.86)
        XCTAssertGreaterThan(opening, 0)
        XCTAssertNotNil(gesture.openingStartProgress)
        let continued = feed(97, 4.2)
        XCTAssertGreaterThan(continued, 0)
        XCTAssertLessThan(continued, opening)
    }

    func testSubthresholdCandidateCannotConsumeOppositeMovementBeyondOrigin() {
        for direction in [-1.0, 1.0] {
            var gesture = LidEffectGesture()
            _ = gesture.update(angle: 80, time: 0, configuration: enabled)
            XCTAssertEqual(gesture.update(angle: 80 - direction, time: 0.05, configuration: enabled), 0)
            XCTAssertEqual(gesture.update(angle: 80 + direction * 5, time: 0.1, configuration: enabled), 0)
            XCTAssertGreaterThan(
                gesture.update(angle: 80 + direction * 5, time: 0.26, configuration: enabled),
                0
            )
            if direction > 0 {
                XCTAssertEqual(gesture.openingStartProgress ?? -1, 0.9, accuracy: 0.0001)
            } else {
                XCTAssertNil(gesture.openingStartProgress)
            }
        }
    }

    func testReturningExcursionMayContinuePastTrustedOriginWithoutUsingSpikeForSeed() {
        for direction in [-1.0, 1.0] {
            for continuation in [0.0, 5.0] {
                var gesture = LidEffectGesture()
                _ = gesture.update(angle: 80, time: 0, configuration: enabled)
                _ = gesture.update(angle: 80 - direction * 20, time: 0.05, configuration: enabled)
                _ = gesture.update(angle: 80 - direction * 15, time: 0.1, configuration: enabled)
                XCTAssertEqual(
                    gesture.update(angle: 80 + direction * continuation, time: 0.15, configuration: enabled),
                    0
                )
                let result = gesture.update(
                    angle: 80 + direction * continuation,
                    time: 0.31,
                    configuration: enabled
                )
                if continuation == 0 {
                    XCTAssertEqual(result, 0)
                    XCTAssertNil(gesture.openingStartProgress)
                } else {
                    XCTAssertGreaterThan(result, 0)
                    if direction > 0 {
                        XCTAssertEqual(gesture.openingStartProgress ?? -1, 0.9, accuracy: 0.0001)
                    } else {
                        XCTAssertNil(gesture.openingStartProgress)
                    }
                }
            }
        }
    }

    func testConfirmedReverseWhileVisibleDoesNotSeedAgain() {
        var gesture = LidEffectGesture()
        XCTAssertGreaterThan(activate(&gesture, angle: 80), 0)
        for (index, angle) in [84.0, 85, 86, 87, 88].enumerated() {
            XCTAssertGreaterThan(gesture.update(angle: angle, time: 0.25 + Double(index) * 0.05,
                                                configuration: enabled), 0)
            XCTAssertNil(gesture.openingStartProgress)
        }
    }

    func testHoldPreservesStationaryEffectButReferenceReboundDoesNotReappear() {
        var configuration = enabled
        configuration.holdsUntilReopened = true
        var gesture = LidEffectGesture()
        let value = activate(&gesture, configuration: configuration)
        XCTAssertEqual(gesture.update(angle: 90, time: 60, configuration: configuration), value)
        XCTAssertEqual(gesture.update(angle: 108, time: 60.05, configuration: configuration), 0)
        for index in 0 ..< 20 {
            let angle = index.isMultiple(of: 2) ? 106.8 : 107.2
            XCTAssertEqual(gesture.update(angle: angle, time: 60.1 + Double(index) * 0.05,
                                          configuration: configuration), 0)
            XCTAssertNil(gesture.openingStartProgress)
        }
        XCTAssertEqual(gesture.update(angle: 102, time: 61.2, configuration: configuration), 0)
        XCTAssertGreaterThan(gesture.update(angle: 100, time: 61.4, configuration: configuration), 0)
    }

    func testFullyOpenTrackingPreservesNextClosingDirection() throws {
        let observations = replay([80, 130, 116, 106, 105, 104, 103, 102])
        XCTAssertGreaterThan(try XCTUnwrap(observations.last?.progress), 0)
    }

    func testClockRollbackClearsVisualSeedAndEstablishesNewBaseline() {
        var gesture = LidEffectGesture()
        _ = gesture.update(angle: 80, time: 100, configuration: enabled)
        _ = gesture.update(angle: 90, time: 100.05, configuration: enabled)
        _ = gesture.update(angle: 100, time: 100.2, configuration: enabled)
        XCTAssertNotNil(gesture.openingStartProgress)
        XCTAssertEqual(gesture.update(angle: 90, time: 1, configuration: enabled), 0)
        XCTAssertNil(gesture.openingStartProgress)
        XCTAssertEqual(gesture.update(angle: 89, time: 1.05, configuration: enabled), 0)
        XCTAssertEqual(gesture.update(angle: 86, time: 1.25, configuration: enabled), 0)
        XCTAssertGreaterThan(gesture.update(angle: 85, time: 1.3, configuration: enabled), 0)
    }

    func testInvalidReadingsAndCancellationClearAllMotionEvidence() {
        for invalid in [nil, Double.nan, .infinity, -1, 361] as [Double?] {
            var gesture = LidEffectGesture()
            _ = activate(&gesture)
            XCTAssertEqual(gesture.update(angle: invalid, time: 0.3, configuration: enabled), 0)
            XCTAssertNil(gesture.openingStartProgress)
            XCTAssertEqual(gesture.update(angle: 90, time: 0.4, configuration: enabled), 0)
            XCTAssertEqual(gesture.update(angle: 89, time: 0.45, configuration: enabled), 0)
            XCTAssertEqual(gesture.update(angle: 85, time: 0.65, configuration: enabled), 0)
            XCTAssertGreaterThan(gesture.update(angle: 84, time: 0.7, configuration: enabled), 0)
        }
        var gesture = LidEffectGesture()
        _ = activate(&gesture)
        gesture.reset()
        XCTAssertNil(gesture.openingStartProgress)
        XCTAssertEqual(gesture.update(angle: 80, time: 1, configuration: enabled), 0)
        XCTAssertEqual(gesture.update(angle: 70, time: 2, configuration: .init()), 0)
        XCTAssertEqual(gesture.update(angle: 60, time: .nan, configuration: enabled), 0)
    }
}
