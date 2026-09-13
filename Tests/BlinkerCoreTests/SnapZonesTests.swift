@testable import BlinkerCore
import CoreGraphics
import XCTest

final class SnapZonesTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)

    func testCenterIsNotASnapZone() {
        XCTAssertNil(SnapZones.placement(at: CGPoint(x: 500, y: 350), in: screen))
    }

    func testEdgesMapToHalvesAndMaximize() {
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 2, y: 350), in: screen), .left)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 998, y: 350), in: screen), .right)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 500, y: 698), in: screen), .maximize)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 500, y: 2), in: screen), .bottom)
    }

    func testCornersMapToQuadrants() {
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 2, y: 698), in: screen), .topLeft)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 998, y: 698), in: screen), .topRight)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 2, y: 2), in: screen), .bottomLeft)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 998, y: 2), in: screen), .bottomRight)
    }

    /// The corner zones are bounded: moving inward past `cornerExtent` along
    /// the top edge falls back to maximize, not a quadrant.
    func testCornerExtentBounds() {
        // x = 50 is within cornerExtent (80) of the left edge.
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 50, y: 698), in: screen), .topLeft)
        // x = 100 is past it; the top edge wins → maximize.
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 100, y: 698), in: screen), .maximize)
    }

    func testInsetBoundaryInclusive() {
        // Exactly at the inset distance still counts as the edge.
        let insetX = SnapZones.edgeInset
        let insetY = SnapZones.edgeInset
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: insetX, y: insetY), in: screen), .bottomLeft)
    }

    func testOffsetScreenCoordinates() {
        let offsetScreen = CGRect(x: 1000, y: 0, width: 1000, height: 700)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 1002, y: 350), in: offsetScreen), .left)
        XCTAssertEqual(SnapZones.placement(at: CGPoint(x: 1998, y: 698), in: offsetScreen), .topRight)
        XCTAssertNil(SnapZones.placement(at: CGPoint(x: 1500, y: 350), in: offsetScreen))
    }
}
