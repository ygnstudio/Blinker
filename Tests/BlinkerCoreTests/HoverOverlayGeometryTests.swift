@testable import BlinkerCore
import CoreGraphics
import XCTest

final class HoverOverlayGeometryTests: XCTestCase {
    func testCursorInTriggerZone() {
        let buttons = [
            CGRect(x: 100, y: 500, width: 14, height: 14),
            CGRect(x: 114, y: 500, width: 14, height: 14),
        ]
        let panels = [CGRect(x: 90, y: 485, width: 40, height: 40)]

        // Right at the buttons.
        XCTAssertTrue(HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: CGPoint(x: 107, y: 507),
            buttonFrames: buttons,
            panelFrames: panels
        ))
        // Within the padding around the group.
        XCTAssertTrue(HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: CGPoint(x: 122, y: 507),
            buttonFrames: buttons,
            panelFrames: panels
        ))
        // Away from the buttons but on an enlarged panel: the overlay must
        // stay alive to avoid a hide/flicker loop.
        XCTAssertTrue(HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: CGPoint(x: 95, y: 490),
            buttonFrames: buttons,
            panelFrames: panels
        ))
        // Far away on the title bar: no trigger.
        XCTAssertFalse(HoverOverlayGeometry.isCursorInTriggerZone(
            cursor: CGPoint(x: 400, y: 507),
            buttonFrames: buttons,
            panelFrames: panels
        ))
    }

    func testSingleButtonGroupLeadsAtNativeEdge() {
        let frames = [CGRect(x: 200, y: 300, width: 14, height: 14)]
        let panels = HoverOverlayGeometry.panelFrames(forButtonFrames: frames, enlargedSize: 28)

        XCTAssertEqual(panels.count, 1)
        // Leading edge anchored slightly past the native button's left edge
        // so the glass ghost stays covered; vertical center is preserved.
        XCTAssertEqual(panels[0].minX, 200 - HoverOverlayGeometry.leadingAnchorInset, accuracy: 0.001)
        XCTAssertEqual(panels[0].midY, 307, accuracy: 0.001)
        XCTAssertEqual(panels[0].width, 28)
        XCTAssertEqual(panels[0].height, 28)
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
        // The group is leading-edge anchored: the first panel sits slightly
        // left of the native group's left edge, growing to the right.
        let groupMinX = frames.dropFirst().reduce(frames[0]) { $0.union($1) }.minX
        XCTAssertEqual(
            panels[0].minX,
            groupMinX - HoverOverlayGeometry.leadingAnchorInset,
            accuracy: 0.001
        )
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
        // Buttons at the very top-left corner of the screen: the leading
        // anchor keeps the group inside, but the clamp must still hold for
        // every panel.
        let frames = [
            CGRect(x: 8, y: 8, width: 14, height: 14),
            CGRect(x: 22, y: 8, width: 14, height: 14),
            CGRect(x: 36, y: 8, width: 14, height: 14),
        ]
        let container = CGRect(x: 0, y: 0, width: 1440, height: 900)
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
        let container = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(
            HoverOverlayGeometry.panelFrames(
                forButtonFrames: frames,
                enlargedSize: 40,
                containerBounds: container
            ),
            HoverOverlayGeometry.panelFrames(forButtonFrames: frames, enlargedSize: 40)
        )
    }

    func testExtraChipsAppendRightOfNativeGroup() {
        let frames = [
            CGRect(x: 100, y: 500, width: 14, height: 14),
            CGRect(x: 114, y: 500, width: 14, height: 14),
            CGRect(x: 128, y: 500, width: 14, height: 14),
        ]
        let native = HoverOverlayGeometry.panelFrames(forButtonFrames: frames, enlargedSize: 40)
        let withExtras = HoverOverlayGeometry.panelFrames(
            forButtonFrames: frames,
            enlargedSize: 40,
            minimumGap: 4,
            extraCount: 2
        )

        XCTAssertEqual(withExtras.count, 5)
        // The native chips keep their leading-anchored positions.
        XCTAssertEqual(Array(withExtras.prefix(3)), native)
        // Extras continue to the right with the minimum gap.
        XCTAssertEqual(withExtras[3].minX - withExtras[2].maxX, 4, accuracy: 0.001)
        XCTAssertEqual(withExtras[4].minX - withExtras[3].maxX, 4, accuracy: 0.001)
        for frame in withExtras.dropFirst(3) {
            XCTAssertEqual(frame.width, 40)
            XCTAssertEqual(frame.midY, withExtras[2].midY, accuracy: 0.001)
        }
    }

    func testExtraChipsShiftWholeGroupIntoContainer() {
        // The group sits close to the screen's right edge: appending chips
        // must shift everything left so nothing clips.
        let frames = [
            CGRect(x: 1300, y: 500, width: 14, height: 14),
            CGRect(x: 1314, y: 500, width: 14, height: 14),
        ]
        let container = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panels = HoverOverlayGeometry.panelFrames(
            forButtonFrames: frames,
            enlargedSize: 40,
            minimumGap: 4,
            containerBounds: container,
            extraCount: 2
        )

        XCTAssertEqual(panels.count, 4)
        for panel in panels {
            XCTAssertTrue(container.contains(panel), "panel \(panel) escapes the container")
        }
        for index in 0 ..< panels.count - 1 {
            XCTAssertEqual(
                panels[index + 1].minX - panels[index].maxX,
                4,
                accuracy: 0.001
            )
        }
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

        // The minimum keeps the enlarged circle larger than the native
        // buttons after the chip's inner padding.
        let tiny = HoverOverlaySettings(enlargedSize: 2, dwellMilliseconds: -5)
        XCTAssertEqual(tiny.enlargedSize, 28)
        XCTAssertEqual(tiny.dwellMilliseconds, 0)
    }

    func testExtraActionsNormalizeAndCompact() {
        // Defaults: all slots empty, no chips rendered.
        let defaults = HoverOverlaySettings()
        XCTAssertEqual(defaults.extraButtonActions.count, HoverOverlaySettings.extraSlotCount)
        XCTAssertTrue(defaults.enabledExtraActions.isEmpty)

        // Configured slots surface in order; empty slots are skipped.
        var configured = HoverOverlaySettings()
        configured.extraButtonActions[0] = .tileLeft
        configured.extraButtonActions[2] = .centerWindow
        XCTAssertEqual(configured.enabledExtraActions, [.tileLeft, .centerWindow])

        // Oversized payloads are trimmed to the slot count.
        let oversized = HoverOverlaySettings(
            extraButtonActions: Array(repeating: ButtonAction.maximize, count: 9)
        )
        XCTAssertEqual(oversized.extraButtonActions.count, HoverOverlaySettings.extraSlotCount)
        XCTAssertEqual(oversized.enabledExtraActions.count, HoverOverlaySettings.extraSlotCount)
    }

    func testSettingsDecodeWithoutExtraActionsKey() {
        // A payload persisted by an older version carries no extra-button
        // key and must still load (defaults, not a reset).
        let oldPayload = """
        {"isEnabled":true,"enlargedSize":36,"dwellMilliseconds":150,\
        "appliesToAllWindows":true,"mode":"overlay","maskStyle":"glass"}
        """
        let decoded = try? JSONDecoder().decode(
            HoverOverlaySettings.self,
            from: Data(oldPayload.utf8)
        )
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.enlargedSize, 36)
        XCTAssertEqual(decoded?.extraButtonActions.count, HoverOverlaySettings.extraSlotCount)
        XCTAssertTrue(decoded?.enabledExtraActions.isEmpty ?? false)
    }

    func testSettingsRoundTripsExtraActions() throws {
        var settings = HoverOverlaySettings()
        settings.extraButtonActions = [.tileLeft, nil, .quitApp, nil]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(HoverOverlaySettings.self, from: data)
        XCTAssertEqual(decoded.extraButtonActions, settings.extraButtonActions)
        XCTAssertEqual(decoded.enabledExtraActions, [.tileLeft, .quitApp])
    }
}

final class SafeCorridorTests: XCTestCase {
    // Chip at (200, 500, 40, 40); HUD directly below with a 6 pt gap.
    private let anchor = CGRect(x: 200, y: 500, width: 40, height: 40)
    private let panel = CGRect(x: 200, y: 546, width: 252, height: 220)

    func testStraightDownPathStaysInsideCorridor() {
        // Every sample along the straight path from the chip's bottom edge
        // to the HUD's top edge — including the gap itself — is safe. The
        // endpoint `panel.minY` itself is half-open (covered by the HUD
        // rect hit-test in the caller).
        for sampleY in stride(from: CGFloat(540), through: CGFloat(545.5), by: 0.5) {
            XCTAssertTrue(
                HoverOverlayGeometry.safeCorridorContains(
                    cursor: CGPoint(x: 220, y: sampleY),
                    anchor: anchor,
                    panel: panel
                ),
                "cursor at y=\(sampleY) should stay inside the corridor"
            )
        }
    }

    func testDiagonalPathTowardClampedPanelStaysInside() {
        // The HUD clamped far to the right: the straight path slants, and
        // the corridor must still cover it.
        let clamped = CGRect(x: 400, y: 546, width: 252, height: 220)
        for fraction in stride(from: CGFloat(0.1), through: CGFloat(0.9), by: 0.1) {
            let start = CGPoint(x: anchor.midX, y: anchor.maxY)
            let end = CGPoint(x: clamped.midX, y: clamped.minY)
            let cursor = CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
            XCTAssertTrue(
                HoverOverlayGeometry.safeCorridorContains(cursor: cursor, anchor: anchor, panel: clamped),
                "slanted path at fraction \(fraction) should stay safe"
            )
        }
    }

    func testHorizontalEscapeClosesTheCorridor() {
        // Moving sideways away from the chip → HUD axis is outside the
        // corridor: the HUD may close.
        XCTAssertFalse(HoverOverlayGeometry.safeCorridorContains(
            cursor: CGPoint(x: 150, y: 543),
            anchor: anchor,
            panel: panel
        ))
    }

    func testPointsOutsideTheVerticalSpanAreNotCorridor() {
        // Above the chip's bottom edge (the chip itself) and below the
        // HUD's top edge (the HUD body) are handled by rect hit-tests,
        // not the corridor.
        XCTAssertFalse(HoverOverlayGeometry.safeCorridorContains(
            cursor: CGPoint(x: 220, y: 520),
            anchor: anchor,
            panel: panel
        ))
        XCTAssertFalse(HoverOverlayGeometry.safeCorridorContains(
            cursor: CGPoint(x: 220, y: 600),
            anchor: anchor,
            panel: panel
        ))
    }
}
