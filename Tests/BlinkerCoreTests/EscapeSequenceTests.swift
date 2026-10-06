@testable import BlinkerCore
import XCTest

final class EscapeSequenceTests: XCTestCase {
    func testSinglePressTriggersImmediatelyForDisplayMode() {
        var sequence = EscapeSequence(threshold: 1, window: 0)
        XCTAssertTrue(sequence.record(now: 100))
    }

    func testTriplePressInsideWindowTriggersForKeyboardMode() {
        var sequence = EscapeSequence(threshold: 3, window: 1.5)
        XCTAssertFalse(sequence.record(now: 10.0))
        XCTAssertFalse(sequence.record(now: 10.6))
        XCTAssertTrue(sequence.record(now: 11.4))
    }

    func testSlowPressesOutsideWindowDoNotTrigger() {
        var sequence = EscapeSequence(threshold: 3, window: 1.5)
        XCTAssertFalse(sequence.record(now: 0))
        XCTAssertFalse(sequence.record(now: 2.0))
        XCTAssertFalse(sequence.record(now: 4.0))
        XCTAssertFalse(sequence.record(now: 6.0))
    }

    func testTriggerResetsSoSequenceCanFireAgain() {
        var sequence = EscapeSequence(threshold: 3, window: 1.5)
        _ = sequence.record(now: 0)
        _ = sequence.record(now: 0.2)
        XCTAssertTrue(sequence.record(now: 0.4))
        XCTAssertFalse(sequence.record(now: 0.6))
        XCTAssertFalse(sequence.record(now: 0.8))
        XCTAssertTrue(sequence.record(now: 1.0))
    }
}
