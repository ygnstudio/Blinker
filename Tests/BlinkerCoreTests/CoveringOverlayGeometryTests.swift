@testable import BlinkerCore
import CoreGraphics
import XCTest

final class CoveringOverlayGeometryTests: XCTestCase {
    private let buttons = [
        CGRect(x: 110, y: 110, width: 14, height: 14),
        CGRect(x: 130, y: 110, width: 14, height: 14),
        CGRect(x: 150, y: 110, width: 14, height: 14),
    ]

    func testOverlayCoversOriginalRowWithoutMovingBelowIt() throws {
        let frames = HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: buttons, enlargedSize: 40,
            containerBounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let tray = try XCTUnwrap(HoverOverlayTrayPanel.frame(forDisplayFrames: frames))
        let anchor = try XCTUnwrap(HoverOverlayGeometry.unionedBounds(of: buttons))
        XCTAssertEqual(frames.first?.midY, anchor.midY)
        XCTAssertEqual(frames.first?.midX, buttons[0].midX)
        XCTAssertTrue(tray.contains(anchor))
        XCTAssertTrue(frames[0].contains(buttons[0]))
    }

    func testLargeOverlayAtWindowTopRemainsCenteredOnNativeRow() throws {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frames = HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: buttons, enlargedSize: 48, containerBounds: screen
        )
        let first = try XCTUnwrap(frames.first)
        XCTAssertEqual(first.midY, buttons[0].midY)
        XCTAssertEqual(first.midX, buttons[0].midX)
        XCTAssertTrue(first.contains(buttons[0]))
        // The window begins at y=100. A genuine covering panel may extend above it.
        XCTAssertLessThan(first.minY, 100)
    }

    func testScreenEdgeClampsControlsWithoutReservingInvisibleMargins() throws {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let native = CGRect(x: 16, y: 14, width: 14, height: 14)
        let frames = HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: [native], enlargedSize: 48, containerBounds: screen
        )
        let first = try XCTUnwrap(frames.first)
        XCTAssertEqual(first.minX, 0)
        XCTAssertEqual(first.minY, 0)
        XCTAssertTrue(first.contains(native))
    }

    func testAllControlsFitNarrowDisplay() throws {
        let container = CGRect(x: 100, y: 100, width: 220, height: 200)
        let frames = HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: buttons, enlargedSize: 48, containerBounds: container, extraCount: 4
        )
        XCTAssertEqual(frames.count, 7)
        let controls = try XCTUnwrap(HoverOverlayGeometry.unionedBounds(of: frames))
        XCTAssertTrue(container.insetBy(dx: -0.001, dy: -0.001).contains(controls))
        for pair in zip(frames, frames.dropFirst()) {
            XCTAssertLessThan(pair.0.maxX, pair.1.minX)
        }
    }

    func testPaletteClampsAtBottomAndRightOnOffsetDisplay() throws {
        let container = CGRect(x: -1200, y: -700, width: 800, height: 500)
        let anchor = [CGRect(x: -450, y: -240, width: 14, height: 14)]
        let frames = HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: anchor, enlargedSize: 48, containerBounds: container, extraCount: 4
        )
        let controls = try XCTUnwrap(HoverOverlayGeometry.unionedBounds(of: frames))
        XCTAssertTrue(container.contains(controls))
    }

    func testNoControlsForMissingAnchorOrImpossibleContainer() {
        XCTAssertTrue(HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: [], enlargedSize: 40,
            containerBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        ).isEmpty)
        XCTAssertTrue(HoverOverlayGeometry.coveringPanelFrames(
            forButtonFrames: buttons, enlargedSize: 40,
            containerBounds: CGRect(x: 0, y: 0, width: 0, height: 0)
        ).isEmpty)
    }

    func testAXFramesBecomeTrayLocalFramesWithoutScreenDependence() {
        let tray = CGRect(x: -200, y: -80, width: 180, height: 56)
        let control = CGRect(x: -188, y: -72, width: 40, height: 40)
        XCTAssertEqual(HoverOverlayTrayPanel.localRect(forAXRect: control, inTray: tray),
                       CGRect(x: 12, y: 8, width: 40, height: 40))
    }
}
