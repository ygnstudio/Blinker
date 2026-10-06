@testable import BlinkerApp
import XCTest

/// Trash listing and Apple Events error mapping: hidden entries and
/// directories count, a refused listing reads as nil rather than zero, and
/// script error dictionaries map to the row's two failure states.
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
            try? FileManager.default.removeItem(at: trashURL)
        }
        trashURL = nil
        try super.tearDownWithError()
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

    /// A listing the system refuses must not masquerade as an empty trash.
    func testItemCountForMissingDirectoryIsNil() {
        let missing = trashURL.appendingPathComponent("no-such-place")
        XCTAssertNil(SystemTrashInfo.itemCount(at: missing))
    }

    func testFailureMapsNilToSuccess() {
        XCTAssertNil(SystemTrashInfo.failure(from: nil))
    }

    func testFailureMapsNotPermittedToAutomationDenied() {
        let info: [AnyHashable: Any] = [NSAppleScript.errorNumber: NSNumber(value: -1743)]
        XCTAssertEqual(SystemTrashInfo.failure(from: info), .automationDenied)
    }

    func testFailureMapsScriptErrorToMessage() {
        let info: [AnyHashable: Any] = [
            NSAppleScript.errorNumber: NSNumber(value: -10000),
            NSAppleScript.errorMessage: "有项目正在使用。",
        ]
        XCTAssertEqual(SystemTrashInfo.failure(from: info), .failed("有项目正在使用。"))
    }

    func testFailureWithoutMessageFallsBackToGenericText() {
        let info: [AnyHashable: Any] = [NSAppleScript.errorNumber: NSNumber(value: -10000)]
        guard case .failed(let message) = SystemTrashInfo.failure(from: info) else {
            return XCTFail("expected a generic failure")
        }
        XCTAssertFalse(message.isEmpty)
    }

    /// The Finder errors when asked to empty an already-empty trash; the
    /// script must count first so that case becomes a silent success.
    func testEmptyTrashScriptShortCircuitsAnEmptyTrash() {
        XCTAssertTrue(SystemTrashInfo.emptyTrashScript.contains("count of items of trash"))
        XCTAssertTrue(SystemTrashInfo.emptyTrashScript.contains("empty trash"))
    }
}
