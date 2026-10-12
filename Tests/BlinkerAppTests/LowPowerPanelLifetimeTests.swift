import AppKit
@testable import BlinkerApp
import BlinkerHelperXPC
import Combine
import SwiftUI
import XCTest

@MainActor
final class LowPowerPanelLifetimeTests: XCTestCase {
    func testRecreatedPanelsShareTheSameLowPowerOperation() throws {
        let presentation = try makePresentation()
        let first = presentation.makePanel().lowPower
        presentation.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        let reopened = presentation.makePanel().lowPower
        XCTAssertIdentical(first, reopened, "Closing the panel must not discard the recovery owner")
    }

    func testRecreatedPanelsShareTheSameScreenOperation() throws {
        let presentation = try makePresentation()
        let first = presentation.makePanel().screenActions
        presentation.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        XCTAssertIdentical(first, presentation.makePanel().screenActions)
    }

    func testPendingRecoverySurvivesHostingControllerReleaseAndReopen() throws {
        let repairStarted = expectation(description: "repair after panel closes")
        let settled = expectation(description: "retry completed")
        var initialReply: ((Int) -> Void)?
        var unregisterCompletion: ((Error?) -> Void)?
        var writes: [Bool] = []
        var output = false
        var lowPower: LowPowerController? = LowPowerController(
            readSystemState: { output },
            registerDaemon: { .enabled },
            unregisterDaemon: {
                unregisterCompletion = $0
                repairStarted.fulfill()
            },
            callHelper: { enabled, reply in
                writes.append(enabled)
                if writes.count == 1 {
                    initialReply = reply
                } else {
                    output = true
                    reply(0)
                }
            }, openLoginItemsSettings: {}
        )
        let presentation = try makePresentation(lowPower: lowPower)
        weak var operation: LowPowerController?
        operation = lowPower
        startWriteInTransientHost(presentation)
        lowPower = nil
        presentation.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        XCTAssertNotNil(operation, "Only the presentation owner keeps the operation alive")
        try XCTUnwrap(initialReply)(LowPowerHelperRejection.timedOut.rawValue)
        initialReply = nil
        wait(for: [repairStarted], timeout: 1)

        let reopened = NSHostingController(rootView: presentation.makePanel())
        XCTAssertIdentical(operation, reopened.rootView.lowPower)
        XCTAssertTrue(reopened.rootView.lowPower.isApplying)
        reopened.rootView.lowPower.setLowPowerMode(false)
        XCTAssertEqual(writes, [true], "Reopening cannot start an overlapping write")
        let subscription = reopened.rootView.lowPower.$isApplying.dropFirst().filter { !$0 }
            .sink { _ in settled.fulfill() }
        defer { subscription.cancel() }
        let finish = try XCTUnwrap(unregisterCompletion)
        DispatchQueue.global().async { finish(nil) }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(writes, [true, true])
        XCTAssertTrue(reopened.rootView.lowPower.isOn)
        XCTAssertNil(reopened.rootView.lowPower.issue)
    }

    private func makePresentation(lowPower: LowPowerController? = nil) throws -> MenuBarPresentation {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: 24)
        let suite = "LowPowerPanelLifetimeTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            await MainActor.run {
                NSStatusBar.system.removeStatusItem(item)
                defaults.removePersistentDomain(forName: suite)
            }
        }
        return MenuBarPresentation(
            item: item, monitor: SystemStatusMonitor(), audio: SystemAudioController(),
            scanner: BluetoothLEScanner(), preferences: MenuBarPreferences(defaults: defaults),
            onOpenApplications: {}, onOpenSettings: {}, onOpenMenuBarPage: { _ in },
            lowPower: lowPower
        )
    }

    private func startWriteInTransientHost(_ presentation: MenuBarPresentation) {
        weak var closedHost: NSHostingController<SystemStatusPanel>?
        autoreleasepool {
            let host = NSHostingController(rootView: presentation.makePanel())
            closedHost = host
            host.rootView.lowPower.setLowPowerMode(true)
        }
        XCTAssertNil(closedHost, "The old hosting controller must actually be released")
    }
}
