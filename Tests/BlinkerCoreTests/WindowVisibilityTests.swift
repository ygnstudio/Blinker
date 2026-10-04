@testable import BlinkerCore
import Combine
import XCTest

@MainActor
final class WindowVisibilityTests: XCTestCase {
    private enum Call: Equatable { case minimize(Int32?, Set<UInt32>?); case restore(Bool) }
    private final class Backend: WindowMinimizationOperating {
        var calls: [Call] = []
        var tokens: [WindowVisibilityCancellation] = []
        var completion: (@MainActor (WindowVisibilityResult) -> Void)?
        var accepts = true
        var discards = 0

        func minimize(
            pid: Int32?,
            eligibleWindowIDs: Set<UInt32>?,
            cancellation: WindowVisibilityCancellation,
            completion: @escaping @MainActor (WindowVisibilityResult) -> Void
        ) -> Bool {
            accept(.minimize(pid, eligibleWindowIDs), token: cancellation, completion: completion)
        }

        func restore(activateOriginal: Bool, cancellation: WindowVisibilityCancellation,
                     completion: @escaping @MainActor (WindowVisibilityResult) -> Void) -> Bool {
            accept(.restore(activateOriginal), token: cancellation, completion: completion)
        }

        func discard() {
            discards += 1
        }

        private func accept(_ call: Call, token: WindowVisibilityCancellation,
                            completion: @escaping @MainActor (WindowVisibilityResult) -> Void) -> Bool {
            guard accepts else { return false }
            calls.append(call)
            tokens.append(token)
            self.completion = completion
            return true
        }

        func finish(owned: Int, failures: Int = 0) {
            let completion = completion
            self.completion = nil
            completion?(.init(ownedCount: owned, failures: failures))
        }
    }

    func testDesktopToggleRestoresOnlyAfterVerifiedMinimizationAndRequestsOriginalFocus() {
        let backend = Backend()
        let desktop = DesktopVisibilityController(session: WindowVisibilitySession(backend: backend))
        XCTAssertFalse(desktop.isDesktopShown)
        XCTAssertTrue(desktop.toggle())
        XCTAssertEqual(backend.calls, [.minimize(nil, nil)])
        XCTAssertFalse(desktop.isDesktopShown)
        XCTAssertTrue(desktop.isBusy)
        backend.finish(owned: 3)
        XCTAssertTrue(desktop.isDesktopShown)
        XCTAssertTrue(desktop.toggle())
        XCTAssertEqual(backend.calls.last, .restore(true))
        backend.finish(owned: 0)
        XCTAssertFalse(desktop.isDesktopShown)
        XCTAssertFalse(desktop.isBusy)
    }

    func testBusyToggleCannotEnqueueOverlappingTransactions() {
        let backend = Backend()
        let desktop = DesktopVisibilityController(session: WindowVisibilitySession(backend: backend))
        XCTAssertTrue(desktop.toggle())
        for _ in 0 ..< 1000 {
            XCTAssertFalse(desktop.toggle())
        }
        XCTAssertEqual(backend.calls.count, 1)
        backend.finish(owned: 2)
        XCTAssertTrue(desktop.toggle())
        for _ in 0 ..< 1000 {
            XCTAssertFalse(desktop.toggle())
        }
        XCTAssertEqual(backend.calls.count, 2)
        backend.finish(owned: 0)
    }

    func testPartialFailureRetainsRemainingOwnershipForNextRestore() {
        let backend = Backend()
        let session = WindowVisibilitySession(backend: backend)
        XCTAssertFalse(session.restore())
        XCTAssertTrue(session.minimize())
        backend.finish(owned: 2, failures: 1)
        XCTAssertTrue(session.hasMinimizedWindows)
        XCTAssertEqual(session.lastFailureCount, 1)
        XCTAssertTrue(session.restore())
        backend.finish(owned: 1, failures: 1)
        XCTAssertTrue(session.hasMinimizedWindows)
        XCTAssertTrue(session.restore())
        backend.finish(owned: 0)
        XCTAssertFalse(session.hasMinimizedWindows)
        XCTAssertEqual(session.lastFailureCount, 0)
    }

    func testNoSuccessfulWindowsDoesNotClaimDesktopIsShown() {
        let backend = Backend()
        let desktop = DesktopVisibilityController(session: WindowVisibilitySession(backend: backend))
        XCTAssertTrue(desktop.toggle())
        backend.finish(owned: 0, failures: 1)
        XCTAssertFalse(desktop.isDesktopShown)
        XCTAssertEqual(desktop.lastFailureCount, 1)
        XCTAssertTrue(desktop.toggle())
        XCTAssertEqual(backend.calls.last, .minimize(nil, nil))
    }

    func testDockEligibilityAndPIDPassUnchangedIncludingEmptySnapshot() {
        let backend = Backend()
        let session = WindowVisibilitySession(backend: backend)
        XCTAssertTrue(session.minimize(processIdentifier: 100, eligibleWindowIDs: [12, 13]))
        XCTAssertEqual(backend.calls.last, .minimize(100, [12, 13]))
        backend.finish(owned: 1)
        // Re-minimizing manually restored/new visible windows extends the same owned batch.
        XCTAssertTrue(session.minimize(processIdentifier: 100, eligibleWindowIDs: [14]))
        backend.finish(owned: 2)
        XCTAssertTrue(session.hasMinimizedWindows)
        XCTAssertTrue(session.minimize(processIdentifier: 100, eligibleWindowIDs: []))
        XCTAssertEqual(backend.calls.last, .minimize(100, []))
        backend.finish(owned: 2)
        XCTAssertTrue(session.restore())
        XCTAssertEqual(backend.calls.last, .restore(false))
    }

    func testPauseCancelsFurtherWritesButKeepsPartialSuccessEligibleForRestore() {
        let backend = Backend()
        let session = WindowVisibilitySession(backend: backend)
        XCTAssertTrue(session.minimize())
        session.setPaused(true)
        XCTAssertTrue(backend.tokens[0].isCancelled)
        backend.finish(owned: 1)
        XCTAssertTrue(session.hasMinimizedWindows)
        XCTAssertFalse(session.restore())
        XCTAssertEqual(backend.discards, 0)
        session.setPaused(false)
        XCTAssertTrue(session.restore())
        backend.finish(owned: 0)
        XCTAssertFalse(session.hasMinimizedWindows)
    }

    func testCancelPendingDoesNotDiscardOrPermanentlyPauseTheSession() {
        let backend = Backend()
        let session = WindowVisibilitySession(backend: backend)
        XCTAssertTrue(session.minimize())
        session.cancelPending()
        XCTAssertTrue(backend.tokens[0].isCancelled)
        backend.finish(owned: 1)
        XCTAssertTrue(session.hasMinimizedWindows)
        XCTAssertEqual(backend.discards, 0)
        XCTAssertTrue(session.restore())
    }

    func testStopOrSpaceInvalidationRejectsLateOwnershipWithoutRestoringWindows() {
        let backend = Backend()
        let session = WindowVisibilitySession(backend: backend)
        XCTAssertTrue(session.minimize())
        session.stop()
        XCTAssertTrue(backend.tokens[0].isCancelled)
        XCTAssertEqual(backend.discards, 1)
        XCTAssertFalse(session.hasMinimizedWindows)
        XCTAssertFalse(session.minimize(), "The old in-flight slot is retained until it returns")
        backend.finish(owned: 3)
        XCTAssertFalse(session.hasMinimizedWindows)
        XCTAssertFalse(session.isBusy)
        XCTAssertFalse(session.restore())
        XCTAssertTrue(session.minimize())
        XCTAssertEqual(backend.calls, [.minimize(nil, nil), .minimize(nil, nil)])
    }

    func testServiceRejectionDoesNotLeaveBusyStateOrInvokeCompletion() {
        let backend = Backend()
        backend.accepts = false
        let session = WindowVisibilitySession(backend: backend)
        var callbacks = 0
        XCTAssertFalse(session.minimize { callbacks += 1 })
        XCTAssertEqual(callbacks, 0)
        XCTAssertFalse(session.isBusy)
        XCTAssertFalse(session.hasMinimizedWindows)
        backend.accepts = true
        XCTAssertTrue(session.minimize { callbacks += 1 })
        backend.finish(owned: 1)
        XCTAssertEqual(callbacks, 1)
    }

    func testTimeoutCancelsWritesWithoutAddingWorkersOrLosingConfirmedOwnership() async {
        let backend = Backend()
        let session = WindowVisibilitySession(backend: backend, operationTimeout: 0.01)
        let expired = expectation(description: "Long-running transaction reports a failure")
        let observation = session.$lastFailureCount.filter { $0 > 0 }.prefix(1)
            .sink { _ in expired.fulfill() }
        XCTAssertTrue(session.minimize())
        await fulfillment(of: [expired], timeout: 1)
        XCTAssertTrue(backend.tokens[0].isCancelled)
        XCTAssertTrue(session.isBusy)
        for _ in 0 ..< 100 {
            XCTAssertFalse(session.minimize())
        }
        XCTAssertEqual(backend.calls.count, 1)
        backend.finish(owned: 1)
        XCTAssertTrue(session.hasMinimizedWindows)
        XCTAssertEqual(session.lastFailureCount, 1)
        XCTAssertFalse(session.isBusy)
        withExtendedLifetime(observation) {}
    }

    func testSurfaceMatchingRequiresUniqueFrameAndRejectsContradictoryTitles() {
        let frame = CGRect(x: 20, y: 30, width: 600, height: 400)
        let first = VisibleWindowSurface(id: 1, pid: 100, frame: frame, title: "First")
        let second = VisibleWindowSurface(id: 2, pid: 100, frame: frame, title: "Second")
        XCTAssertEqual(VisibleWindowSurface.matchingIndex(frame: frame, title: "First", in: [first]), 0)
        XCTAssertNil(VisibleWindowSurface.matchingIndex(frame: frame, title: "Wrong", in: [first]))
        XCTAssertNil(VisibleWindowSurface.matchingIndex(frame: frame, title: nil, in: [first, second]))
        XCTAssertEqual(
            VisibleWindowSurface.matchingIndex(frame: frame, title: "Second", in: [first, second]),
            1
        )
        var moved = frame
        moved.origin.x += 10
        XCTAssertNil(VisibleWindowSurface.matchingIndex(frame: moved, title: "First", in: [first]))
    }
}
