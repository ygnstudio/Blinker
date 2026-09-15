@testable import BlinkerCore
import CoreGraphics
import XCTest

/// Regression tests for the CG→AppKit coordinate conversion in
/// `WindowSnapper`. The event tap delivers CG points (top-left origin,
/// y growing downward) while `NSScreen` frames and `SnapZones` live in
/// AppKit space (bottom-left origin, y growing upward); skipping the flip
/// mirrors every snap zone vertically (drag-to-top snapped to a bottom tile).
final class WindowSnapperTests: XCTestCase {
    /// Typical MacBook layout: 982 pt tall screen, menu bar at the top,
    /// dock at the bottom. `visibleFrame.maxY` sits just below the menu bar.
    private let pivotY: CGFloat = 982
    private let visibleFrame = CGRect(x: 0, y: 69, width: 1512, height: 889)

    func testYAxisFlipsAroundPivot() {
        // Top edge of the screen in CG space (y ≈ 24, below the menu bar)
        // lands near the top of AppKit space.
        XCTAssertEqual(
            WindowSnapper.appKitPoint(from: CGPoint(x: 756, y: 24), pivotY: pivotY),
            CGPoint(x: 756, y: 958)
        )
        // Bottom edge in CG space lands near the bottom of AppKit space.
        XCTAssertEqual(
            WindowSnapper.appKitPoint(from: CGPoint(x: 756, y: 975), pivotY: pivotY),
            CGPoint(x: 756, y: 7)
        )
        // x is never touched.
        XCTAssertEqual(
            WindowSnapper.appKitPoint(from: CGPoint(x: 120, y: 491), pivotY: pivotY).x,
            120
        )
    }

    func testConvertedTopEdgeResolvesToMaximize() {
        // Dragging to the physical top edge must resolve to .maximize —
        // before the fix it resolved to a bottom tile.
        let topEdge = WindowSnapper.appKitPoint(from: CGPoint(x: 756, y: 24), pivotY: pivotY)
        XCTAssertGreaterThan(topEdge.y, visibleFrame.maxY - SnapZones.edgeInset)
        XCTAssertEqual(SnapZones.placement(at: topEdge, in: visibleFrame), .maximize)
    }

    func testConvertedBottomEdgeResolvesToBottomTile() {
        let bottomEdge = WindowSnapper.appKitPoint(from: CGPoint(x: 756, y: 975), pivotY: pivotY)
        XCTAssertLessThanOrEqual(bottomEdge.y, visibleFrame.minY + SnapZones.edgeInset)
        XCTAssertEqual(SnapZones.placement(at: bottomEdge, in: visibleFrame), .bottom)
    }

    func testConvertedLeftCornerResolvesToTopLeftQuadrant() {
        // Physical top-left corner: small CG y, small x.
        let corner = WindowSnapper.appKitPoint(from: CGPoint(x: 10, y: 24), pivotY: pivotY)
        XCTAssertEqual(SnapZones.placement(at: corner, in: visibleFrame), .topLeft)
    }
}
