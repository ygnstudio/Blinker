import ApplicationServices
@testable import BlinkerCore
import XCTest

final class WindowActionDispatchTests: XCTestCase {
    func testOwnWindowMutationFromWorkerRunsOnMainThread() async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let finished = expectation(description: "own window action executed")
        let performer = DefaultWindowActionPerformer { action, _, pid in
            XCTAssertTrue(Thread.isMainThread, "in-process AX actions call AppKit synchronously")
            XCTAssertEqual(action, .closeWindow)
            XCTAssertEqual(pid, ownPID)
            finished.fulfill()
            return .completed
        }
        DispatchQueue.global().async {
            performer.perform(.closeWindow, window: AXUIElementCreateApplication(ownPID),
                              processIdentifier: ownPID)
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testExternalWindowActionsStayOffMainThread() async {
        let externalPID = ProcessInfo.processInfo.processIdentifier + 1
        let finished = expectation(description: "external window action executed")
        let performer = DefaultWindowActionPerformer { action, _, pid in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(action, .quitApp)
            XCTAssertEqual(pid, externalPID)
            finished.fulfill()
            return .completed
        }
        DispatchQueue.global().async {
            performer.perform(.quitApp, window: AXUIElementCreateApplication(externalPID),
                              processIdentifier: externalPID)
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    @MainActor
    func testOwnApplicationCannotBeQuitOrHiddenThroughWindowActions() {
        var executed: [ButtonAction] = []
        let performer = DefaultWindowActionPerformer { action, _, _ in
            executed.append(action)
            return .completed
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let element = AXUIElementCreateApplication(ownPID)
        performer.perform(.quitApp, window: element, processIdentifier: ownPID)
        performer.perform(.hideApp, window: element, processIdentifier: ownPID)
        performer.perform(.minimize, window: element, processIdentifier: ownPID)
        XCTAssertEqual(executed, [.minimize])
    }
}
