@testable import BlinkerCore
import CoreGraphics
import XCTest

final class WindowGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

    func testHalvesSplitTheScreen() {
        let left = WindowGeometry.targetFrame(for: .left, originalFrame: window, in: screen)
        let right = WindowGeometry.targetFrame(for: .right, originalFrame: window, in: screen)
        let top = WindowGeometry.targetFrame(for: .top, originalFrame: window, in: screen)
        let bottom = WindowGeometry.targetFrame(for: .bottom, originalFrame: window, in: screen)

        XCTAssertEqual(left, CGRect(x: 0, y: 0, width: 500, height: 800))
        XCTAssertEqual(right, CGRect(x: 500, y: 0, width: 500, height: 800))
        XCTAssertEqual(top, CGRect(x: 0, y: 400, width: 1000, height: 400))
        XCTAssertEqual(bottom, CGRect(x: 0, y: 0, width: 1000, height: 400))
    }

    func testQuadrantsTileWithoutGaps() {
        let topLeft = WindowGeometry.targetFrame(for: .topLeft, originalFrame: window, in: screen)
        let topRight = WindowGeometry.targetFrame(for: .topRight, originalFrame: window, in: screen)
        let bottomLeft = WindowGeometry.targetFrame(for: .bottomLeft, originalFrame: window, in: screen)
        let bottomRight = WindowGeometry.targetFrame(for: .bottomRight, originalFrame: window, in: screen)

        let union = topLeft.union(topRight).union(bottomLeft).union(bottomRight)
        XCTAssertEqual(union, screen)
        XCTAssertEqual(topLeft, CGRect(x: 0, y: 400, width: 500, height: 400))
        XCTAssertEqual(bottomRight, CGRect(x: 500, y: 0, width: 500, height: 400))
    }

    func testAlmostMaximizeLeavesSymmetricMargins() {
        let frame = WindowGeometry.targetFrame(for: .almostMaximize, originalFrame: window, in: screen)
        let margin = WindowGeometry.almostMaximizeMargin

        XCTAssertEqual(frame.width, screen.width * (1 - margin * 2), accuracy: 0.001)
        XCTAssertEqual(frame.height, screen.height * (1 - margin * 2), accuracy: 0.001)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.001)
    }

    func testCenterKeepsWindowSize() {
        let frame = WindowGeometry.targetFrame(for: .center, originalFrame: window, in: screen)
        XCTAssertEqual(frame.size, window.size)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.001)
    }

    func testMaximizeFillsVisibleFrame() {
        let frame = WindowGeometry.targetFrame(for: .maximize, originalFrame: window, in: screen)
        XCTAssertEqual(frame, screen)
    }
}
