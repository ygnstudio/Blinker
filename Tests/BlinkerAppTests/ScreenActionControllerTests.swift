@testable import BlinkerApp
import Combine
import XCTest

@MainActor
final class ScreenActionControllerTests: XCTestCase {
    func testCommandRunsOffMainThreadAndRejectsOverlappingActions() async {
        let started = expectation(description: "background command started")
        let settled = expectation(description: "command completed")
        let gate = DispatchSemaphore(value: 0)
        let controller = ScreenActionController { action in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(action, .screenSaver)
            started.fulfill()
            XCTAssertEqual(gate.wait(timeout: .now() + 3), .success)
        }
        let subscription = controller.$running.dropFirst().filter { $0 == nil }
            .sink { _ in settled.fulfill() }
        controller.run(.screenSaver)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(controller.running, .screenSaver)
        controller.run(.displaySleep)
        XCTAssertEqual(controller.running, .screenSaver)
        gate.signal()
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertNil(controller.failed)
        XCTAssertEqual(controller.completed, .screenSaver)
        subscription.cancel()
    }

    func testFailureCanBeRetriedAndClearsStaleFeedback() async {
        let worker = RetryWorker()
        let controller = ScreenActionController { try worker.perform($0) }
        let failed = expectation(description: "failure reported")
        let first = controller.$running.dropFirst().filter { $0 == nil }.sink { _ in failed.fulfill() }
        controller.run(.displaySleep)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(controller.failed, .displaySleep)
        XCTAssertNil(controller.completed)
        first.cancel()

        let recovered = expectation(description: "retry completed")
        let second = controller.$running.dropFirst().filter { $0 == nil }.sink { _ in recovered.fulfill() }
        controller.run(.displaySleep)
        XCTAssertNil(controller.failed)
        await fulfillment(of: [recovered], timeout: 2)
        XCTAssertNil(controller.failed)
        XCTAssertEqual(controller.completed, .displaySleep)
        second.cancel()
    }

    private final class RetryWorker: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts = 0

        func perform(_: ScreenActionController.Action) throws {
            lock.lock()
            defer { lock.unlock() }
            attempts += 1
            if attempts == 1 {
                throw CocoaError(.fileReadUnknown)
            }
        }
    }
}
