@testable import BlinkerApp
import XCTest

/// Trash listing and emptying against a temporary stand-in directory:
/// hidden entries count, subdirectories count as one item, and locked items
/// survive the sweep as failures instead of blocking it.
final class SystemTrashInfoTests: XCTestCase {
    private var trashURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        trashURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blinker.SystemTrashInfoTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let trashURL {
            unlockContents(of: trashURL)
            try? FileManager.default.removeItem(at: trashURL)
        }
        trashURL = nil
        try super.tearDownWithError()
    }

    /// A locked item cannot be removed — and neither can the temp directory
    /// at teardown — until the flag is cleared.
    private func unlockContents(of url: URL) {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? manager.setAttributes([.immutable: false], ofItemAtPath: item.path)
        }
    }

    private func makeItem(_ name: String, isDirectory: Bool = false) throws {
        let url = trashURL.appendingPathComponent(name)
        if isDirectory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try "nested".write(to: url.appendingPathComponent("inner.txt"),
                               atomically: true, encoding: .utf8)
        } else {
            try "payload".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func testItemCountIncludesHiddenFilesAndDirectories() throws {
        try makeItem("plain.txt")
        try makeItem(".hidden")
        try makeItem("folder", isDirectory: true)
        XCTAssertEqual(SystemTrashInfo.itemCount(at: trashURL), 3)
    }

    func testItemCountForMissingDirectoryIsZero() {
        let missing = trashURL.appendingPathComponent("no-such-place")
        XCTAssertEqual(SystemTrashInfo.itemCount(at: missing), 0)
    }

    func testEmptyDeletesEverything() throws {
        try makeItem("a.txt")
        try makeItem("b.txt")
        try makeItem("folder", isDirectory: true)
        let report = SystemTrashInfo.empty(at: trashURL)
        XCTAssertEqual(report, SystemTrashInfo.EmptyReport(emptied: 3, failed: 0))
        XCTAssertEqual(SystemTrashInfo.itemCount(at: trashURL), 0)
    }

    func testEmptyKeepsLockedItemsAndCountsThem() throws {
        try makeItem("free.txt")
        try makeItem("locked.txt")
        let locked = trashURL.appendingPathComponent("locked.txt")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        let report = SystemTrashInfo.empty(at: trashURL)
        XCTAssertEqual(report, SystemTrashInfo.EmptyReport(emptied: 1, failed: 1))
        XCTAssertEqual(SystemTrashInfo.itemCount(at: trashURL), 1)
    }

    func testEmptyMissingDirectoryReportsZero() {
        let missing = trashURL.appendingPathComponent("no-such-place")
        XCTAssertEqual(SystemTrashInfo.empty(at: missing),
                       SystemTrashInfo.EmptyReport(emptied: 0, failed: 0))
    }
}
