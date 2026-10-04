@testable import BlinkerCore
import XCTest

@MainActor
final class WindowMinimizationConfirmationTests: XCTestCase {
    func testAXSuccessWithInitiallyStaleStateEventuallyConfirmsOwnership() {
        var clock: TimeInterval = 0
        var reads = 0
        let confirmed = WindowMinimizationConfirmation.confirm(expected: true, reads: [{ _ in
            reads += 1
            return clock >= 0.1
        }], deadline: .init(now: { clock }), wait: { clock += $0 })
        XCTAssertEqual(confirmed, [0])
        XCTAssertGreaterThan(reads, 1, "An immediate read is not the final state of an accepted request")
    }

    func testManyWindowAnimationsShareOneConfirmationDeadline() {
        var clock: TimeInterval = 0
        let reads: [(TimeInterval) -> Bool?] = (0 ..< 20).map { _ in { _ in clock >= 0.1 } }
        let confirmed = WindowMinimizationConfirmation.confirm(expected: true, reads: reads,
                                                               deadline: .init(now: { clock }),
                                                               wait: { clock += $0 })
        XCTAssertEqual(confirmed, Set(0 ..< 20))
        XCTAssertLessThan(clock, 0.15, "Do not wait for each animation serially")
    }

    func testAXConfirmationStopsAtDeadlineAndDoesNotTreatUnavailableAsRestored() {
        var clock: TimeInterval = 0
        var reads = 0
        let confirmed = WindowMinimizationConfirmation.confirm(expected: false, reads: [{ _ in
            reads += 1
            return nil
        }], deadline: .init(now: { clock }), wait: { clock += $0 })
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertLessThanOrEqual(reads, WindowMinimizationConfirmation.maximumReads)
        XCTAssertLessThanOrEqual(clock, WindowMinimizationConfirmation.timeout)
    }

    func testSlowAXReadsConsumeOneSharedDeadline() {
        var clock: TimeInterval = 0
        var count = 0
        let reads: [(TimeInterval) -> Bool?] = (0 ..< 100).map { _ in { timeout in
            clock += timeout
            count += 1
            return false
        } }
        let confirmed = WindowMinimizationConfirmation.confirm(expected: true, reads: reads,
                                                               deadline: .init(time: 0.6, now: { clock }),
                                                               wait: { clock += $0 })
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertLessThanOrEqual(count, 16)
        XCTAssertLessThan(clock, 0.65)
    }

    func testBackwardClockStillHasBoundedReadAttempts() {
        var clock: TimeInterval = 1
        var reads = 0
        let confirmed = WindowMinimizationConfirmation.confirm(expected: true, reads: [{ _ in
            reads += 1
            return false
        }], deadline: .init(now: { clock }), wait: { _ in clock -= 1 })
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertEqual(reads, WindowMinimizationConfirmation.maximumReads)
    }

    func testDockRestoreAnimationUnavailableForEightTenthsThenConfirms() {
        var clock: TimeInterval = 0
        let confirmed = WindowMinimizationConfirmation.confirm(expected: false, reads: [{ timeout in
            if clock < 0.8 {
                clock += timeout // AX cannotComplete consumes its IPC timeout during Dock animation.
                return nil
            }
            return false
        }], deadline: .init(now: { clock }), wait: { clock += $0 })
        XCTAssertEqual(confirmed, [0])
        XCTAssertGreaterThanOrEqual(clock, 0.8)
        XCTAssertLessThan(clock, 1, "Return immediately after the actual restore finishes")
    }

    func testExpiredDeadlineNeverStartsAXOrNativeReads() async {
        let deadline = WindowMinimizationConfirmation.Deadline(time: 5, now: { 5 })
        let confirmed = WindowMinimizationConfirmation.confirm(expected: false, reads: [{ _ in
            XCTFail("Do not issue AX IPC after the shared operation deadline")
            return false
        }], deadline: deadline)
        let native = await WindowMinimizationConfirmation.native(expected: false, reads: [{
            XCTFail("Native confirmation must not start a fresh timeout")
            return false
        }], isCurrent: { true }, deadline: deadline)
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertTrue(native.confirmed.isEmpty)
    }

    func testIPCReadTimeoutCannotExceedRemainingOperationBudget() {
        var clock: TimeInterval = 9.99
        var observed: TimeInterval = 0
        let confirmed = WindowMinimizationConfirmation.confirm(expected: true, reads: [{ timeout in
            observed = timeout
            clock += timeout
            return nil
        }], deadline: .init(time: 10, now: { clock }), wait: { clock += $0 })
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertEqual(observed, 0.01, accuracy: 0.0001)
        XCTAssertEqual(clock, 10, accuracy: 0.0001)
    }

    func testNativeMinimizeYieldsThenConfirmsBothWindowsTogether() async {
        var clock: TimeInterval = 0
        var isMinimized = false
        var waits = 0
        let result = await WindowMinimizationConfirmation.native(
            expected: true, reads: [{ isMinimized }, { isMinimized }], isCurrent: { true },
            deadline: .init(now: { clock }), wait: {
                waits += 1
                clock += $0
                isMinimized = true
            }
        )
        XCTAssertEqual(result.confirmed, [0, 1])
        XCTAssertTrue(result.pending.isEmpty)
        XCTAssertEqual(waits, 1, "Native windows must yield the main actor to finish miniaturizing")
    }

    func testNativeRestoreWaitsForDeminiaturization() async {
        var clock: TimeInterval = 0
        let result = await WindowMinimizationConfirmation.native(
            expected: false, reads: [{ clock < 0.1 }], isCurrent: { true },
            deadline: .init(now: { clock }), wait: { clock += $0 }
        )
        XCTAssertEqual(result.confirmed, [0])
        XCTAssertTrue(result.pending.isEmpty)
    }

    func testNativeSpaceInvalidationNeverAcceptsLateOwnership() async {
        var clock: TimeInterval = 0
        var current = true
        var reads = 0
        let result = await WindowMinimizationConfirmation.native(
            expected: true, reads: [{ reads += 1; return clock > 0 }], isCurrent: { current },
            deadline: .init(now: { clock }), wait: { clock += $0; current = false }
        )
        XCTAssertTrue(result.confirmed.isEmpty)
        XCTAssertEqual(reads, 1)
    }

    func testNativeClosedWindowIsDroppedAndTimeoutDoesNotClaimSuccess() async {
        var clock: TimeInterval = 0
        let result = await WindowMinimizationConfirmation.native(
            expected: true, reads: [{ nil }, { false }], isCurrent: { true },
            deadline: .init(now: { clock }), wait: { clock += $0 }
        )
        XCTAssertTrue(result.confirmed.isEmpty)
        XCTAssertEqual(result.pending, [1])
        XCTAssertLessThanOrEqual(clock, WindowMinimizationConfirmation.timeout)
    }
}
