@testable import BlinkerApp
import XCTest

/// Dark-mode switch: script shape, error mapping, and the controller's
/// optimistic-apply/revert cadence with an injected script channel.
@MainActor
final class SystemAppearanceToggleTests: XCTestCase {
    /// Thread-safe script log: the runner fires from a detached task.
    private final class ScriptLog: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var entries: [String] = []
        func add(_ script: String) {
            lock.lock()
            entries.append(script)
            lock.unlock()
        }
    }

    private func waitForIdle(_ controller: AppearanceToggleController) async throws {
        for _ in 0 ..< 200 {
            if !controller.isApplying { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("controller stayed busy")
    }

    /// Writes are explicit sets, not toggles, so retries stay idempotent.
    func testScriptSetsExplicitValue() {
        let dark = SystemAppearanceToggle.script(darkMode: true)
        XCTAssertTrue(dark.contains("System Events"))
        XCTAssertTrue(dark.contains("set dark mode to true"))
        XCTAssertTrue(SystemAppearanceToggle.script(darkMode: false).contains("set dark mode to false"))
    }

    func testFailureMapping() {
        XCTAssertNil(SystemAppearanceToggle.failure(from: nil))
        XCTAssertEqual(
            SystemAppearanceToggle.failure(from: [NSAppleScript.errorNumber: -1743]),
            .automationDenied
        )
        XCTAssertEqual(
            SystemAppearanceToggle.failure(from: [NSAppleScript.errorNumber: 1,
                                                  NSAppleScript.errorMessage: "出错了"]),
            .failed("出错了")
        )
        guard case .failed(let fallback) =
            SystemAppearanceToggle.failure(from: [NSAppleScript.errorNumber: 1]) else {
            return XCTFail("missing message should still map to .failed")
        }
        XCTAssertFalse(fallback.isEmpty)
    }

    func testInitialStateReadsInjectedValue() {
        XCTAssertTrue(AppearanceToggleController(readDarkMode: { true },
                                                 runScript: { _ in nil }).isDarkMode)
        XCTAssertFalse(AppearanceToggleController(readDarkMode: { false },
                                                  runScript: { _ in nil }).isDarkMode)
    }

    /// External changes (Control Center) land via refresh, which the theme
    /// notification and the panel's onAppear both call.
    func testRefreshSyncsWithDomain() {
        var dark = false
        let controller = AppearanceToggleController(readDarkMode: { dark },
                                                    runScript: { _ in nil })
        XCTAssertFalse(controller.isDarkMode)
        dark = true
        controller.refresh()
        XCTAssertTrue(controller.isDarkMode)
    }

    func testSuccessfulApplyKeepsNewState() async throws {
        let log = ScriptLog()
        let controller = AppearanceToggleController(readDarkMode: { false }, runScript: { script in
            log.add(script)
            return nil
        })
        controller.setDarkMode(true)
        try await waitForIdle(controller)
        XCTAssertTrue(controller.isDarkMode)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(log.entries, [SystemAppearanceToggle.script(darkMode: true)])
    }

    /// A refused consent reverts the optimistic flip to the real mode and
    /// surfaces the guidance state.
    func testDeniedApplyRevertsAndReports() async throws {
        let controller = AppearanceToggleController(readDarkMode: { false }, runScript: { _ in
            [NSAppleScript.errorNumber: -1743]
        })
        controller.setDarkMode(true)
        try await waitForIdle(controller)
        XCTAssertFalse(controller.isDarkMode)
        XCTAssertEqual(controller.failure, .automationDenied)
    }

    /// While a script is in flight (a consent prompt can pend for minutes)
    /// further toggles drop instead of stacking writes.
    func testReentrantApplyIsDropped() async throws {
        let log = ScriptLog()
        let gate = DispatchSemaphore(value: 0)
        let controller = AppearanceToggleController(readDarkMode: { false }, runScript: { script in
            log.add(script)
            gate.wait()
            return nil
        })
        controller.setDarkMode(true)
        for _ in 0 ..< 200 where log.entries.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(log.entries.count, 1)
        controller.setDarkMode(false)
        gate.signal()
        try await waitForIdle(controller)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertTrue(controller.isDarkMode)
    }
}
