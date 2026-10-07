@testable import BlinkerApp
import BlinkerHelperXPC
import XCTest

/// Low power mode: pmset -g parsing, the whitelist contract shared with
/// the daemon, and the controller's register → write → mirror state
/// machine. Every system boundary (SMAppService, XPC, pmset) is injected.
@MainActor
final class LowPowerModeTests: XCTestCase {

    // MARK: Status parsing

    func testParserReadsTheSystemWideLine() {
        let output = """
        System-wide power settings:
        Currently in use:
         standby              1
         lowpowermode         1
         displaysleep         10
        """
        XCTAssertEqual(LowPowerStatusParser.parse(output), true)
    }

    func testParserReadsZeroAsOff() {
        XCTAssertEqual(LowPowerStatusParser.parse(" lowpowermode         0\n"), false)
    }

    func testParserReturnsNilWithoutTheKey() {
        XCTAssertNil(LowPowerStatusParser.parse(" standby              1\n"))
        XCTAssertNil(LowPowerStatusParser.parse(""))
    }

    // MARK: Allowlist contract

    func testAllowlistPermitsExactlyTheTwoVectors() {
        XCTAssertTrue(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "1"]))
        XCTAssertTrue(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "0"]))
    }

    func testAllowlistRejectsEverythingElse() {
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "2"]))
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-b", "lowpowermode", "1"]))
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/bin/sh",
            arguments: ["-a", "lowpowermode", "1"]))
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "1", ";", "rm", "-rf", "/"]))
        XCTAssertFalse(LowPowerCommand.isAllowed(executable: "/usr/bin/pmset", arguments: []))
    }

    func testServiceNamesDeriveFromTheAppIdentity() {
        XCTAssertEqual(LowPowerHelperNames.machServiceName(appBundleID: "com.example.App"),
                       "com.example.App.LowPowerHelper")
        XCTAssertEqual(LowPowerHelperNames.plistName(appBundleID: "com.example.App"),
                       "com.example.App.LowPowerHelper.plist")
    }

    // MARK: Daemon launch discovery

    /// The label comes from the sibling <executable>.plist; the executable
    /// path itself must be absolute (the argv[0] failure mode is covered by
    /// the dyld-based executablePath() contract below).
    func testServiceNameReadsTheSiblingPlist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("com.example.Helper")
        try Data().write(to: executable)
        let plist: NSDictionary = ["Label": "com.example.Helper"]
        XCTAssertTrue(plist.write(to: executable.appendingPathExtension("plist"), atomically: true))
        XCTAssertEqual(
            LowPowerHelperLaunch.serviceNameFromSiblingPlist(executablePath: executable.path),
            "com.example.Helper"
        )
    }

    func testServiceNameRejectsMissingOrMalformedPlists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("helper")
        try Data().write(to: executable)
        XCTAssertNil(LowPowerHelperLaunch.serviceNameFromSiblingPlist(
            executablePath: executable.path), "No plist next to the binary")
        let malformed: NSDictionary = ["BundleProgram": "x"]
        XCTAssertTrue(malformed.write(to: executable.appendingPathExtension("plist"),
                                      atomically: true))
        XCTAssertNil(LowPowerHelperLaunch.serviceNameFromSiblingPlist(
            executablePath: executable.path), "A plist without Label is useless")
    }

    /// Guards the launchd regression: argv[0] under launchd is the relative
    /// BundleProgram string with cwd `/`, so the discovery must not consult
    /// argv[0] — the dyld query always yields an absolute path.
    func testExecutablePathIsAbsolute() {
        XCTAssertTrue(LowPowerHelperLaunch.executablePath().hasPrefix("/"),
                      "The dyld executable path never depends on argv[0] or the cwd")
    }

    // MARK: Controller state machine

    private func makeController(
        pmset: String = " lowpowermode 0\n",
        daemon: LowPowerController.DaemonStatus = .enabled,
        helperStatus: Int = 0,
        openSettings: @escaping () -> Void = {}
    ) -> LowPowerController {
        LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemOutput: { pmset },
            registerDaemon: { daemon },
            callHelper: { _, reply in reply(helperStatus) },
            openLoginItemsSettings: openSettings
        )
    }

    private func flush() {
        let expectation = expectation(description: "helper reply delivered")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }

    func testRefreshMirrorsTheSystemState() {
        let controller = makeController(pmset: " lowpowermode 1\n")
        controller.refresh()
        XCTAssertTrue(controller.isOn)
        XCTAssertNil(controller.issue)
    }

    func testToggleWritesAndMirrorsTheNewState() {
        var output = " lowpowermode 0\n"
        var requested: [Bool] = []
        let controller = LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemOutput: { output },
            registerDaemon: { .enabled },
            callHelper: { enabled, reply in
                requested.append(enabled)
                output = " lowpowermode \(enabled ? 1 : 0)\n"
                reply(0)
            },
            openLoginItemsSettings: {}
        )
        controller.refresh()
        XCTAssertFalse(controller.isOn)
        controller.setLowPowerMode(true)
        flush()
        XCTAssertEqual(requested, [true])
        XCTAssertTrue(controller.isOn)
        XCTAssertNil(controller.issue)
        XCTAssertFalse(controller.isApplying)
    }

    func testApprovalRequiredOpensSettingsAndKeepsState() {
        var opened = 0
        let controller = makeController(daemon: .requiresApproval,
                                        openSettings: { opened += 1 })
        controller.refresh()
        controller.setLowPowerMode(true)
        XCTAssertEqual(controller.issue, .approvalRequired)
        XCTAssertEqual(opened, 1, "The login-items pane opens so the approval is one click away")
        XCTAssertFalse(controller.isOn, "No write happened, so the switch keeps the system state")
    }

    func testUnpackagedAppSurfacesHelperUnavailable() {
        let controller = makeController(daemon: .unavailable)
        controller.setLowPowerMode(true)
        XCTAssertEqual(controller.issue, .helperUnavailable)
    }

    func testFailedWriteFlagsAndSnapsBack() {
        let controller = makeController(pmset: " lowpowermode 0\n",
                                        daemon: .enabled, helperStatus: 1)
        controller.refresh()
        controller.setLowPowerMode(true)
        flush()
        XCTAssertEqual(controller.issue, .writeFailed)
        XCTAssertFalse(controller.isOn, "A failed write snaps the switch back to the system state")
        XCTAssertFalse(controller.isApplying)
    }

    func testReentryWhileApplyingIsDropped() {
        let gate = DispatchSemaphore(value: 0)
        var calls = 0
        let controller = LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemOutput: { " lowpowermode 0\n" },
            registerDaemon: { .enabled },
            callHelper: { _, reply in
                calls += 1
                DispatchQueue.global().async {
                    gate.wait()
                    reply(0)
                }
            },
            openLoginItemsSettings: {}
        )
        controller.setLowPowerMode(true)
        controller.setLowPowerMode(false)
        XCTAssertEqual(calls, 1, "A second toggle lands while the first write is in flight")
        gate.signal()
        flush()
    }
}
