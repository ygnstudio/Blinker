@testable import BlinkerApp
import XCTest

/// Screen actions are one-shot command lines; the injected runner records
/// what would have run. Availability probes depend on the host macOS and
/// stay out of scope here.
final class SystemScreenActionsTests: XCTestCase {
    func testScreenSaverLaunchesTheEngineApp() throws {
        var recorded: [(String, [String])] = []
        try SystemScreenActions.startScreenSaver { tool, args in
            recorded.append((tool, args))
        }
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.0, "/usr/bin/open")
        XCTAssertEqual(recorded.first?.1, [SystemScreenActions.screenSaverAppURL.path])
    }

    func testDisplaySleepUsesPmsetWithoutSleepingTheMac() throws {
        var recorded: [(String, [String])] = []
        try SystemScreenActions.sleepDisplays { tool, args in
            recorded.append((tool, args))
        }
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.0, "/usr/bin/pmset")
        XCTAssertEqual(recorded.first?.1, ["displaysleepnow"])
    }
}
