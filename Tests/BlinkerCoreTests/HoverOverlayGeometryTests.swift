@testable import BlinkerCore
import CoreGraphics
import XCTest

final class HoverOverlayGeometryTests: XCTestCase {
    func testCursorInTitleBarBand() {
        let window = CGRect(x: 100, y: 500, width: 800, height: 600)

        // Inside the band, near the top and at the band edge.
        XCTAssertTrue(HoverOverlayGeometry.isCursorInTitleBarBand(
            cursor: CGPoint(x: 150, y: 510),
            windowBounds: window
        ))
        XCTAssertTrue(HoverOverlayGeometry.isCursorInTitleBarBand(
            cursor: CGPoint(x: 150, y: 548),
            windowBounds: window
        ))
        // Below the band.
        XCTAssertFalse(HoverOverlayGeometry.isCursorInTitleBarBand(
            cursor: CGPoint(x: 150, y: 560),
            windowBounds: window
        ))
        // Outside the window entirely.
        XCTAssertFalse(HoverOverlayGeometry.isCursorInTitleBarBand(
            cursor: CGPoint(x: 50, y: 510),
            windowBounds: window
        ))
    }

    func testPanelFrameCentersOnButton() {
        let button = CGRect(x: 200, y: 300, width: 14, height: 14)
        let panel = HoverOverlayGeometry.panelFrame(forButtonFrame: button, enlargedSize: 28)

        XCTAssertEqual(panel.midX, button.midX, accuracy: 0.001)
        XCTAssertEqual(panel.midY, button.midY, accuracy: 0.001)
        XCTAssertEqual(panel.width, 28)
        XCTAssertEqual(panel.height, 28)
    }

    func testCursorInPanelHitTest() {
        let panel = CGRect(x: 0, y: 0, width: 28, height: 28)

        XCTAssertTrue(HoverOverlayGeometry.isCursorInPanel(cursor: CGPoint(x: 14, y: 14), panelFrame: panel))
        XCTAssertTrue(HoverOverlayGeometry.isCursorInPanel(cursor: CGPoint(x: 0, y: 0), panelFrame: panel))
        XCTAssertFalse(HoverOverlayGeometry.isCursorInPanel(cursor: CGPoint(x: 40, y: 14), panelFrame: panel))
    }

    func testDwellProgress() {
        XCTAssertEqual(
            HoverOverlayGeometry.dwellProgress(elapsedMilliseconds: 0, dwellMilliseconds: 150),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            HoverOverlayGeometry.dwellProgress(elapsedMilliseconds: 75, dwellMilliseconds: 150),
            0.5,
            accuracy: 0.0001
        )
        // Progress saturates at 1.
        XCTAssertEqual(
            HoverOverlayGeometry.dwellProgress(elapsedMilliseconds: 300, dwellMilliseconds: 150),
            1,
            accuracy: 0.0001
        )
        // Zero dwell means immediate activation.
        XCTAssertEqual(
            HoverOverlayGeometry.dwellProgress(elapsedMilliseconds: 0, dwellMilliseconds: 0),
            1,
            accuracy: 0.0001
        )
    }

    func testWindowBoundsChangeDetection() {
        let bounds = CGRect(x: 100, y: 200, width: 800, height: 600)

        // No previous bounds means a fresh cache.
        XCTAssertTrue(HoverOverlayGeometry.hasWindowBoundsChanged(previous: nil, current: bounds))
        XCTAssertFalse(HoverOverlayGeometry.hasWindowBoundsChanged(previous: bounds, current: bounds))
        // Sub-point jitter (shadow rounding) does not invalidate the cache.
        XCTAssertFalse(HoverOverlayGeometry.hasWindowBoundsChanged(
            previous: bounds,
            current: CGRect(x: 100.5, y: 200.5, width: 800, height: 600)
        ))
        // A real move or resize does.
        XCTAssertTrue(HoverOverlayGeometry.hasWindowBoundsChanged(
            previous: bounds,
            current: CGRect(x: 105, y: 200, width: 800, height: 600)
        ))
        XCTAssertTrue(HoverOverlayGeometry.hasWindowBoundsChanged(
            previous: bounds,
            current: CGRect(x: 100, y: 200, width: 900, height: 600)
        ))
    }

    func testSettingsClampToBounds() {
        let settings = HoverOverlaySettings(enlargedSize: 99, dwellMilliseconds: 5000)
        XCTAssertEqual(settings.enlargedSize, 48)
        XCTAssertEqual(settings.dwellMilliseconds, 800)

        let tiny = HoverOverlaySettings(enlargedSize: 2, dwellMilliseconds: -5)
        XCTAssertEqual(tiny.enlargedSize, 18)
        XCTAssertEqual(tiny.dwellMilliseconds, 0)
    }
}
