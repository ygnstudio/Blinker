@testable import BlinkerApp
import BlinkerHelperXPC
import XCTest

/// Low power mode: native state reads, the allowlist contract shared with
/// the daemon, and the controller's register → write → mirror state
/// machine. Every system boundary (SMAppService, XPC, pmset) is injected.
@MainActor
final class LowPowerModeTests: XCTestCase {
    // MARK: Allowlist contract

    func testAllowlistPermitsExactlyTheTwoVectors() {
        XCTAssertTrue(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "1"]
        ))
        XCTAssertTrue(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "0"]
        ))
    }

    func testAllowlistRejectsEverythingElse() {
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "2"]
        ))
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-b", "lowpowermode", "1"]
        ))
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/bin/sh",
            arguments: ["-a", "lowpowermode", "1"]
        ))
        XCTAssertFalse(LowPowerCommand.isAllowed(
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "1", ";", "rm", "-rf", "/"]
        ))
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
            executablePath: executable.path
        ), "No plist next to the binary")
        let malformed: NSDictionary = ["BundleProgram": "x"]
        XCTAssertTrue(malformed.write(to: executable.appendingPathExtension("plist"),
                                      atomically: true))
        XCTAssertNil(LowPowerHelperLaunch.serviceNameFromSiblingPlist(
            executablePath: executable.path
        ), "A plist without Label is useless")
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
        systemState: Bool = false,
        daemon: LowPowerController.DaemonStatus = .enabled,
        helperStatus: Int = 0,
        openSettings: @escaping () -> Void = {}
    ) -> LowPowerController {
        LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemState: { systemState },
            registerDaemon: { daemon },
            callHelper: { _, reply in reply(helperStatus) },
            openLoginItemsSettings: openSettings
        )
    }

    /// Pumps pending MainActor continuations. The repair path hops the
    /// main queue once per attempt, so tests exercise one bounce per hop.
    private func flush(times: Int = 1) {
        for _ in 0 ..< times {
            let expectation = expectation(description: "helper reply delivered")
            DispatchQueue.main.async { expectation.fulfill() }
            wait(for: [expectation], timeout: 1)
        }
    }

    func testRefreshMirrorsTheSystemState() {
        let controller = makeController(systemState: true)
        controller.refresh()
        XCTAssertTrue(controller.isOn)
        XCTAssertNil(controller.issue)
    }

    func testToggleWritesAndMirrorsTheNewState() {
        var output = false
        var requested: [Bool] = []
        let controller = LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemState: { output },
            registerDaemon: { .enabled },
            callHelper: { enabled, reply in
                requested.append(enabled)
                output = enabled
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
        let controller = makeController(systemState: false,
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
            readSystemState: { false },
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

    // MARK: Registration self-repair

    /// The exact field failure: launchd vends the endpoint but the spawn
    /// dies before listening, so the write pends until the watchdog. The
    /// controller rebuilds the registration and the retry lands.
    func testUnreachableHelperRebuildsRegistrationAndRetries() {
        var output = false
        var registrations = 0
        var unregistrations = 0
        var writes = 0
        let controller = LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemState: { output },
            registerDaemon: {
                registrations += 1
                return .enabled
            },
            unregisterDaemon: { completion in
                unregistrations += 1
                completion(nil)
            },
            callHelper: { enabled, reply in
                writes += 1
                if writes == 1 {
                    reply(LowPowerHelperRejection.timedOut.rawValue)
                } else {
                    output = enabled
                    reply(0)
                }
            },
            openLoginItemsSettings: {}
        )
        controller.refresh()
        controller.setLowPowerMode(true)
        flush(times: 3)
        XCTAssertEqual(writes, 2, "The write is retried after the registration is rebuilt")
        XCTAssertEqual(unregistrations, 1)
        XCTAssertEqual(registrations, 2, "Re-registration re-evaluates the daemon status")
        XCTAssertTrue(controller.isOn)
        XCTAssertNil(controller.issue)
        XCTAssertFalse(controller.isApplying)
    }

    /// Rebuilding the registration can land on a fresh approval request
    /// (unregister clears the grant): the row explains and opens the pane.
    func testRepairLandingOnApprovalGuidesTheUser() {
        var daemon: LowPowerController.DaemonStatus = .enabled
        var opened = 0
        let controller = LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemState: { false },
            registerDaemon: {
                defer { daemon = .requiresApproval }
                return daemon
            },
            unregisterDaemon: { $0(nil) },
            callHelper: { _, reply in reply(LowPowerHelperRejection.connectionFailed.rawValue) },
            openLoginItemsSettings: { opened += 1 }
        )
        controller.setLowPowerMode(true)
        flush(times: 3)
        XCTAssertEqual(controller.issue, .approvalRequired)
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(controller.isApplying)
    }

    /// The retry budget is exactly one: a helper that stays unreachable
    /// surfaces writeFailed instead of looping or hanging the switch.
    func testRepeatedlyUnreachableHelperFlagsWriteFailed() {
        var unregistrations = 0
        var writes = 0
        let controller = LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemState: { false },
            registerDaemon: { .enabled },
            unregisterDaemon: { completion in
                unregistrations += 1
                completion(nil)
            },
            callHelper: { _, reply in
                writes += 1
                reply(LowPowerHelperRejection.timedOut.rawValue)
            },
            openLoginItemsSettings: {}
        )
        controller.setLowPowerMode(true)
        flush(times: 3)
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(unregistrations, 1)
        XCTAssertEqual(controller.issue, .writeFailed)
        XCTAssertFalse(controller.isApplying)
    }

    /// A genuine pmset failure (positive exit) proves the helper ran, so
    /// no repair is attempted — rebuilding a healthy registration would
    /// only cost the user their approval.
    func testPmsetFailureDoesNotRebuildRegistration() {
        var unregistrations = 0
        let controller = LowPowerController(
            appBundleID: "com.example.Blinker.tests",
            readSystemState: { false },
            registerDaemon: { .enabled },
            unregisterDaemon: { completion in
                unregistrations += 1
                completion(nil)
            },
            callHelper: { _, reply in reply(1) },
            openLoginItemsSettings: {}
        )
        controller.setLowPowerMode(true)
        flush()
        XCTAssertEqual(unregistrations, 0)
        XCTAssertEqual(controller.issue, .writeFailed)
    }
}
