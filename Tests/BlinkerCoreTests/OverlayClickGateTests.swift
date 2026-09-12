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
}
