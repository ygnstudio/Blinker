@testable import BlinkerCore
import XCTest

/// Tests for the workspace models and persistence. Capture/restore touch
/// CGWindowList and AX and are covered by manual verification.
final class WorkspaceStoreTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "WorkspaceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    private func sampleEntry(_ bundleID: String, originX: CGFloat) -> WorkspaceEntry {
        WorkspaceEntry(
            bundleIdentifier: bundleID,
            appName: bundleID,
            frame: CGRect(x: originX, y: 0, width: 800, height: 600)
        )
    }

    /// Waits for one async store operation to finish. Capture runs on the
    /// AX work queue and lands on the main thread, which `wait(for:)` serves.
    private func waitForSave(_ store: WorkspaceStore, named name: String) {
        let saved = expectation(description: "save \(name) completed")
        store.saveCurrentLayout(named: name) { saved.fulfill() }
        wait(for: [saved], timeout: 10)
    }

    func testSavedWorkspaceCodableRoundTrip() throws {
        let workspace = SavedWorkspace(
            name: "写代码",
            entries: [
                sampleEntry("com.apple.Safari", originX: 0),
                sampleEntry("com.apple.Xcode", originX: 800),
            ]
        )
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(SavedWorkspace.self, from: data)

        XCTAssertEqual(decoded, workspace)
        XCTAssertEqual(decoded.entries.count, 2)
        XCTAssertEqual(decoded.entries[1].frame.maxX, 1600)
    }

    func testSaveReplacesSameName() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WorkspaceStore(defaults: defaults)
        XCTAssertEqual(store.workspaces.count, 0)

        waitForSave(store, named: "写代码")
        waitForSave(store, named: "写代码")

        XCTAssertEqual(store.workspaces.count, 1, "same name overwrites instead of duplicating")
    }

    func testWorkspacesRoundTripThroughDefaults() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WorkspaceStore(defaults: defaults)
        waitForSave(store, named: "写代码")
        waitForSave(store, named: "开会")
        let firstID = store.workspaces[0].id

        let reloaded = WorkspaceStore(defaults: defaults)
        XCTAssertEqual(reloaded.workspaces.map(\.name), ["写代码", "开会"])
        XCTAssertEqual(reloaded.workspaces[0].id, firstID)
    }

    func testRemoveAndRestoreUnknownID() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WorkspaceStore(defaults: defaults)
        waitForSave(store, named: "写代码")

        let restoredUnknown = expectation(description: "unknown id restores nothing")
        store.restore(id: UUID()) { restored in
            XCTAssertEqual(restored, 0, "unknown ID restores nothing")
            restoredUnknown.fulfill()
        }
        wait(for: [restoredUnknown], timeout: 10)

        store.remove(id: UUID())
        XCTAssertEqual(store.workspaces.count, 1, "removing an unknown ID is a no-op")

        store.remove(id: store.workspaces[0].id)
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertTrue(WorkspaceStore(defaults: defaults).workspaces.isEmpty)
    }

    func testCaptureFilteringLogic() {
        // Pure verification of the minimum-size rule via the constant, since
        // the CGWindowList walk itself needs a live session.
        XCTAssertGreaterThan(WorkspaceManager.minimumCaptureSize.width, 0)
        XCTAssertGreaterThan(WorkspaceManager.minimumCaptureSize.height, 0)
        XCTAssertEqual(SpaceSwitcher.Direction.previous.keyCode, 123)
        XCTAssertEqual(SpaceSwitcher.Direction.next.keyCode, 124)
    }
}
