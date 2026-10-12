@testable import BlinkerApp
import XCTest

/// Inject launches so tests never activate a screen saver or sleep the display.
final class SystemScreenActionsTests: XCTestCase {
    @MainActor
    func testScreenSaverLaunchesTheEngineApp() async throws {
        var recorded: [URL] = []
        try await SystemScreenActions.startScreenSaver { recorded.append($0) }
        XCTAssertEqual(recorded, [SystemScreenActions.screenSaverAppURL])
    }

    @MainActor
    func testScreenSaverLaunchFailureIsReportedToCaller() async {
        do {
            try await SystemScreenActions.startScreenSaver { _ in throw CocoaError(.fileNoSuchFile) }
            XCTFail("Expected the Launch Services error to propagate")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile)
        }
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
