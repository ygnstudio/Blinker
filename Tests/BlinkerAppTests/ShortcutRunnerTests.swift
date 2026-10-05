@testable import BlinkerApp
import XCTest

/// classify(status:stderr:) is the runner's pure core: exit zero always
/// wins, "not found" on stderr maps to the dedicated case, everything else
/// carries the trimmed message.
final class ShortcutRunnerTests: XCTestCase {
    private func failure(of result: Result<Void, ShortcutRunner.Failure>) -> ShortcutRunner.Failure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }

    func testZeroStatusIsSuccessEvenWithStderrNoise() {
        XCTAssertNil(failure(of: ShortcutRunner.classify(status: 0, stderr: "warning: something\n")))
    }

    func testNotFoundIsDetectedCaseInsensitively() {
        XCTAssertEqual(
            failure(of: ShortcutRunner.classify(status: 1,
                                                stderr: "Error: The shortcut \"清洁\" was Not Found.")),
            .notFound
        )
    }

    func testOtherFailuresCarryTrimmedStderr() {
        XCTAssertEqual(
            failure(of: ShortcutRunner.classify(status: 2, stderr: "  Error: permission denied.\n\n")),
            .failed("Error: permission denied.")
        )
    }

    func testEmptyStderrFallsBackToExitCode() {
        XCTAssertEqual(
            failure(of: ShortcutRunner.classify(status: 3, stderr: "   \n")),
            .failed("exit 3")
        )
    }
}
