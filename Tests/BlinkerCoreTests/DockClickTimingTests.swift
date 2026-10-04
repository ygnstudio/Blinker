@testable import BlinkerCore
import CoreGraphics
import XCTest

final class DockClickTimingTests: XCTestCase {
    private let hit = DockClickHit(applicationURL: URL(fileURLWithPath: "/Applications/Example.app"),
                                   frame: CGRect(x: 0, y: 0, width: 100, height: 100))

    func testDifferentEventEpochDoesNotExpireARealFreshClick() throws {
        // Recorded from the failing Dock click: hardware/synthesized event time
        // was 2570 seconds, while the local receipt clock was 107115 seconds.
        let down = try input(timestamp: 2_570_771_278_629, receipt: 107_115.494)
        let released = try input(timestamp: 2_570_774_329_810, receipt: 107_115.611)
        var gesture = DockClickGesture()
        let ticket = try XCTUnwrap(gesture.begin(at: down.point, time: down.receivedAt,
                                                 frontmostPID: 42, isPlainSingleClick: true))
        gesture.snapshot([11], for: ticket)
        XCTAssertNil(gesture.resolve(hit, for: ticket))
        let candidate = try XCTUnwrap(gesture.end(at: released.point, time: released.receivedAt,
                                                  isPlainSingleClick: true))
        XCTAssertEqual(candidate.releasedAt, 107_115.611)
        XCTAssertTrue(candidate.isFresh(at: 107_115.624))
        XCTAssertFalse(candidate.isFresh(at: 107_116.611))
    }

    func testFreshnessRejectsExpiredFutureAndNonfiniteReceiptTimes() {
        let candidate = DockClickCandidate(ticket: UUID(), applicationURL: hit.applicationURL,
                                           frontmostPIDAtDown: 42, eligibleWindowIDs: [11], releasedAt: 100)
        XCTAssertTrue(candidate.isFresh(at: 100))
        XCTAssertTrue(candidate.isFresh(at: 100.99))
        let invalid: [TimeInterval] = [99, 101, 110, .nan, .infinity, -.infinity]
        for now in invalid {
            XCTAssertFalse(candidate.isFresh(at: now), "Invalid local time: \(now)")
        }
    }

    func testLongPressUsesReceiptDurationEvenWhenEventClockBarelyMoves() throws {
        let down = try input(timestamp: 2_570_771_278_629, receipt: 107_115.494)
        let released = try input(timestamp: 2_570_774_329_810, receipt: 107_116.494)
        var gesture = DockClickGesture()
        let ticket = try XCTUnwrap(gesture.begin(at: down.point, time: down.receivedAt,
                                                 frontmostPID: 42, isPlainSingleClick: true))
        gesture.snapshot([11], for: ticket)
        XCTAssertNil(gesture.resolve(hit, for: ticket))
        XCTAssertNil(gesture.end(at: released.point, time: released.receivedAt, isPlainSingleClick: true))
        XCTAssertNotEqual(gesture.ticket, ticket)
    }

    func testFreshOldClickCannotResolveAfterAnotherPress() throws {
        let input = try input(timestamp: 17, receipt: 100)
        var gesture = DockClickGesture()
        let old = try XCTUnwrap(gesture.begin(at: input.point, time: input.receivedAt,
                                              frontmostPID: 42, isPlainSingleClick: true))
        XCTAssertNil(gesture.end(at: input.point, time: 100.1, isPlainSingleClick: true))
        XCTAssertNotNil(gesture.begin(at: input.point, time: 100.2,
                                      frontmostPID: 42, isPlainSingleClick: true))
        XCTAssertNil(gesture.resolve(hit, for: old))
    }

    private func input(timestamp: CGEventTimestamp, receipt: TimeInterval) throws -> DockClickEventInput {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                          mouseCursorPosition: CGPoint(x: 50, y: 50), mouseButton: .left))
        event.timestamp = timestamp
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        // This event is an in-memory object only; no tap, posting or user input.
        return DockClickEventInput(event, receivedAt: receipt)
    }
}
