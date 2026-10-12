@testable import BlinkerApp
import Combine
import XCTest

/// Finder switches: domain semantics for absent keys, the write-then-
/// restart ordering, and the controller's failure surface. Each test runs
/// against its own throwaway defaults suite; the real CLI is injected out.
@MainActor
final class SystemFinderTogglesTests: XCTestCase {
    private func withStore(_ body: (UserDefaults) throws -> Void) throws {
        let name = "Blinker.SystemFinderTogglesTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    func testDesktopIconsDefaultToShownAndFollowTheKey() throws {
        try withStore { store in
            XCTAssertTrue(SystemFinderToggles.desktopIconsShown(in: store),
                          "An absent CreateDesktop key means the factory default: icons shown")
            store.set(false, forKey: SystemFinderToggles.desktopIconsKey)
            XCTAssertFalse(SystemFinderToggles.desktopIconsShown(in: store))
            store.set(true, forKey: SystemFinderToggles.desktopIconsKey)
            XCTAssertTrue(SystemFinderToggles.desktopIconsShown(in: store))
        }
    }

    func testHiddenFilesDefaultToHiddenAndFollowTheKey() throws {
        try withStore { store in
            XCTAssertFalse(SystemFinderToggles.hiddenFilesShown(in: store))
            store.set(true, forKey: SystemFinderToggles.hiddenFilesKey)
            XCTAssertTrue(SystemFinderToggles.hiddenFilesShown(in: store))
        }
    }

    func testExtensionsDefaultToHiddenAndFollowTheKey() throws {
        try withStore { store in
            // A suite's search list falls through to NSGlobalDomain, and
            // System Settings writes AppleShowAllExtensions to the GLOBAL
            // domain — so an absent-key assertion would depend on the host
            // machine. Finder resolves defaults the same way, which is why
            // the production read stays a plain bool(forKey:). Here we pin
            // the follow-the-key behavior with explicit values only.
            store.set(false, forKey: SystemFinderToggles.extensionsKey)
            XCTAssertFalse(SystemFinderToggles.extensionsShown(in: store))
            store.set(true, forKey: SystemFinderToggles.extensionsKey)
            XCTAssertTrue(SystemFinderToggles.extensionsShown(in: store))
        }
    }

    func testWriteRestartsFinderOnlyAfterASuccessfulWrite() throws {
        var commands: [(String, [String])] = []
        try SystemFinderToggles.setKey(SystemFinderToggles.desktopIconsKey, value: false) { tool, args in
            commands.append((tool, args))
        }
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands.first?.0, "/usr/bin/defaults")
        XCTAssertEqual(commands.first?.1,
                       ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"])
        XCTAssertEqual(commands.last?.0, "/usr/bin/killall")
        XCTAssertEqual(commands.last?.1, ["Finder"])
    }

    func testFailedWriteSkipsTheRestart() throws {
        struct Probe: Error {}
        var commands = 0
        XCTAssertThrowsError(
            try SystemFinderToggles.setKey(SystemFinderToggles.hiddenFilesKey, value: true) { _, _ in
                commands += 1
                throw Probe()
            }
        )
        XCTAssertEqual(commands, 1, "killall must not run when the write itself failed")
    }

    func testControllerAppliesValuesAndMirrorsTheDomain() throws {
        try withStore { store in
            let controller = FinderTogglesController(store: store) { key, value in
                store.set(value, forKey: key)
            }
            controller.refresh()
            XCTAssertTrue(controller.desktopIconsShown)
            XCTAssertFalse(controller.hiddenFilesShown)
            controller.setDesktopIconsShown(false)
            waitForWrite(controller)
            XCTAssertFalse(controller.desktopIconsShown)
            XCTAssertFalse(controller.lastWriteFailed)
            controller.setHiddenFilesShown(true)
            waitForWrite(controller)
            XCTAssertTrue(controller.hiddenFilesShown)
            controller.setExtensionsShown(true)
            waitForWrite(controller)
            XCTAssertTrue(controller.extensionsShown)
        }
    }

    func testControllerFlagsFailedWritesAndKeepsTheDomainState() throws {
        try withStore { store in
            struct Probe: Error {}
            let controller = FinderTogglesController(store: store) { _, _ in throw Probe() }
            controller.refresh()
            controller.setDesktopIconsShown(false)
            waitForWrite(controller)
            XCTAssertTrue(controller.lastWriteFailed)
            XCTAssertTrue(controller.desktopIconsShown,
                          "A failed write snaps the toggle back to what the domain says")
        }
    }

    func testSlowFinderWriteDoesNotBlockTheMainActor() throws {
        try withStore { store in
            let applied = expectation(description: "worker applied preference")
            var ranOnMainThread = true
            let controller = FinderTogglesController(store: store) { _, _ in
                ranOnMainThread = Thread.isMainThread
                Thread.sleep(forTimeInterval: 0.1)
                applied.fulfill()
            }
            let started = Date()
            controller.setHiddenFilesShown(true)
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(elapsed, 0.05, "A slow CLI must not hold the click handler")
            wait(for: [applied], timeout: 2)
            XCTAssertFalse(ranOnMainThread)
            waitForWrite(controller)
        }
    }

    private func waitForWrite(_ controller: FinderTogglesController) {
        guard controller.isApplying else { return }
        let settled = expectation(description: "preference write settled")
        let subscription = controller.$isApplying.filter { !$0 }.prefix(1)
            .sink { _ in settled.fulfill() }
        defer { subscription.cancel() }
        wait(for: [settled], timeout: 2)
    }
}
