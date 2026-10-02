import ApplicationServices
@testable import BlinkerCore
import XCTest

final class OverlayPresentationStateTests: XCTestCase {
    func testDisplayedPaletteRetainsOwnerAboveAndLeftOfWindowIncludingPadding() {
        let state = OverlayPresentationState()
        let layout = layout(windowID: 1)
        XCTAssertTrue(state.publish(layout, revision: state.revision))
        for point in [CGPoint(x: 95, y: 95), CGPoint(x: 80, y: 90), CGPoint(x: 140, y: 110)] {
            XCTAssertEqual(state.displayedLayout(at: point)?.target.hit.windowID, 1)
        }
        XCTAssertNil(state.displayedLayout(at: CGPoint(x: 300, y: 300)))
        state.invalidate()
        XCTAssertNil(state.displayedLayout(at: CGPoint(x: 95, y: 95)))
    }

    func testRebuildingConsumedPresentationDoesNotDropNewHover() throws {
        let state = OverlayPresentationState()
        let revision = state.revision
        XCTAssertTrue(state.submit(presentation(windowID: 1, hoveredIndex: 0), revision: revision))
        let first = try XCTUnwrap(state.takePending())
        // AX detection delivers the next hover while main is building the first tray.
        XCTAssertTrue(state.submit(presentation(windowID: 2, hoveredIndex: 1), revision: revision))
        XCTAssertTrue(state.publish(first.presentation.layout, revision: first.revision))
        let latest = try XCTUnwrap(state.takePending())
        XCTAssertEqual(latest.presentation.layout.target.hit.windowID, 2)
        XCTAssertEqual(latest.presentation.hoveredIndex, 1)
    }

    func testHideRejectsInFlightDetectionAndRendering() throws {
        let state = OverlayPresentationState()
        let oldRevision = state.revision
        XCTAssertTrue(state.submit(presentation(windowID: 1), revision: oldRevision))
        let consumed = try XCTUnwrap(state.takePending())
        state.invalidate()
        XCTAssertFalse(state.submit(presentation(windowID: 1), revision: oldRevision))
        XCTAssertFalse(state.publish(consumed.presentation.layout, revision: consumed.revision))
        XCTAssertNil(state.takePending())
    }

    func testQueuedDrainSurvivesCancellationAndDeliversNewSubmission() throws {
        let state = OverlayPresentationState()
        XCTAssertTrue(state.submit(presentation(windowID: 1), revision: state.revision))
        let hiddenRevision = state.invalidate()
        // The existing drain will consume the new value, so no second drain is needed.
        XCTAssertFalse(state.submit(presentation(windowID: 2), revision: hiddenRevision))
        let latest = try XCTUnwrap(state.takePending())
        XCTAssertEqual(latest.presentation.layout.target.hit.windowID, 2)
        XCTAssertTrue(state.publish(latest.presentation.layout, revision: latest.revision))
        XCTAssertFalse(state.shouldRemoveViews(revision: hiddenRevision))
    }

    func testPendingMovesCoalesceToLatestHover() throws {
        let state = OverlayPresentationState()
        XCTAssertTrue(state.submit(presentation(windowID: 1, hoveredIndex: 0), revision: state.revision))
        XCTAssertFalse(state.submit(presentation(windowID: 1, hoveredIndex: 1), revision: state.revision))
        XCTAssertEqual(try XCTUnwrap(state.takePending()).presentation.hoveredIndex, 1)
        XCTAssertNil(state.takePending())
    }

    private func presentation(windowID: CGWindowID, hoveredIndex: Int? = nil) -> OverlayPresentation {
        OverlayPresentation(layout: layout(windowID: windowID), hoveredIndex: hoveredIndex,
                            settings: HoverOverlaySettings())
    }

    private func layout(windowID: CGWindowID) -> OverlayLayout {
        OverlayLayout(
            buttons: [], axWindow: AXUIElementCreateApplication(10),
            target: HoverTarget(
                hit: AXQuery.WindowHit(processIdentifier: 10,
                                       bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
                                       windowID: windowID),
                bundleIdentifier: "test.app", appName: nil
            ),
            panelFrames: [CGRect(x: 90, y: 90, width: 40, height: 40),
                          CGRect(x: 150, y: 90, width: 40, height: 40)],
            extraActions: [], extraPanelFrames: []
        )
    }
}
