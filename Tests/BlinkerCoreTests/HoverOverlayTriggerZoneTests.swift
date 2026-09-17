@testable import BlinkerCore
import CoreGraphics
import XCTest

/// Trigger-zone wake-up semantics: the controller's pre-activation call
/// shape must keep the wake-up area at the native corner no matter how
/// wide the enlarged group is.
final class HoverOverlayTriggerZoneTests: XCTestCase {
    func testWakeUpCallShapeIgnoresEnlargedGroup() {
        // Pre-activation the controller passes no panel/tray frames: the
        // wake-up zone must be just the native group + padding, so enabling
        // extra chips (which grow the enlarged group and tray far to the
        // right) must not balloon the corner the cursor needs to enter.
        let buttons = [
            CGRect(x: 100, y: 500, width: 14, height: 14),
            CGRect(x: 120, y: 500, width: 14, height: 14),
        ]
        let panels = HoverOverlayGeometry.panelFrames(
            forButtonFrames: buttons,
            enlargedSize: 28,
            extraCount: 2
        )
        let tray = HoverOverlayTrayPanel.frame(forDisplayFrames: panels)

        // The wake-up call shape: empty panels, no tray. A point over the
        // enlarged group — well past the native group + 12pt padding (which
        // ends at x=146) — must not trigger.
        XCTAssertFalse(HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: CGPoint(x: 170, y: 507),
            buttonFrames: buttons,
            panelFrames: [],
            trayFrame: nil
        ))
        // The keep-alive call shape (overlay already visible) at the same
        // point stays alive via the panels/tray.
        XCTAssertTrue(HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: CGPoint(x: 170, y: 507),
            buttonFrames: buttons,
            panelFrames: panels,
            trayFrame: tray
        ))
        // Sanity: the same point really is inside the tray/enlarged group.
        XCTAssertTrue(tray!.contains(CGPoint(x: 170, y: 507)))
    }
}
