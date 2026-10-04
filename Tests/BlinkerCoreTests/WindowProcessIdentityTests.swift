@testable import BlinkerCore
import XCTest

final class WindowProcessIdentityTests: XCTestCase {
    private let first = WindowProcessStartTime(seconds: 1234, microseconds: 567)!
    private let reused = WindowProcessStartTime(seconds: 1234, microseconds: 568)!

    func testMissingLaunchDateUsesKernelIdentityRatherThanSkippingFinderLikeProcess() throws {
        let identity = try XCTUnwrap(WindowProcessIdentity(pid: 100, launchDate: nil) { first })
        XCTAssertEqual(identity.pid, 100)
        XCTAssertTrue(identity.matches(launchDate: nil) { first })
        XCTAssertFalse(identity.matches(launchDate: nil) { reused }, "A reused PID is a different process")
        XCTAssertFalse(identity.matches(launchDate: nil) { nil }, "Unreadable identity must fail closed")
    }

    func testKernelIdentityRemainsStableWhenLaunchServicesLaterProvidesDate() throws {
        let identity = try XCTUnwrap(WindowProcessIdentity(pid: 100, launchDate: nil) { first })
        XCTAssertTrue(identity.matches(launchDate: Date(timeIntervalSince1970: 1234)) { first })
        XCTAssertFalse(identity.matches(launchDate: Date(timeIntervalSince1970: 1234)) { reused })
    }

    func testExistingLaunchDateRetainsItsIdentityAndDoesNotReadKernel() throws {
        let date = Date(timeIntervalSince1970: 4321)
        let identity = try XCTUnwrap(WindowProcessIdentity(pid: 100, launchDate: date) {
            XCTFail("Existing launchDate does not need a fallback")
            return nil
        })
        XCTAssertTrue(identity
            .matches(launchDate: date) { XCTFail("Do not change identity source"); return nil })
        XCTAssertFalse(identity.matches(launchDate: date.addingTimeInterval(1)) { first })
        XCTAssertFalse(identity.matches(launchDate: nil) { first })
    }

    func testNoBirthIdentityNeverFallsBackToPIDOnly() {
        XCTAssertNil(WindowProcessIdentity(pid: 100, launchDate: nil) { nil })
        XCTAssertNil(WindowProcessIdentity(pid: 0, launchDate: nil) { first })
        XCTAssertNil(WindowProcessIdentity(pid: -1, launchDate: nil) { first })
        XCTAssertNil(WindowProcessStartTime(seconds: 0, microseconds: 0))
        XCTAssertNil(WindowProcessStartTime(seconds: 1, microseconds: 1_000_000))
    }
}
