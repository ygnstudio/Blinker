@testable import BlinkerCore
import XCTest

final class DockClickGestureTests: XCTestCase {
    private let point = CGPoint(x: 40, y: 50)
    private let hit = DockClickHit(applicationURL: URL(fileURLWithPath: "/Applications/Example.app"),
                                   frame: CGRect(x: 20, y: 20, width: 60, height: 60))

    func testHitBeforeReleasePreservesTheDownTimeIdentityAndEligibleWindows() throws {
        var gesture = DockClickGesture()
        let request = try XCTUnwrap(gesture.begin(at: point, time: 1, frontmostPID: 42,
                                                  isPlainSingleClick: true))
        gesture.snapshot([11, 12], for: request)
        XCTAssertNil(gesture.resolve(hit, for: request))
        let candidate = try XCTUnwrap(gesture.end(at: point, time: 1.1, isPlainSingleClick: true))
        XCTAssertEqual(candidate.frontmostPIDAtDown, 42)
        XCTAssertEqual(candidate.applicationURL, hit.applicationURL)
        XCTAssertEqual(candidate.eligibleWindowIDs, [11, 12])
        XCTAssertEqual(candidate.ticket, request)
        XCTAssertNil(gesture.end(at: point, time: 1.2, isPlainSingleClick: true))
    }

    func testReleaseBeforeAXCompletesStillUsesOnlyThePreReleaseSnapshot() throws {
        var gesture = DockClickGesture()
        let request = try XCTUnwrap(gesture.begin(at: point, time: 1, frontmostPID: 42,
                                                  isPlainSingleClick: true))
        gesture.snapshot([11], for: request)
        XCTAssertNil(gesture.end(at: point, time: 1.1, isPlainSingleClick: true))
        gesture.snapshot([99], for: request)
        let candidate = try XCTUnwrap(gesture.resolve(hit, for: request))
        XCTAssertEqual(
            candidate.eligibleWindowIDs,
            [11],
            "A newly restored window must not replace down evidence"
        )
        XCTAssertEqual(candidate.releasedAt, 1.1)
    }

    func testFastReleaseWithoutSnapshotCannotTurnPostClickWindowsIntoEligibleOnes() throws {
        var gesture = DockClickGesture()
        let request = try XCTUnwrap(gesture.begin(at: point, time: 1, frontmostPID: 42,
                                                  isPlainSingleClick: true))
        XCTAssertNil(gesture.end(at: point, time: 1.01, isPlainSingleClick: true))
        gesture.snapshot([99], for: request)
        XCTAssertNil(try XCTUnwrap(gesture.resolve(hit, for: request)).eligibleWindowIDs)
    }

    func testDraggingOrInterruptionRejectsLateAXAndMouseUp() throws {
        var gesture = DockClickGesture()
        let request = try XCTUnwrap(gesture.begin(at: point, time: 1, frontmostPID: 42,
                                                  isPlainSingleClick: true))
        gesture.cancel()
        XCTAssertNil(gesture.resolve(hit, for: request))
        XCTAssertNil(gesture.end(at: point, time: 1.1, isPlainSingleClick: true))
        XCTAssertNotEqual(gesture.ticket, request)
    }

    func testModifiersMultipleClicksLongPressAndLeavingTheItemAreIgnored() throws {
        var gesture = DockClickGesture()
        XCTAssertNil(gesture.begin(at: point, time: 1, frontmostPID: 42, isPlainSingleClick: false))
        for (release, time, plain) in [(point, 2.0, true), (point, 1.1, false), (.zero, 1.1, true)] {
            let request = try XCTUnwrap(gesture.begin(at: point, time: 1, frontmostPID: 42,
                                                      isPlainSingleClick: true))
            XCTAssertNil(gesture.resolve(hit, for: request))
            XCTAssertNil(gesture.end(at: release, time: time, isPlainSingleClick: plain))
            XCTAssertNotEqual(gesture.ticket, request)
        }
    }

    func testNewClickRejectsOldResolutionAndNonApplicationHitCancels() throws {
        var gesture = DockClickGesture()
        let old = try XCTUnwrap(gesture.begin(at: point, time: 1, frontmostPID: 42,
                                              isPlainSingleClick: true))
        let fresh = try XCTUnwrap(gesture.begin(at: point, time: 2, frontmostPID: 43,
                                                isPlainSingleClick: true))
        gesture.snapshot([11], for: old)
        XCTAssertNil(gesture.resolve(hit, for: old))
        XCTAssertNil(gesture.resolve(nil, for: fresh))
        XCTAssertNil(gesture.end(at: point, time: 2.1, isPlainSingleClick: true))
    }
}

@MainActor
final class DockClickActionRouterTests: XCTestCase {
    func testNewlyActivatedAppIsNeverMinimized() {
        let session = FakeDockClickSession()
        let router = DockClickActionRouter { session }
        router.setPaused(false)
        XCTAssertFalse(router.route(pid: 42, frontmostPIDAtDown: 13, currentPID: 42,
                                    eligibleWindowIDs: [11], isAllowed: true))
        XCTAssertTrue(session.minimizations.isEmpty)
        XCTAssertEqual(session.restores, 0)
    }

    func testFrontmostAppWithoutVisibleWindowKeepsNativeRestoreOrLaunch() {
        let session = FakeDockClickSession()
        let router = DockClickActionRouter { session }
        router.setPaused(false)
        let cases: [Set<UInt32>?] = [nil, []]
        for evidence in cases {
            XCTAssertFalse(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                        eligibleWindowIDs: evidence, isAllowed: true))
        }
        XCTAssertTrue(session.minimizations.isEmpty)
        XCTAssertEqual(session.restores, 0)
    }

    func testMinimizeUsesTheDownCandidatesThenRestoresOnlyItsOwnedBatch() {
        let session = FakeDockClickSession()
        let router = DockClickActionRouter { session }
        var notices = 0
        router.onWillToggle = { notices += 1 }
        router.setPaused(false)
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                   eligibleWindowIDs: [11, 12], isAllowed: true))
        XCTAssertEqual(session.minimizations, [[11, 12]])
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 13, currentPID: 42,
                                   eligibleWindowIDs: [88], isAllowed: true))
        XCTAssertEqual(session.restores, 1)
        XCTAssertFalse(session.restoreActivatesOriginal)
        XCTAssertEqual(notices, 2)
    }

    func testManuallyRestoredOwnedWindowsAreMinimizedAgainInsteadOfNoOpRestore() {
        let session = FakeDockClickSession()
        let router = DockClickActionRouter { session }
        router.setPaused(false)
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                   eligibleWindowIDs: [11, 12], isAllowed: true))
        // Native Dock or a minimized-window thumbnail restored 11; ownership
        // still exists, but the new down snapshot proves it is visible again.
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                   eligibleWindowIDs: [11], isAllowed: true))
        XCTAssertEqual(session.minimizations, [[11, 12], [11]])
        XCTAssertEqual(session.restores, 0)
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                   eligibleWindowIDs: [], isAllowed: true))
        XCTAssertEqual(session.restores, 1)
    }

    func testChangedFrontmostPausedAppAndBusyBatchNeverSubmitAgain() {
        let session = FakeDockClickSession()
        let router = DockClickActionRouter { session }
        router.setPaused(false)
        XCTAssertFalse(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 13,
                                    eligibleWindowIDs: [11], isAllowed: true))
        XCTAssertFalse(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                    eligibleWindowIDs: [11], isAllowed: false))
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                   eligibleWindowIDs: [11], isAllowed: true))
        session.isBusy = true
        XCTAssertFalse(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                    eligibleWindowIDs: [11], isAllowed: true))
        XCTAssertEqual(session.minimizations.count, 1)
    }

    func testDisablingPreservesOwnershipButStopDiscardsWithoutRestoring() {
        let session = FakeDockClickSession()
        let router = DockClickActionRouter { session }
        router.setPaused(false)
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                   eligibleWindowIDs: [11], isAllowed: true))
        router.setPaused(true)
        XCTAssertTrue(session.paused)
        XCTAssertTrue(router.hasOwnedWindows(pid: 42))
        XCTAssertFalse(router.route(pid: 42, frontmostPIDAtDown: 13, currentPID: 42,
                                    eligibleWindowIDs: [], isAllowed: true))
        router.setPaused(false)
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 13, currentPID: 42,
                                   eligibleWindowIDs: [], isAllowed: true))
        router.stop()
        XCTAssertEqual(session.stops, 1)
        XCTAssertEqual(session.restores, 1, "Stopping itself must not restore windows")
        XCTAssertFalse(router.hasOwnedWindows(pid: 42))
    }

    func testTerminatedApplicationLosesItsOldProcessRestoreEligibility() {
        let session = FakeDockClickSession()
        let router = DockClickActionRouter { session }
        router.setPaused(false)
        XCTAssertTrue(router.route(pid: 42, frontmostPIDAtDown: 42, currentPID: 42,
                                   eligibleWindowIDs: [11], isAllowed: true))
        router.discard(pid: 42)
        XCTAssertFalse(router.hasOwnedWindows(pid: 42))
        XCTAssertFalse(router.route(pid: 42, frontmostPIDAtDown: 13, currentPID: 42,
                                    eligibleWindowIDs: [], isAllowed: true))
        XCTAssertEqual(session.restores, 0)
    }
}

final class DockClickScreenRegionsTests: XCTestCase {
    func testContentClicksCannotScheduleHitTestingAndScreenEdgesCan() {
        let regions = DockClickScreenRegions.make(screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)],
                                                  coordinatePivotY: 900)
        var gesture = DockClickGesture()
        XCTAssertNil(gesture.begin(at: CGPoint(x: 720, y: 450), time: 1, frontmostPID: 42,
                                   isPlainSingleClick: true, candidateRegions: regions))
        for point in [CGPoint(x: 10, y: 450), CGPoint(x: 1430, y: 450), CGPoint(x: 720, y: 895)] {
            XCTAssertNotNil(gesture.begin(at: point, time: 1, frontmostPID: 42,
                                          isPlainSingleClick: true, candidateRegions: regions))
        }
        XCTAssertNil(gesture.begin(at: CGPoint(x: 720, y: 10), time: 1, frontmostPID: 42,
                                   isPlainSingleClick: true, candidateRegions: regions))
    }

    func testDisplaysAboveAndLeftOfPrimaryUseThePrimaryCoordinatePivot() {
        let regions = DockClickScreenRegions.make(screens: [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 1440, height: 900),
            CGRect(x: -1440, y: 0, width: 1440, height: 900),
        ], coordinatePivotY: 900)
        XCTAssertTrue(regions.contains { $0.contains(CGPoint(x: 720, y: -5)) })
        XCTAssertFalse(regions.contains { $0.contains(CGPoint(x: 720, y: -450)) })
        XCTAssertTrue(regions.contains { $0.contains(CGPoint(x: -720, y: 895)) })
        XCTAssertFalse(regions.contains { $0.contains(CGPoint(x: -720, y: 450)) })
    }

    func testUnknownScreenGeometryDoesNotEnableGlobalHitTesting() {
        XCTAssertTrue(DockClickScreenRegions.make(screens: [.zero], coordinatePivotY: 0).isEmpty)
        XCTAssertTrue(DockClickScreenRegions.make(screens: [.infinite], coordinatePivotY: 0).isEmpty)
        var gesture = DockClickGesture()
        XCTAssertNil(gesture.begin(at: .zero, time: 1, frontmostPID: 42,
                                   isPlainSingleClick: true, candidateRegions: []))
    }
}

@MainActor
private final class FakeDockClickSession: DockClickWindowSession {
    var hasMinimizedWindows = false
    var isBusy = false
    var paused = false
    var minimizations: [Set<UInt32>] = []
    var restores = 0
    var restoreActivatesOriginal = false
    var stops = 0

    func minimize(processIdentifier _: Int32?, eligibleWindowIDs: Set<UInt32>?,
                  completion: (() -> Void)?) -> Bool {
        guard !paused else { return false }
        minimizations.append(eligibleWindowIDs ?? [])
        hasMinimizedWindows = true
        completion?()
        return true
    }

    func restore(activateOriginal: Bool, completion: (() -> Void)?) -> Bool {
        guard !paused else { return false }
        restores += 1
        restoreActivatesOriginal = activateOriginal
        hasMinimizedWindows = false
        completion?()
        return true
    }

    func setPaused(_ value: Bool) {
        paused = value
    }

    func stop() {
        stops += 1; hasMinimizedWindows = false
    }
}
