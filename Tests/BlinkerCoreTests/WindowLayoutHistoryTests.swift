@testable import BlinkerCore
import CoreGraphics
import XCTest

final class WindowLayoutHistoryTests: XCTestCase {
    private let original = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let maximized = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testSecondMaximizeRestoresOnlyTheSameWindowAtItsAppliedFrame() {
        var history = WindowLayoutHistory<Int>()
        history.record(key: 1, action: .maximize, before: original, after: maximized)
        XCTAssertEqual(history.toggleFrame(for: 1, action: .maximize, current: maximized), original)
        XCTAssertNil(history.toggleFrame(for: 2, action: .maximize, current: maximized))
        XCTAssertNil(history.toggleFrame(for: 1, action: .maximize, current: original))
        XCTAssertNil(history.toggleFrame(for: 1, action: .almostMaximize, current: maximized))
        history.didRestore(1)
        XCTAssertNil(history.previousFrame(for: 1))
    }

    func testUndoWalksThroughDifferentLayoutActions() {
        var history = WindowLayoutHistory<Int>()
        let moved = maximized.offsetBy(dx: 1200, dy: 0)
        history.record(key: 1, action: .maximize, before: original, after: maximized)
        history.record(key: 1, action: .moveToNextDisplay, before: maximized, after: moved)
        XCTAssertEqual(history.previousFrame(for: 1), maximized)
        history.didRestore(1)
        XCTAssertEqual(history.previousFrame(for: 1), original)
        history.didRestore(1)
        XCTAssertNil(history.previousFrame(for: 1))
    }

    func testUnchangedFrameDoesNotConsumeUndoHistory() {
        var history = WindowLayoutHistory<Int>()
        history.record(key: 1, action: .centerWindow, before: original, after: original)
        XCTAssertNil(history.previousFrame(for: 1))
    }

    func testWindowAndPerWindowHistoryAreBounded() {
        var history = WindowLayoutHistory<Int>()
        for key in 0 ...
            128 {
            history.record(key: key, action: .maximize, before: original, after: maximized)
        }
        XCTAssertNil(history.previousFrame(for: 0))
        XCTAssertEqual(history.previousFrame(for: 128), original)
        for offset in 1 ... 20 {
            history.record(key: 500, action: .centerWindow, before: original,
                           after: original.offsetBy(dx: CGFloat(offset * 10), dy: 0))
        }
        for _ in 0 ..< 10 {
            history.didRestore(500)
        }
        XCTAssertNil(history.previousFrame(for: 500))
    }
}
