import ApplicationServices
@testable import BlinkerCore
import XCTest

final class WindowActionDispatchTests: XCTestCase {
    func testOwnWindowMutationFromWorkerRunsOnMainThread() async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let finished = expectation(description: "own window action executed")
        let performer = DefaultWindowActionPerformer { action, _, pid in
            XCTAssertTrue(Thread.isMainThread, "in-process AX actions call AppKit synchronously")
            XCTAssertEqual(action, .action(.closeWindow))
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
            XCTAssertEqual(action, .action(.quitApp))
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
        var executed: [WindowActionRequest] = []
        let performer = DefaultWindowActionPerformer { action, _, _ in
            executed.append(action)
            return .completed
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let element = AXUIElementCreateApplication(ownPID)
        performer.perform(.quitApp, window: element, processIdentifier: ownPID)
        performer.perform(.hideApp, window: element, processIdentifier: ownPID)
        performer.perform(.minimize, window: element, processIdentifier: ownPID)
        XCTAssertEqual(executed, [.action(.minimize)])
    }

    @MainActor
    func testNativePressPreservesZoomAndFullScreenSubroles() {
        var executed: [WindowActionRequest] = []
        let performer = DefaultWindowActionPerformer { request, _, _ in
            executed.append(request)
            return .completed
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        for subrole in ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"] {
            performer.pressNativeButton(subrole: subrole, window: element, processIdentifier: pid)
        }
        performer.perform(.fullscreen, window: element, processIdentifier: pid)
        XCTAssertEqual(executed, [.nativeButton("AXCloseButton"), .nativeButton("AXMinimizeButton"),
                                  .nativeButton("AXZoomButton"), .nativeButton("AXFullScreenButton"),
                                  .action(.fullscreen)])
    }

    func testNativePressOnOwnWindowStillHopsToMainThread() async {
        let finished = expectation(description: "native press on main thread")
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let performer = DefaultWindowActionPerformer { request, _, pid in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(pid, ownPID)
            XCTAssertEqual(request, .nativeButton("AXZoomButton"))
            finished.fulfill()
            return .completed
        }
        DispatchQueue.global().async {
            performer.pressNativeButton(subrole: "AXZoomButton", window: AXUIElementCreateApplication(ownPID),
                                        processIdentifier: ownPID)
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    @MainActor
    func testNativePressRejectsUnrecognizedControls() {
        let performer = DefaultWindowActionPerformer { _, _, _ in
            XCTFail("only standard traffic controls may use the native path")
            return .completed
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        performer.pressNativeButton(subrole: "AXUnknownButton", window: AXUIElementCreateApplication(pid),
                                    processIdentifier: pid)
    }

    func testCompatibilityRecognizesZoomOnlyAndFullScreenWindows() {
        for greenAttribute in [kAXZoomButtonAttribute, kAXFullScreenButtonAttribute] {
            let available = Set([kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, greenAttribute])
            XCTAssertEqual(WindowCompatibility.availableButtons { available.contains($0) },
                           [.close, .minimize, .zoom])
        }
        XCTAssertEqual(WindowCompatibility.availableButtons { $0 == kAXCloseButtonAttribute }, [.close])
        XCTAssertTrue(WindowCompatibility.availableButtons { _ in false }.isEmpty)
    }
}
