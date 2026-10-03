@testable import BlinkerApp
import BlinkerCore
import XCTest

final class WindowBrowserOperationStateTests: XCTestCase {
    func testAnInFlightActionRejectsRepeatedAndDifferentSubmissions() throws {
        var state = WindowBrowserOperationState()
        let session = UUID()
        let window = UUID()
        let first = try XCTUnwrap(state.begin(.closeWindow, windowID: window, sessionID: session))

        XCTAssertNil(state.begin(.closeWindow, windowID: window, sessionID: session))
        XCTAssertNil(state.begin(.minimize, windowID: UUID(), sessionID: session))
        XCTAssertEqual(state.current, first)

        XCTAssertTrue(state.finish(first))
        XCTAssertNil(state.current)
        XCTAssertNotNil(state.begin(.minimize, windowID: window, sessionID: session))
    }

    func testOldCompletionCannotClearFeedbackAfterDismissAndReopen() throws {
        var state = WindowBrowserOperationState()
        let window = UUID()
        let old = try XCTUnwrap(state.begin(.minimize, windowID: window, sessionID: UUID()))
        state.reset()
        XCTAssertNil(state.current)

        let current = try XCTUnwrap(state.begin(.minimize, windowID: window, sessionID: UUID()))
        XCTAssertFalse(state.finish(old))
        XCTAssertEqual(state.current, current)
        XCTAssertTrue(state.finish(current))
        XCTAssertNil(state.current)
    }

    func testAnEarlierCompletionCannotClearARepeatedActionInTheSameSession() throws {
        var state = WindowBrowserOperationState()
        let session = UUID()
        let window = UUID()
        let first = try XCTUnwrap(state.begin(.centerWindow, windowID: window, sessionID: session))
        XCTAssertTrue(state.finish(first))

        let next = try XCTUnwrap(state.begin(.centerWindow, windowID: window, sessionID: session))
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertFalse(state.finish(first))
        XCTAssertEqual(state.current, next)
    }
}
