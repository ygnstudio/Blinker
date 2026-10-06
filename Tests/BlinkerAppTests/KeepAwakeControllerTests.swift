@testable import BlinkerApp
import IOKit.pwr_mgt
import XCTest

/// Keep-awake holds its assertion through injected seams only: a real
/// assertion created in a test would keep the host awake past the suite.
@MainActor
final class KeepAwakeControllerTests: XCTestCase {
    @MainActor
    private final class Recorder {
        var created: [IOPMAssertionID] = []
        var released: [IOPMAssertionID] = []
        var nextID: IOPMAssertionID? = 42

        func make() -> KeepAwakeController {
            KeepAwakeController(create: { [self] in
                guard let nextID else { return nil }
                created.append(nextID)
                return nextID
            }, release: { [self] assertionID in
                released.append(assertionID)
            })
        }
    }

    func testToggleOnCreatesAssertionAndReportsActive() {
        let recorder = Recorder()
        let controller = recorder.make()
        controller.setActive(true)
        XCTAssertEqual(recorder.created, [42])
        XCTAssertTrue(controller.isActive)
    }

    func testToggleOnTwiceCreatesOnlyOnce() {
        let recorder = Recorder()
        let controller = recorder.make()
        controller.setActive(true)
        controller.setActive(true)
        XCTAssertEqual(recorder.created, [42])
    }

    func testToggleOffReleasesTheHeldAssertion() {
        let recorder = Recorder()
        let controller = recorder.make()
        controller.setActive(true)
        controller.setActive(false)
        XCTAssertEqual(recorder.released, [42])
        XCTAssertFalse(controller.isActive)
    }

    func testFailedCreationLeavesToggleOffAndStopIsHarmless() {
        let recorder = Recorder()
        recorder.nextID = nil
        let controller = recorder.make()
        controller.setActive(true)
        XCTAssertFalse(controller.isActive)
        controller.setActive(false)
        XCTAssertTrue(recorder.released.isEmpty)
    }

    func testToggleOffWithoutStartReleasesNothing() {
        let recorder = Recorder()
        let controller = recorder.make()
        controller.setActive(false)
        XCTAssertTrue(recorder.released.isEmpty)
    }
}
