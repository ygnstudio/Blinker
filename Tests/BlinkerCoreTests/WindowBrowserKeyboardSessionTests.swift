@testable import BlinkerCore
import XCTest

final class WindowBrowserKeyboardSessionTests: XCTestCase {
    func testReleaseEndsAHoldWhileTheCatalogIsStillLoading() {
        var session = WindowBrowserKeyboardSession()
        session.begin(holdingOption: true)
        let token = session.id
        XCTAssertTrue(session.releaseOption())
        session.deferCommitUntilLoaded()
        XCTAssertFalse(session.isHoldingOption)
        XCTAssertFalse(session.releaseOption(), "duplicate flag notifications must not repeat a release")
        XCTAssertTrue(session.takePendingCommit(for: token))
        XCTAssertFalse(session.takePendingCommit(for: token), "a completed load may commit only once")
    }

    func testRepressDuringSlowRefreshStartsANewHoldAndRejectsOldCompletion() {
        var session = WindowBrowserKeyboardSession()
        session.begin(holdingOption: true)
        let firstRefresh = session.id
        XCTAssertTrue(session.releaseOption())
        session.deferCommitUntilLoaded()

        // This is the same continue-or-reopen decision the controller makes for another Option-Tab.
        if !session.isHoldingOption {
            session.begin(holdingOption: true)
        }
        let secondRefresh = session.id
        XCTAssertNotEqual(firstRefresh, secondRefresh)
        XCTAssertTrue(session.isHoldingOption)
        XCTAssertFalse(session.takePendingCommit(for: firstRefresh))
        XCTAssertFalse(
            session.takePendingCommit(for: secondRefresh),
            "a new held Option must not auto-commit"
        )

        XCTAssertTrue(session.releaseOption())
        session.deferCommitUntilLoaded()
        XCTAssertFalse(session.takePendingCommit(for: firstRefresh), "old work cannot consume the new intent")
        XCTAssertTrue(session.takePendingCommit(for: secondRefresh))
    }

    func testDismissAndRapidReopenInvalidateDeferredCommitAndOldRefresh() {
        var session = WindowBrowserKeyboardSession()
        for _ in 0 ..< 500 {
            session.begin(holdingOption: true)
            let oldRefresh = session.id
            XCTAssertTrue(session.releaseOption())
            session.deferCommitUntilLoaded()
            session.dismiss()
            XCTAssertFalse(session.takePendingCommit(for: oldRefresh))
            session.begin(holdingOption: true)
            XCTAssertFalse(session.takePendingCommit(for: oldRefresh))
            XCTAssertFalse(session.takePendingCommit(for: session.id))
            XCTAssertTrue(session.isHoldingOption)
        }
    }

    func testManualPreviewDoesNotCommitOnModifierRelease() {
        var session = WindowBrowserKeyboardSession()
        session.begin(holdingOption: false)
        XCTAssertFalse(session.releaseOption())
        XCTAssertFalse(session.takePendingCommit(for: session.id))
        session.dismiss()
        XCTAssertFalse(session.releaseOption())
    }
}
