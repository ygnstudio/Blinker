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

    func testSingleButtonGroupMatchesPanelFrame() {
        let frames = [CGRect(x: 200, y: 300, width: 14, height: 14)]
        let panels = HoverOverlayGeometry.panelFrames(forButtonFrames: frames, enlargedSize: 28)

        XCTAssertEqual(panels, [HoverOverlayGeometry.panelFrame(
            forButtonFrame: frames[0],
            enlargedSize: 28
        )])
    }

    func testGroupLayoutSpreadsEnlargedPanelsWithoutOverlap() {
        // Real traffic lights sit ~12 pt apart; enlarging to 40 pt per button
        // must not stack the panels on top of each other.
        let frames = [
            CGRect(x: 100, y: 500, width: 14, height: 14),
            CGRect(x: 114, y: 500, width: 14, height: 14),
            CGRect(x: 128, y: 500, width: 14, height: 14),
        ]
        let panels = HoverOverlayGeometry.panelFrames(
            forButtonFrames: frames,
            enlargedSize: 40,
            minimumGap: 6
        )

        XCTAssertEqual(panels.count, 3)
        // No horizontal overlap between neighbors.
        for index in 0 ..< panels.count - 1 {
            XCTAssertLessThanOrEqual(
                panels[index].maxX,
                panels[index + 1].minX,
                "panel \(index) overlaps panel \(index + 1)"
            )
        }
        // The group stays centered on the original buttons' bounding box.
        let groupCenterX = frames.dropFirst().reduce(frames[0]) { $0.union($1) }.midX
        let laidOutCenterX = (panels[0].minX + panels[2].maxX) / 2
        XCTAssertEqual(laidOutCenterX, groupCenterX, accuracy: 0.001)
        // Order is preserved (close / minimize / zoom left to right).
        XCTAssertTrue(panels[0].midX < panels[1].midX)
        XCTAssertTrue(panels[1].midX < panels[2].midX)
        // Vertical centering follows the original group.
        for panel in panels {
            XCTAssertEqual(panel.midY, 507, accuracy: 0.001)
        }
    }

    func testGroupLayoutWithEmptyInput() {
        XCTAssertTrue(HoverOverlayGeometry.panelFrames(forButtonFrames: [], enlargedSize: 28).isEmpty)
    }

    func testGroupLayoutClampsIntoContainerOnEdgeAnchoredWindows() {
        // Buttons at the very top-left corner of the screen: the centered
        // group would overflow past both edges and get clipped.
        let frames = [
            CGRect(x: 8, y: 8, width: 14, height: 14),
            CGRect(x: 22, y: 8, width: 14, height: 14),
            CGRect(x: 36, y: 8, width: 14, height: 14),
        ]
        let container = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let panels = HoverOverlayGeometry.panelFrames(
            forButtonFrames: frames,
            enlargedSize: 40,
            minimumGap: 4,
            containerBounds: container
        )

        for panel in panels {
            XCTAssertTrue(
                container.contains(panel),
                "panel \(panel) escapes the screen container"
            )
        }
        // The group is shifted right/down, but order and spacing are kept.
        for index in 0 ..< panels.count - 1 {
            XCTAssertEqual(
                panels[index + 1].minX - panels[index].maxX,
                4,
                accuracy: 0.001
            )
        }
        XCTAssertTrue(panels[0].midX < panels[1].midX)
        XCTAssertTrue(panels[1].midX < panels[2].midX)
    }

    func testGroupLayoutUnchangedWhenGroupFitsContainer() {
        let frames = [
            CGRect(x: 300, y: 300, width: 14, height: 14),
            CGRect(x: 314, y: 300, width: 14, height: 14),
        ]
        let container = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        XCTAssertEqual(
            HoverOverlayGeometry.panelFrames(
                forButtonFrames: frames,
                enlargedSize: 40,
                containerBounds: container
            ),
            HoverOverlayGeometry.panelFrames(forButtonFrames: frames, enlargedSize: 40)
        )
    }

    func testGroupLayoutClampsWhenGroupWiderThanContainer() {
        let frames = [
            CGRect(x: 8, y: 8, width: 14, height: 14),
            CGRect(x: 22, y: 8, width: 14, height: 14),
        ]
        let tinyContainer = CGRect(x: 0, y: 0, width: 30, height: 900)
        let panels = HoverOverlayGeometry.panelFrames(
            forButtonFrames: frames,
            enlargedSize: 40,
            containerBounds: tinyContainer
        )

        // Degenerate container: prefer the leading edge instead of NaN math.
        XCTAssertEqual(panels[0].minX, 0)
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
