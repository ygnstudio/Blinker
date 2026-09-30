@testable import BlinkerCore
import XCTest

final class OverlayClickGateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OverlayClickGate.reset()
    }

    override func tearDown() {
        OverlayClickGate.reset()
        super.tearDown()
    }

    func testDefaultsToUnsuppressed() {
        XCTAssertFalse(OverlayClickGate.isSuppressed)
    }

    func testSuppressesDuringWindow() {
        OverlayClickGate.suppressFor(milliseconds: 5000)
        XCTAssertTrue(OverlayClickGate.isSuppressed)
    }

    func testZeroDurationDoesNotSuppress() {
        OverlayClickGate.suppressFor(milliseconds: 0)
        XCTAssertFalse(OverlayClickGate.isSuppressed)
    }

    func testResetClearsSuppression() {
        OverlayClickGate.suppressFor(milliseconds: 5000)
        OverlayClickGate.reset()
        XCTAssertFalse(OverlayClickGate.isSuppressed)
    }

    func testVisibleOverlaySuppressesFirstClickBeforeMouseDown() {
        OverlayClickGate.setOverlayFrames([CGRect(x: 100, y: 100, width: 120, height: 44)])
        XCTAssertTrue(OverlayClickGate.isSuppressed(at: CGPoint(x: 130, y: 120)))
        XCTAssertFalse(OverlayClickGate.isSuppressed(at: CGPoint(x: 80, y: 120)))
    }

    func testHidingOverlayReleasesItsHitRegion() {
        OverlayClickGate.setOverlayFrames([CGRect(x: 100, y: 100, width: 120, height: 44)])
        OverlayClickGate.setOverlayFrames([])
        XCTAssertFalse(OverlayClickGate.isSuppressed(at: CGPoint(x: 130, y: 120)))
    }

    func testReplacingOverlayDoesNotKeepOldRegions() {
        OverlayClickGate.setOverlayFrames([CGRect(x: 100, y: 100, width: 120, height: 44)])
        OverlayClickGate.setOverlayFrames([CGRect(x: 300, y: 300, width: 120, height: 44)])
        XCTAssertFalse(OverlayClickGate.isSuppressed(at: CGPoint(x: 130, y: 120)))
        XCTAssertTrue(OverlayClickGate.isSuppressed(at: CGPoint(x: 330, y: 320)))
    }
}
