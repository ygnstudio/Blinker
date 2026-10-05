import AppKit
@testable import BlinkerCore
import ObjectiveC
import XCTest

@MainActor
final class DockClickAdmissionTests: XCTestCase {
    func testCompletedMouseUpSurvivesLaggingGlobalButtonState() throws {
        let (gesture, candidate) = try completedClick()
        try withPressedButtons(1) {
            XCTAssertTrue(admits(candidate, isCurrent: gesture.ticket == candidate.ticket),
                          "A validated mouse-up must not be rejected by the lagging global button bitmap")
        }
    }

    func testNewPressOutsideDockInvalidatesCompletedClick() throws {
        var (gesture, candidate) = try completedClick()
        XCTAssertNil(gesture.begin(at: CGPoint(x: 500, y: 500), time: 100.15,
                                   frontmostPID: 42, isPlainSingleClick: true,
                                   candidateRegions: [CGRect(x: 0, y: 0, width: 100, height: 100)]))
        try withPressedButtons(0) {
            XCTAssertFalse(admits(candidate, isCurrent: gesture.ticket == candidate.ticket))
        }
    }

    func testInterruptionInvalidatesCompletedClick() throws {
        var (gesture, candidate) = try completedClick()
        // Right/other down, drag, modified input and stop use this same cancellation.
        gesture.cancel()
        try withPressedButtons(0) {
            XCTAssertFalse(admits(candidate, isCurrent: gesture.ticket == candidate.ticket))
        }
    }

    func testExpiredAndFutureCompletedClicksRemainRejected() throws {
        let (_, candidate) = try completedClick()
        try withPressedButtons(0) {
            XCTAssertTrue(admits(candidate, uptime: 100.2))
            XCTAssertFalse(admits(candidate, uptime: 101.1))
            XCTAssertFalse(admits(candidate, uptime: 100))
        }
    }

    func testInactiveAndUntrustedClicksRemainRejected() throws {
        let (_, candidate) = try completedClick()
        try withPressedButtons(0) {
            XCTAssertTrue(admits(candidate))
            XCTAssertFalse(admits(candidate, isActive: false))
            XCTAssertFalse(admits(candidate, isTrusted: false))
        }
    }

    private func completedClick() throws -> (DockClickGesture, DockClickCandidate) {
        var gesture = DockClickGesture()
        let point = CGPoint(x: 40, y: 50)
        let ticket = try XCTUnwrap(gesture.begin(at: point, time: 100, frontmostPID: 42,
                                                 isPlainSingleClick: true))
        gesture.snapshot([11], for: ticket)
        let hit = DockClickHit(applicationURL: URL(fileURLWithPath: "/Applications/Example.app"),
                               frame: CGRect(x: 20, y: 20, width: 60, height: 60))
        XCTAssertNil(gesture.resolve(hit, for: ticket))
        let candidate = try XCTUnwrap(gesture.end(at: point, time: 100.1, isPlainSingleClick: true))
        return (gesture, candidate)
    }

    private func admits(_ candidate: DockClickCandidate, isActive: Bool = true,
                        isCurrent: Bool = true, isTrusted: Bool = true,
                        uptime: TimeInterval = 100.2) -> Bool {
        DockClickController.acceptsCompletedClick(candidate, isActive: isActive,
                                                  isCurrent: isCurrent, isTrusted: isTrusted, uptime: uptime)
    }

    /// This synchronous main-actor scope changes only the test process's getter.
    /// It neither posts input nor changes the system button state. Always restore
    /// before returning so subsequent tests cannot observe the replacement.
    private func withPressedButtons(_ value: UInt, perform body: () -> Void) throws {
        let method = try XCTUnwrap(class_getClassMethod(NSEvent.self,
                                                        NSSelectorFromString("pressedMouseButtons")))
        let getter: @convention(block) (AnyObject) -> UInt = { _ in value }
        let replacement = imp_implementationWithBlock(getter)
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        XCTAssertEqual(UInt(NSEvent.pressedMouseButtons), value)
        body()
    }
}
