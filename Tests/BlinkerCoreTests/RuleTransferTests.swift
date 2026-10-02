@testable import BlinkerCore
import Darwin
import XCTest

@MainActor
final class RuleTransferTests: XCTestCase {
    func testBackupRoundTripRetainsHoverAndEnhancedClickSettings() throws {
        var rule = AppRule(bundleIdentifier: "one", displayName: "One", closeAction: .quitApp,
                           isHoverEnabled: false)
        rule.setAction(.restorePreviousFrame, button: .zoom, variant: .optionLeft)
        XCTAssertEqual(try RuleTransfer.decode(RuleTransfer.encode([rule])), [rule])
    }

    func testCompactImportRemainsRestorableAfterExportNearSizeLimit() throws {
        let source = (0 ..< 1000).map {
            ["bundleIdentifier": "test.app.\($0)", "displayName": String(repeating: "x", count: 900)]
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "rules": source])
        let rules = try RuleTransfer.decode(data)
        let exported = try RuleTransfer.encode(rules)
        XCTAssertLessThanOrEqual(exported.count, RuleTransfer.maximumBytes)
        XCTAssertEqual(try RuleTransfer.decode(exported), rules)
    }

    func testExportRejectsInvalidRules() {
        let rule = AppRule(bundleIdentifier: "one", displayName: "One")
        XCTAssertThrowsError(try RuleTransfer.encode([rule, rule]))
        XCTAssertThrowsError(try RuleTransfer.encode([AppRule(bundleIdentifier: " ", displayName: "One")]))
        let ambiguous = AppRule(bundleIdentifier: "one", displayName: "One",
                                extraVariantActions: [.close: [.left: .quitApp]])
        XCTAssertThrowsError(try RuleTransfer.encode([ambiguous]))
    }

    func testExportRejectsTooManyRulesAndOversizedUTF8Data() {
        let rules = (0 ... RuleTransfer.maximumRules).map {
            AppRule(bundleIdentifier: "test.app.\($0)", displayName: "App \($0)")
        }
        XCTAssertThrowsError(try RuleTransfer.encode(rules))
        let oversized = AppRule(bundleIdentifier: "one",
                                displayName: String(repeating: "🟢", count: RuleTransfer.maximumBytes / 4))
        XCTAssertThrowsError(try RuleTransfer.encode([oversized]))
    }

    func testRejectedExportLeavesExistingBackupRestorable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rules.json")
        let original = [AppRule(bundleIdentifier: "one", displayName: "One")]
        let backup = try RuleTransfer.encode(original)
        try backup.write(to: file, options: .atomic)
        let oversized = AppRule(bundleIdentifier: "two",
                                displayName: String(repeating: "x", count: RuleTransfer.maximumBytes))
        XCTAssertThrowsError(try RuleTransfer.encode([oversized]).write(to: file, options: .atomic))
        XCTAssertEqual(try Data(contentsOf: file), backup)
        XCTAssertEqual(try RuleTransfer.read(from: file), original)
    }

    func testImportRejectsDuplicateAppsFutureVersionsAndOversizedFiles() throws {
        let rule = AppRule(bundleIdentifier: "one", displayName: "One")
        XCTAssertThrowsError(try RuleTransfer.decode(uncheckedArchive([rule, rule])))
        XCTAssertThrowsError(try RuleTransfer.decode(Data(#"{"version":2,"rules":[]}"#.utf8)))
        XCTAssertThrowsError(try RuleTransfer.decode(Data(repeating: 0, count: 1_048_577)))
        XCTAssertThrowsError(try RuleTransfer.decode(Data("broken".utf8)))
    }

    func testFileImportReadsOnlyRegularBoundedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rules.json")
        let rule = AppRule(bundleIdentifier: "one", displayName: "One")
        try RuleTransfer.encode([rule]).write(to: file)
        XCTAssertEqual(try RuleTransfer.read(from: file), [rule])
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(RuleTransfer.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try RuleTransfer.read(from: file))
        XCTAssertThrowsError(try RuleTransfer.read(from: directory))
        let pipe = directory.appendingPathComponent("pipe.json")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try RuleTransfer.read(from: pipe), "a pipe must not block while opening")
    }

    func testImportRejectsUnknownActionsAndHiddenLeftClickOverrides() throws {
        let unknown = Data("""
        {"version":1,"rules":[{"bundleIdentifier":"one","displayName":"One","closeAction":"runShell"}]}
        """.utf8)
        XCTAssertThrowsError(try RuleTransfer.decode(unknown))
        let empty = AppRule(bundleIdentifier: " ", displayName: "One")
        XCTAssertThrowsError(try RuleTransfer.decode(uncheckedArchive([empty])))
        let ambiguous = AppRule(bundleIdentifier: "one", displayName: "One", closeAction: .closeWindow,
                                extraVariantActions: [.close: [.left: .quitApp]])
        XCTAssertThrowsError(try RuleTransfer.decode(uncheckedArchive([ambiguous])))
    }

    func testStoredDuplicateIDsAreQuarantinedBeforeRuleMerging() throws {
        let name = "Blinker.RuleTransferTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let rule = AppRule(bundleIdentifier: "one", displayName: "One")
        let data = try JSONEncoder().encode([rule, rule])
        defaults.set(data, forKey: "rules")
        let store = RuleStore(defaults: defaults, storageKey: "rules")
        XCTAssertTrue(store.rules.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "rules.corrupt-backup"), data)
        store.merge([rule])
        XCTAssertEqual(store.rules, [rule])
    }

    func testCopyPreservesDestinationIdentity() {
        let source = AppRule(bundleIdentifier: "one", displayName: "One", closeAction: .quitApp,
                             isHoverEnabled: false)
        let destination = AppRule(bundleIdentifier: "two", displayName: "Two")
        let copied = RuleTransfer.copying(source, to: destination)
        XCTAssertEqual(copied.id, "two")
        XCTAssertEqual(copied.displayName, "Two")
        XCTAssertEqual(copied.closeAction, .quitApp)
        XCTAssertFalse(copied.isHoverEnabled)
    }

    func testImportAndResetAreUndoableAndPersisted() throws {
        let name = "Blinker.RuleTransferTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RuleStore(defaults: defaults)
        let original = AppRule(bundleIdentifier: "one", displayName: "One", closeAction: .quitApp)
        store.upsert(original)
        let extra = AppRule(bundleIdentifier: "two", displayName: "Two")
        var modified = original
        modified.isHoverEnabled = false
        store.merge([modified, extra])
        XCTAssertEqual(store.rules, [modified, extra])
        store.undo()
        XCTAssertEqual(store.rules, [original])
        XCTAssertEqual(RuleStore(defaults: defaults).rules, [original])
        store.redo()
        XCTAssertEqual(store.rules, [modified, extra])
        store.reset(bundleIdentifier: "one")
        XCTAssertNil(store.rules[0].closeAction)
        XCTAssertTrue(store.rules[0].isHoverEnabled)
        store.undo()
        XCTAssertEqual(store.rules, [modified, extra])
        store.remove(bundleIdentifier: "two")
        XCTAssertFalse(store.canRedo)
    }

    private func uncheckedArchive(_ rules: [AppRule]) throws -> Data {
        struct Archive: Encodable {
            let version = 1
            let rules: [AppRule]
        }
        return try JSONEncoder().encode(Archive(rules: rules))
    }
}
