@testable import BlinkerApp
import BlinkerHelperXPC
import XCTest

@MainActor
final class LowPowerRecoveryTests: XCTestCase {
    private func flush() {
        let drained = expectation(description: "main actor callbacks drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    func testRepairWaitsUntilUnregistrationCompletes() {
        var registrations = 0
        var writes = 0
        var unregisterStarted = false
        var finishUnregister: (() -> Void)?
        let controller = LowPowerController(
            readSystemState: { false },
            registerDaemon: {
                registrations += 1
                return .enabled
            },
            unregisterDaemon: { completion in
                unregisterStarted = true
                finishUnregister = { completion(nil) }
            },
            callHelper: { _, reply in
                writes += 1
                reply(writes == 1 ? LowPowerHelperRejection.timedOut.rawValue : 0)
            }, openLoginItemsSettings: {}
        )
        controller.setLowPowerMode(true)
        flush()
        XCTAssertTrue(unregisterStarted)
        XCTAssertEqual(registrations, 1, "Do not register while the old service is being removed")
        XCTAssertEqual(writes, 1, "Do not write to a service that is being removed")
        XCTAssertTrue(controller.isApplying)
        controller.setLowPowerMode(false)
        XCTAssertEqual(registrations, 1, "A second user request cannot bypass pending cleanup")
        finishUnregister?()
        flush()
        flush()
        XCTAssertEqual(registrations, 2)
        XCTAssertEqual(writes, 2)
        XCTAssertFalse(controller.isApplying)
        XCTAssertNil(controller.issue)
    }

    func testHelperExecutionFailuresDoNotUnregisterHealthyService() {
        for status in [LowPowerHelperRejection.launchFailed.rawValue,
                       LowPowerHelperRejection.rejectedCommand.rawValue, 1] {
            var unregistrations = 0
            var writes = 0
            let controller = LowPowerController(
                readSystemState: { false },
                registerDaemon: { .enabled },
                unregisterDaemon: { completion in
                    unregistrations += 1
                    completion(nil)
                },
                callHelper: { _, reply in
                    writes += 1
                    reply(status)
                }, openLoginItemsSettings: {}
            )
            controller.setLowPowerMode(true)
            flush()
            flush()
            XCTAssertEqual(unregistrations, 0, "A helper reply proves the connection worked: \(status)")
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(controller.issue, .writeFailed)
            XCTAssertFalse(controller.isApplying)
        }
    }

    func testFailedUnregistrationStopsRecoveryAndRefreshesActualState() throws {
        var completion: ((Error?) -> Void)?
        var registrations = 0
        var writes = 0
        let controller = LowPowerController(
            readSystemState: { true },
            registerDaemon: {
                registrations += 1
                return .enabled
            },
            unregisterDaemon: { completion = $0 },
            callHelper: { _, reply in
                writes += 1
                reply(LowPowerHelperRejection.connectionFailed.rawValue)
            }, openLoginItemsSettings: {}
        )
        controller.setLowPowerMode(true)
        flush()
        XCTAssertTrue(controller.isApplying)
        let finish = try XCTUnwrap(completion)
        finish(NSError(domain: "LowPowerRecoveryTests", code: 1))
        flush()
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(writes, 1)
        XCTAssertFalse(controller.isApplying)
        XCTAssertEqual(controller.issue, .writeFailed)
        XCTAssertTrue(controller.isOn, "Failure still refreshes the real system state")
    }
}
