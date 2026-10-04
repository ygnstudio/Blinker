@testable import BlinkerApp
import CoreVideo
import XCTest

final class LidEffectFrameStateTests: XCTestCase {
    func testCaptureKeepsOnlyLatestFrameAndBindsItsStream() throws {
        let state = LidEffectFrameState()
        let first = try buffer()
        let latest = try buffer()
        let source = NSObject()
        let foreign = NSObject()
        state.accept(first, stream: ObjectIdentifier(source))
        XCTAssertNil(state.frame())
        XCTAssertTrue(state.start())
        XCTAssertTrue(try XCTUnwrap(state.frame()).buffer === first)
        state.accept(latest, stream: ObjectIdentifier(source))
        state.accept(first, stream: ObjectIdentifier(foreign))
        XCTAssertTrue(try XCTUnwrap(state.frame()).buffer === latest)
    }

    func testStopDropsFramesAndInvalidatesInflightCompletionsPermanently() throws {
        let state = LidEffectFrameState()
        let source = NSObject()
        let input = try buffer()
        XCTAssertTrue(state.start())
        state.accept(input, stream: ObjectIdentifier(source))
        let ticket = try XCTUnwrap(state.frame()).generation
        XCTAssertTrue(state.requestDraw())
        state.stop()
        state.accept(input, stream: ObjectIdentifier(source))
        XCTAssertFalse(state.start())
        XCTAssertFalse(state.markPresented(ticket))
        XCTAssertFalse(state.requestDraw())
        XCTAssertNil(state.frame())
        XCTAssertNil(state.fail(ticket: ticket))
    }

    func testOnlyFirstCurrentGPUCompletionCanRevealTheOverlay() throws {
        let state = LidEffectFrameState()
        let source = NSObject()
        XCTAssertTrue(state.start())
        try state.accept(buffer(), stream: ObjectIdentifier(source))
        let ticket = try XCTUnwrap(state.frame()).generation
        XCTAssertFalse(state.markPresented(UUID()))
        XCTAssertTrue(state.markPresented(ticket))
        XCTAssertFalse(state.markPresented(ticket))
    }

    func testFailureIsSingleShotAndStopCancelsItsPendingDelivery() throws {
        let state = LidEffectFrameState()
        let source = NSObject()
        let foreign = NSObject()
        XCTAssertTrue(state.start())
        try state.accept(buffer(), stream: ObjectIdentifier(source))
        XCTAssertNil(state.fail(stream: ObjectIdentifier(foreign)))
        XCTAssertNil(state.fail(ticket: UUID()))
        let failure = try XCTUnwrap(state.fail(stream: ObjectIdentifier(source)))
        XCTAssertTrue(state.isFailureCurrent(failure))
        XCTAssertNil(state.frame())
        XCTAssertFalse(state.start())
        XCTAssertNil(state.fail())
        state.stop()
        XCTAssertFalse(state.isFailureCurrent(failure))
    }

    func testDrawSchedulingIsBoundedUntilTheMainQueueConsumesIt() {
        let state = LidEffectFrameState()
        XCTAssertFalse(state.requestDraw())
        XCTAssertTrue(state.start())
        XCTAssertTrue(state.requestDraw())
        XCTAssertFalse(state.requestDraw())
        state.finishDraw()
        XCTAssertTrue(state.requestDraw())
        state.stop()
        state.finishDraw()
        XCTAssertFalse(state.requestDraw())
    }

    func testMotionUsesElapsedTimeInsteadOfDisplayRefreshRate() {
        var results = [Double]()
        for rate in [30, 60, 120] {
            var motion = LidEffectMotion()
            for _ in 0 ..< rate {
                _ = motion.advance(to: 1, elapsed: 1.0 / Double(rate), frames: 16)
            }
            results.append(motion.progress)
        }
        XCTAssertGreaterThan(results[0], 0.95)
        XCTAssertLessThan(results[0], 1)
        XCTAssertEqual(results[0], results[1], accuracy: 0.000001)
        XCTAssertEqual(results[1], results[2], accuracy: 0.000001)
    }

    func testExplicitResetAndUnsmoothedMotionAreImmediateAndFinite() {
        var motion = LidEffectMotion()
        XCTAssertEqual(motion.advance(to: 2, elapsed: .nan, frames: 1), 1)
        motion.reset()
        XCTAssertEqual(motion.progress, 0)
        XCTAssertEqual(motion.advance(to: 0.5, elapsed: 0, frames: 1), 0.5)
        XCTAssertEqual(motion.advance(to: 1, elapsed: .infinity, frames: 16), 0.5)
        XCTAssertEqual(motion.advance(to: .nan, elapsed: 1, frames: 16), 0)
    }

    func testAnimationSpeedScalesTransitionTimeAtDifferentRefreshRates() {
        var reference = LidEffectMotion()
        for _ in 0 ..< 30 {
            _ = reference.advance(to: 1, elapsed: 1.0 / 60, frames: 16)
        }
        for rate in [30, 60, 120] {
            for speed in [0.25, 0.5, 1, 2] {
                var motion = LidEffectMotion()
                let count = Int(Double(rate) / (2 * speed))
                for _ in 0 ..< count {
                    _ = motion.advance(to: 1, elapsed: 1.0 / Double(rate), frames: 16, speed: speed)
                }
                // 30 Hz at 200% has a half-frame remainder; account for that elapsed time.
                let remainder = 0.5 / speed - Double(count) / Double(rate)
                _ = motion.advance(to: 1, elapsed: remainder, frames: 16, speed: speed)
                XCTAssertEqual(motion.progress, reference.progress, accuracy: 0.000001)
            }
        }
    }

    func testSpeedAppliesToBothStrengtheningAndFadingWhileResetCancelsImmediately() {
        var slow = LidEffectMotion()
        var fast = LidEffectMotion()
        XCTAssertLessThan(slow.advance(to: 1, elapsed: 0.05, frames: 16, speed: 0.25),
                          fast.advance(to: 1, elapsed: 0.05, frames: 16, speed: 2))
        _ = slow.advance(to: 1, elapsed: 0, frames: 1)
        _ = fast.advance(to: 1, elapsed: 0, frames: 1)
        XCTAssertGreaterThan(slow.advance(to: 0.1, elapsed: 0.05, frames: 16, speed: 0.25),
                             fast.advance(to: 0.1, elapsed: 0.05, frames: 16, speed: 2))
        slow.reset()
        XCTAssertEqual(slow.progress, 0)
    }

    func testInvalidSpeedIsBoundedAndLegacyImmediateMotionCanBeSlowed() {
        var reference = LidEffectMotion()
        let normal = reference.advance(to: 1, elapsed: 0.05, frames: 16)
        for invalid in [Double.nan, .infinity, -.infinity] {
            var motion = LidEffectMotion()
            XCTAssertEqual(motion.advance(to: 1, elapsed: 0.05, frames: 16, speed: invalid), normal)
        }
        var slow = LidEffectMotion()
        let value = slow.advance(to: 1, elapsed: 0.01, frames: 1, speed: 0)
        XCTAssertGreaterThan(value, 0)
        XCTAssertLessThan(value, 1)
        var fast = LidEffectMotion()
        XCTAssertEqual(fast.advance(to: 1, elapsed: 0.05, frames: 1, speed: 999), 1)
    }

    func testZeroTargetRendersIntermediateFramesBeforeFinishing() {
        var motion = LidEffectMotion()
        _ = motion.advance(to: 0.8, elapsed: 0, frames: 1)
        let first = motion.advance(to: 0, elapsed: 1.0 / 60, frames: 16)
        XCTAssertGreaterThan(first, 0, "A normal ending must not remove the last visible effect immediately")
        XCTAssertLessThan(first, 0.8)
        var previous = first
        for _ in 0 ..< 120 {
            let next = motion.advance(to: 0, elapsed: 1.0 / 60, frames: 16)
            XCTAssertLessThanOrEqual(next, previous)
            previous = next
        }
        XCTAssertEqual(motion.progress, 0)
    }

    func testZeroTargetUsesSpeedAndFinishesWithinTwoSecondsAtEveryRefreshRate() {
        var slow = LidEffectMotion()
        var fast = LidEffectMotion()
        _ = slow.advance(to: 0.8, elapsed: 0, frames: 1)
        _ = fast.advance(to: 0.8, elapsed: 0, frames: 1)
        XCTAssertGreaterThan(slow.advance(to: 0, elapsed: 0.05, frames: 16, speed: 0.25),
                             fast.advance(to: 0, elapsed: 0.05, frames: 16, speed: 2))
        for rate in [30, 60, 120] {
            for frames in [1, 16, 30] {
                for speed in [0.25, 1, 2] {
                    var motion = LidEffectMotion()
                    _ = motion.advance(to: 0.8, elapsed: 0, frames: 1)
                    let first = motion.advance(to: 0, elapsed: 1.0 / Double(rate),
                                               frames: frames, speed: speed)
                    XCTAssertGreaterThan(first, 0)
                    for _ in 0 ..< rate * 2 {
                        _ = motion.advance(to: 0, elapsed: 1.0 / Double(rate), frames: frames, speed: speed)
                    }
                    XCTAssertEqual(
                        motion.progress,
                        0,
                        "Ending must reach exact zero without an exponential tail"
                    )
                }
            }
        }
    }

    func testPositiveTargetInterruptsEndingFromItsCurrentValue() {
        var motion = LidEffectMotion()
        _ = motion.advance(to: 0.8, elapsed: 0, frames: 1)
        let partial = motion.advance(to: 0, elapsed: 0.1, frames: 30)
        XCTAssertGreaterThan(partial, 0)
        XCTAssertLessThan(partial, 0.8)
        XCTAssertEqual(motion.advance(to: 0.9, elapsed: 0, frames: 30), partial)
        XCTAssertGreaterThan(motion.advance(to: 0.9, elapsed: 1.0 / 60, frames: 30), partial)
    }

    func testOpeningSeedUsesItsFirstFrameAndReusedOpeningKeepsVisibleStrength() {
        var motion = LidEffectMotion(progress: 0.7)
        XCTAssertEqual(motion.advance(to: 0, elapsed: 0.1, frames: 30), 0.7)
        let partial = motion.advance(to: 0, elapsed: 0.1, frames: 30)
        XCTAssertGreaterThan(partial, 0)
        XCTAssertLessThan(partial, 0.7)
        motion.beginOpening(at: 0.9)
        XCTAssertEqual(motion.advance(to: 0, elapsed: 0, frames: 30), partial,
                       "An interrupted ending must not jump back to the opening seed")
        XCTAssertEqual(motion.advance(to: 0, elapsed: 2, frames: 30, speed: 0.25), 0)
        motion.beginOpening(at: 0.6)
        XCTAssertEqual(motion.advance(to: 0, elapsed: 0.1, frames: 30), 0.6)
        motion.reset()
        XCTAssertEqual(motion.advance(to: 0, elapsed: 0, frames: 30), 0)
    }

    func testEndingConsumesActualElapsedTimeAndCannotBeExtendedByRepeatedZeroTargets() {
        var motion = LidEffectMotion()
        _ = motion.advance(to: 0.8, elapsed: 0, frames: 1)
        XCTAssertGreaterThan(motion.advance(to: 0, elapsed: 0.01, frames: 30, speed: 0.25), 0)
        XCTAssertEqual(motion.advance(to: 0, elapsed: 2, frames: 30, speed: 0.25), 0,
                       "A delayed draw must not restart or stretch the ending")
    }

    func testSettlementWaitsForZeroGPUCompletionAndDeliversOnlyOnce() throws {
        let state = LidEffectFrameState()
        let source = NSObject()
        XCTAssertTrue(state.start())
        try state.accept(buffer(), stream: ObjectIdentifier(source))
        let generation = try XCTUnwrap(state.frame()).generation
        state.setTarget(isZero: true)
        XCTAssertNil(state.settlementTicket(renderedProgress: 0.01))
        let ticket = try XCTUnwrap(state.settlementTicket(renderedProgress: 0))
        state.setTarget(isZero: true)
        XCTAssertEqual(state.settlementTicket(renderedProgress: 0), ticket)
        XCTAssertTrue(state.markPresented(generation))
        XCTAssertTrue(state.markSettled(ticket, generation: generation),
                      "Settlement is independent of the one-time first-frame callback")
        XCTAssertFalse(state.markSettled(ticket, generation: generation))
        XCTAssertNil(state.settlementTicket(renderedProgress: 0))
    }

    func testNewPositiveTargetAndOpeningSeedRejectOldZeroFrameCompletions() throws {
        let state = LidEffectFrameState()
        let source = NSObject()
        XCTAssertTrue(state.start())
        try state.accept(buffer(), stream: ObjectIdentifier(source))
        let generation = try XCTUnwrap(state.frame()).generation
        state.setTarget(isZero: true)
        let first = try XCTUnwrap(state.settlementTicket(renderedProgress: 0))
        state.setTarget(isZero: false)
        XCTAssertFalse(state.markSettled(first, generation: generation))
        XCTAssertNil(state.settlementTicket(renderedProgress: 0))
        state.setTarget(isZero: true)
        let second = try XCTUnwrap(state.settlementTicket(renderedProgress: 0))
        state.setTarget(isZero: true, beginsNewMotion: true)
        let current = try XCTUnwrap(state.settlementTicket(renderedProgress: 0))
        XCTAssertNotEqual(second, current)
        XCTAssertFalse(state.markSettled(second, generation: generation))
        XCTAssertFalse(state.markSettled(current, generation: UUID()))
        XCTAssertTrue(state.markSettled(current, generation: generation))
    }

    func testStopAndFailurePreventLateSettlementOrSeedRevival() throws {
        for failFirst in [false, true] {
            let state = LidEffectFrameState()
            let source = NSObject()
            XCTAssertTrue(state.start())
            try state.accept(buffer(), stream: ObjectIdentifier(source))
            let generation = try XCTUnwrap(state.frame()).generation
            state.setTarget(isZero: true)
            let ticket = try XCTUnwrap(state.settlementTicket(renderedProgress: 0))
            if failFirst {
                XCTAssertNotNil(state.fail(ticket: generation))
            } else {
                state.stop()
            }
            state.setTarget(isZero: true, beginsNewMotion: true)
            XCTAssertFalse(state.markSettled(ticket, generation: generation))
            XCTAssertNil(state.settlementTicket(renderedProgress: 0))
            XCTAssertFalse(state.start())
        }
    }

    private func buffer() throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA,
                                           nil, &result), kCVReturnSuccess)
        return try XCTUnwrap(result)
    }
}
