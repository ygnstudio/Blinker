@testable import BlinkerCore
import CoreGraphics
import XCTest

final class TrafficLightPressStateTests: XCTestCase {
    private let bounds = CGRect(x: -1200, y: -600, width: 14, height: 14)
    private let inside = CGPoint(x: -1193, y: -593)
    private let outside = CGPoint(x: -1160, y: -560)

    private func press(pid: Int32 = 42) -> TrafficLightPressState.Pending {
        .init(bounds: bounds,
              windowHit: AXQuery.WindowHit(processIdentifier: pid,
                                           bounds: CGRect(x: -1220, y: -620, width: 900, height: 700)),
              shortAction: .closeWindow, longAction: .quitApp)
    }

    func testDraggingOutPermanentlyCancelsActionsButConsumesMatchingUp() {
        for reachDeadline in [false, true] {
            var state = TrafficLightPressState()
            let pending = press()
            state.begin(pending)
            XCTAssertTrue(state.drag(to: outside))
            XCTAssertTrue(state.drag(to: inside), "Re-entering must not start a new hold")
            if reachDeadline {
                XCTAssertNil(state.deadline(for: pending.id, at: inside))
            }
            let release = state.release(at: inside)
            XCTAssertTrue(release.swallowed)
            XCTAssertNil(release.invocation)
            XCTAssertFalse(state.release(at: inside).swallowed)
        }
    }

    func testReleaseOutsideCancelsShortActionEvenWithoutDragEvent() {
        var state = TrafficLightPressState()
        let pending = press()
        state.begin(pending)
        let release = state.release(at: outside)
        XCTAssertTrue(release.swallowed)
        XCTAssertNil(release.invocation)
        XCTAssertNil(state.deadline(for: pending.id, at: inside))
    }

    func testDeadlineRequiresCurrentPointerInsideOriginalBounds() {
        for point in [outside, nil] as [CGPoint?] {
            var state = TrafficLightPressState()
            let pending = press()
            state.begin(pending)
            XCTAssertNil(state.deadline(for: pending.id, at: point))
            let release = state.release(at: inside)
            XCTAssertTrue(release.swallowed)
            XCTAssertNil(release.invocation)
        }
    }

    func testOldDeadlineCannotFireOrCancelANewPress() {
        var state = TrafficLightPressState()
        let old = press(pid: 41)
        state.begin(old)
        XCTAssertEqual(state.release(at: inside).invocation?.windowHit.processIdentifier, 41)
        let current = press(pid: 42)
        state.begin(current)
        XCTAssertNil(state.deadline(for: old.id, at: inside))
        XCTAssertNil(state.deadline(for: old.id, at: outside))
        let invocation = state.deadline(for: current.id, at: inside)
        XCTAssertEqual(invocation?.action, .quitApp)
        XCTAssertEqual(invocation?.windowHit.processIdentifier, 42)
        XCTAssertNil(state.deadline(for: current.id, at: inside))
        XCTAssertNil(state.release(at: inside).invocation)
    }

    func testInsideShortAndLongPressEachExecuteExactlyOnce() {
        var state = TrafficLightPressState()
        let short = press()
        state.begin(short)
        XCTAssertEqual(state.release(at: inside).invocation?.action, .closeWindow)
        XCTAssertNil(state.deadline(for: short.id, at: inside))

        let long = press()
        state.begin(long)
        XCTAssertTrue(state.drag(to: inside))
        XCTAssertEqual(state.deadline(for: long.id, at: inside)?.action, .quitApp)
        XCTAssertNil(state.deadline(for: long.id, at: inside))
        let release = state.release(at: inside)
        XCTAssertTrue(release.swallowed)
        XCTAssertNil(release.invocation)
    }

    func testUnmappedAndImmediateClicksKeepTheirRoutingAndResetDropsPendingHold() {
        var state = TrafficLightPressState()
        XCTAssertFalse(state.drag(to: inside))
        XCTAssertFalse(state.release(at: inside).swallowed)

        state.begin(nil) // The existing immediate action already ran on mouse-down.
        XCTAssertFalse(state.drag(to: outside))
        let immediate = state.release(at: outside)
        XCTAssertTrue(immediate.swallowed)
        XCTAssertNil(immediate.invocation)

        let pending = press()
        state.begin(pending)
        state.reset()
        XCTAssertNil(state.deadline(for: pending.id, at: inside))
        XCTAssertFalse(state.release(at: inside).swallowed)
    }
}
