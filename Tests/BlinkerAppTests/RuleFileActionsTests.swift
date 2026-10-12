@testable import BlinkerApp
import BlinkerCore
import Foundation
import XCTest

@MainActor
final class RuleFileActionsTests: XCTestCase {
    private let inputURL = URL(fileURLWithPath: "/rule-transfer-fixture.json")

    private func makeDefaults() throws -> UserDefaults {
        let suite = "Blinker.RuleFileActionsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeStore(storedData: Data? = nil) throws -> RuleStore {
        let defaults = try makeDefaults()
        if let storedData { defaults.set(storedData, forKey: "fixture.rules") }
        return RuleStore(defaults: defaults, storageKey: "fixture.rules")
    }

    private func makeFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("rules.json")
    }

    func testImportReportsProgressRejectsDuplicateAndMergesAsOneUndoableChange() async throws {
        let gate = DeferredFileResult<RuleTransfer.Document>()
        let actions = RuleFileActions(read: { _ in try await gate.read() })
        let store = try makeStore()
        let original = AppRule(bundleIdentifier: "fixture.original", displayName: "Original")
        store.upsert(original)
        let originalDefaults = GlobalButtonRules(actions: [.close: [.left: .minimize]])
        store.updateGlobalDefaults(originalDefaults)
        let previous = store.configurationSnapshot
        let task = try XCTUnwrap(actions.importRules(from: inputURL, into: store))
        await gate.waitUntilStarted()
        XCTAssertEqual(actions.state, .importing)
        XCTAssertTrue(actions.isBusy)
        XCTAssertNil(actions.importRules(from: inputURL, into: store))
        XCTAssertNil(actions.exportRules(store.configurationSnapshot, to: inputURL))
        let imported = [
            AppRule(bundleIdentifier: "fixture.one", displayName: "One"),
            AppRule(bundleIdentifier: "fixture.two", displayName: "Two"),
        ]
        let importedDefaults = GlobalButtonRules(actions: [.close: [.left: .quitApp]])
        await gate.resolve(.success(.init(rules: imported, globalDefaults: importedDefaults)))
        await task.value
        XCTAssertEqual(actions.state, .imported(2, includesDefaults: true))
        XCTAssertFalse(actions.isBusy)
        XCTAssertEqual(store.snapshot, [original] + imported)
        XCTAssertEqual(store.globalDefaults, importedDefaults)
        store.undo()
        XCTAssertEqual(store.configurationSnapshot, previous,
                       "One undo must restore both the application rules and global defaults")
        store.redo()
        XCTAssertEqual(store.snapshot, [original] + imported)
        XCTAssertEqual(store.globalDefaults, importedDefaults)
    }

    func testCancelledOldReadCannotMergeOrReplaceTheNewOperationsStatus() async throws {
        let oldGate = DeferredFileResult<RuleTransfer.Document>()
        let newGate = DeferredFileResult<RuleTransfer.Document>()
        let actions = RuleFileActions(read: { url in
            try await (url.lastPathComponent == "old.json" ? oldGate : newGate).read()
        })
        let store = try makeStore()
        let oldTask = try XCTUnwrap(actions.importRules(
            from: inputURL.deletingLastPathComponent().appendingPathComponent("old.json"), into: store
        ))
        await oldGate.waitUntilStarted()
        actions.cancel()
        XCTAssertEqual(actions.state, .idle)
        let newTask = try XCTUnwrap(actions.importRules(from: inputURL, into: store))
        await newGate.waitUntilStarted()
        let obsolete = RuleTransfer.Document(
            rules: [AppRule(bundleIdentifier: "fixture.old", displayName: "Old")],
            globalDefaults: GlobalButtonRules(actions: [.close: [.left: .quitApp]])
        )
        await oldGate.resolve(.success(obsolete))
        await oldTask.value
        XCTAssertEqual(store.configurationSnapshot, RuleConfiguration())
        XCTAssertEqual(actions.state, .importing)
        let current = AppRule(bundleIdentifier: "fixture.current", displayName: "Current")
        await newGate.resolve(.success(.init(rules: [current])))
        await newTask.value
        XCTAssertEqual(store.snapshot, [current])
        XCTAssertEqual(actions.state, .imported(1, includesDefaults: false))
    }

    func testReleasingTheControllerPreventsADeferredImport() async throws {
        let gate = DeferredFileResult<RuleTransfer.Document>()
        var actions: RuleFileActions? = RuleFileActions(read: { _ in try await gate.read() })
        let controllerExists = { [weak actions] in actions != nil }
        let store = try makeStore()
        let task = try XCTUnwrap(actions?.importRules(from: inputURL, into: store))
        await gate.waitUntilStarted()
        actions = nil
        XCTAssertFalse(controllerExists())
        let abandoned = AppRule(bundleIdentifier: "fixture.old", displayName: "Old")
        let document = RuleTransfer.Document(rules: [abandoned])
        await gate.resolve(.success(document))
        await task.value
        XCTAssertTrue(store.snapshot.isEmpty)
    }

    func testImportFailureKeepsExistingRulesAndReenablesFileActions() async throws {
        let actions = RuleFileActions(read: { _ in throw RuleTransfer.ImportError.invalidArchive })
        let store = try makeStore()
        let original = AppRule(bundleIdentifier: "fixture.original", displayName: "Original")
        store.upsert(original)
        let task = try XCTUnwrap(actions.importRules(from: inputURL, into: store))
        await task.value
        XCTAssertEqual(store.snapshot, [original])
        XCTAssertFalse(actions.isBusy)
        XCTAssertEqual(actions.state, .failed(RuleTransfer.ImportError.invalidArchive.localizedDescription))
    }

    func testEmptyAndIdenticalImportsReportNoChangesAndPreserveEarlierUndoHistory() async throws {
        let previous = AppRule(bundleIdentifier: "fixture.same", displayName: "Before")
        let current = AppRule(bundleIdentifier: "fixture.same", displayName: "After")
        for imported in [[], [current]] {
            let store = try makeStore()
            store.upsert(previous)
            store.upsert(current)
            let actions = RuleFileActions(read: { _ in .init(rules: imported) })
            let task = try XCTUnwrap(actions.importRules(from: inputURL, into: store))
            await task.value
            XCTAssertEqual(actions.state.message, String(localized: "规则没有变化。"))
            XCTAssertEqual(store.snapshot, [current])
            store.undo()
            XCTAssertEqual(store.snapshot, [previous])
            store.redo()
            XCTAssertEqual(store.snapshot, [current])
        }
    }

    func testCancellingAnExportKeepsTheWriteGateUntilTheWriterActuallyFinishes() async throws {
        let gate = DeferredFileResult<Void>()
        let output = SimulatedExportDestination()
        let actions = RuleFileActions(write: { configuration, _ in
            let name = configuration.rules[0].displayName
            if name == "Old" {
                try await gate.read()
            }
            await output.write(name)
        })
        let old = RuleConfiguration(rules: [AppRule(bundleIdentifier: "fixture.export", displayName: "Old")])
        let new = RuleConfiguration(rules: [AppRule(bundleIdentifier: "fixture.export", displayName: "New")])
        let task = try XCTUnwrap(actions.exportRules(old, to: inputURL))
        await gate.waitUntilStarted()
        actions.cancel()
        XCTAssertTrue(
            actions.isBusy,
            "A cancelled UI must not allow a second write over an unfinished export"
        )
        let overlapping = actions.exportRules(new, to: inputURL)
        XCTAssertNil(overlapping, "Both requests target the same file; the old write is still running")
        await overlapping?.value
        await gate.resolve(.success(()))
        await task.value
        let writesBeforeRetry = await output.writes
        XCTAssertEqual(writesBeforeRetry, ["Old"], "Without a gate, the write order becomes New then Old")
        XCTAssertEqual(actions.state, .idle)
        XCTAssertFalse(actions.isBusy)
        let retry = try XCTUnwrap(actions.exportRules(new, to: inputURL))
        await retry.value
        let finalWrites = await output.writes
        XCTAssertEqual(finalWrites, ["Old", "New"])
    }

    func testExportReportsProgressRejectsDuplicateAndReportsTheExportedCount() async throws {
        let gate = DeferredFileResult<Void>()
        let actions = RuleFileActions(write: { _, _ in try await gate.read() })
        let exported = AppRule(bundleIdentifier: "fixture.export", displayName: "Export")
        let rules = RuleConfiguration(rules: [exported])
        let task = try XCTUnwrap(actions.exportRules(rules, to: inputURL))
        await gate.waitUntilStarted()
        XCTAssertEqual(actions.state, .exporting)
        XCTAssertTrue(actions.isBusy)
        XCTAssertNil(actions.exportRules(rules, to: inputURL))
        await gate.resolve(.success(()))
        await task.value
        XCTAssertEqual(actions.state, .exported(1))
        XCTAssertFalse(actions.isBusy)
    }

    func testRejectedExportKeepsTheExistingBackupAndReportsFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rules.json")
        let original = Data("existing backup".utf8)
        try original.write(to: url)
        let actions = RuleFileActions()
        let invalid = AppRule(bundleIdentifier: " ", displayName: "Invalid")
        let task = try XCTUnwrap(actions.exportRules(RuleConfiguration(rules: [invalid]), to: url))
        await task.value
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(actions.state, .failed(RuleTransfer.ExportError.invalidRules.localizedDescription))
        XCTAssertFalse(actions.isBusy)
    }
}

extension RuleFileActionsTests {
    func testDefaultReaderImportsLegacyRulesWithoutReplacingGlobalDefaults() async throws {
        let url = try makeFileURL()
        let imported = AppRule(bundleIdentifier: "fixture.legacy", displayName: "Legacy",
                               closeAction: .hideApp)
        try RuleTransfer.encode([imported]).write(to: url)
        let store = try makeStore()
        let defaults = GlobalButtonRules(actions: [.close: [.left: .quitApp]])
        store.updateGlobalDefaults(defaults)
        let actions = RuleFileActions()

        let task = try XCTUnwrap(actions.importRules(from: url, into: store))
        await task.value
        XCTAssertEqual(store.snapshot, [imported])
        XCTAssertEqual(store.globalDefaults, defaults)
        XCTAssertEqual(actions.state, .imported(1, includesDefaults: false))
        store.undo()
        XCTAssertEqual(store.configurationSnapshot, RuleConfiguration(globalDefaults: defaults))
    }

    func testDefaultFileIOPreservesV2DefaultsAndInheritedSlots() async throws {
        let url = try makeFileURL()
        let defaults = GlobalButtonRules(actions: [
            .close: [.left: .quitApp], .zoom: [.longPressLeft: .maximize],
        ])
        var rule = AppRule(bundleIdentifier: "fixture.inherited", displayName: "Inherited")
        rule.setBinding(.inherit, button: .close, variant: .left)
        rule.setAction(ButtonAction.none, button: .close, variant: .right)
        let configuration = RuleConfiguration(rules: [rule], globalDefaults: defaults)
        let actions = RuleFileActions()
        let export = try XCTUnwrap(actions.exportRules(configuration, to: url))
        await export.value
        XCTAssertEqual(actions.state, .exported(1))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        XCTAssertEqual(try RuleTransfer.readConfiguration(from: url),
                       RuleTransfer.Document(rules: [rule], globalDefaults: defaults))

        let store = try makeStore()
        let imported = try XCTUnwrap(actions.importRules(from: url, into: store))
        await imported.value
        XCTAssertEqual(store.configurationSnapshot, configuration)
        XCTAssertEqual(actions.state, .imported(1, includesDefaults: true))
    }

    func testDefaultsOnlyConfigurationExportsAndImportsWithoutApplicationRules() async throws {
        let url = try makeFileURL()
        let source = try makeStore()
        let defaults = GlobalButtonRules(actions: [.minimize: [.left: .hideApp]])
        source.updateGlobalDefaults(defaults)
        let actions = RuleFileActions()
        let export = try XCTUnwrap(actions.exportRules(from: source, to: url))
        await export.value
        XCTAssertEqual(actions.state, .exported(0))

        let target = try makeStore()
        let imported = try XCTUnwrap(actions.importRules(from: url, into: target))
        await imported.value
        XCTAssertEqual(target.configurationSnapshot, source.configurationSnapshot)
        XCTAssertEqual(actions.state, .imported(0, includesDefaults: true),
                       "A defaults-only edit must not be reported as unchanged")
        target.undo()
        XCTAssertEqual(target.configurationSnapshot, RuleConfiguration())
    }

    func testIdenticalV2ImportDoesNotAddAnUndoStep() async throws {
        let store = try makeStore()
        let previous = GlobalButtonRules(actions: [.close: [.left: .minimize]])
        let current = GlobalButtonRules(actions: [.close: [.left: .quitApp]])
        store.updateGlobalDefaults(previous)
        store.updateGlobalDefaults(current)
        let actions = RuleFileActions(read: { _ in .init(rules: [], globalDefaults: current) })
        let task = try XCTUnwrap(actions.importRules(from: inputURL, into: store))
        await task.value
        XCTAssertEqual(actions.state, .unchanged)
        store.undo()
        XCTAssertEqual(store.globalDefaults, previous)
    }

    func testFutureConfigurationRejectsImportAndIncompleteExportWithoutTouchingEitherFile() async throws {
        let raw = Data(#"{"version":999,"rules":[],"future":{"preserve":true}}"#.utf8)
        let defaults = try makeDefaults()
        defaults.set(raw, forKey: "fixture.rules")
        let store = RuleStore(defaults: defaults, storageKey: "fixture.rules")
        XCTAssertTrue(store.isReadOnly)
        let actions = RuleFileActions(read: { _ in
            XCTFail("A read-only store must reject import before reading the file")
            return .init(rules: [])
        }, write: { _, _ in XCTFail("An unknown configuration cannot be exported as a complete v2 backup") })
        let imported = actions.importRules(from: inputURL, into: store)
        XCTAssertNil(imported)
        await imported?.value
        XCTAssertTrue(actions.state.message.contains(try XCTUnwrap(store.writeIssue).localizedDescription))
        if case .failed = actions.state {} else { XCTFail("Read-only import must report a failure") }

        let output = try makeFileURL()
        let backup = Data("previous complete backup".utf8)
        try backup.write(to: output)
        let exported = actions.exportRules(from: store, to: output)
        XCTAssertNil(exported)
        await exported?.value
        if case .failed = actions.state {} else { XCTFail("Read-only export must report a failure") }
        XCTAssertFalse(actions.isBusy)
        XCTAssertEqual(try Data(contentsOf: output), backup)
        XCTAssertEqual(defaults.data(forKey: "fixture.rules"), raw)
    }

    func testExternalFutureVersionRejectsExportBeforeWritingAStaleSnapshot() async throws {
        let defaults = try makeDefaults()
        let store = RuleStore(defaults: defaults, storageKey: "fixture.rules")
        store.upsert(AppRule(bundleIdentifier: "fixture.existing", displayName: "Existing"))
        let previous = store.configurationSnapshot
        XCTAssertTrue(store.canUndo)
        let future = Data(#"{"version":999,"rules":[],"future":{"preserve":true}}"#.utf8)
        defaults.set(future, forKey: "fixture.rules")
        XCTAssertFalse(store.isReadOnly, "The store has not refreshed the external version yet")
        let output = try makeFileURL()
        let backup = Data("existing complete backup".utf8)
        try backup.write(to: output)
        let actions = RuleFileActions(write: { _, _ in
            XCTFail("The stale in-memory snapshot must never reach the writer")
        })

        let task = actions.exportRules(from: store, to: output)
        XCTAssertNil(task)
        await task?.value
        XCTAssertTrue(store.isReadOnly)
        XCTAssertFalse(store.canUndo)
        if case .failed = actions.state {} else { XCTFail("Export must report the unsupported version") }
        XCTAssertTrue(actions.state.message.contains(try XCTUnwrap(store.writeIssue).localizedDescription))
        XCTAssertFalse(actions.isBusy)
        XCTAssertEqual(store.configurationSnapshot, previous)
        XCTAssertEqual(defaults.data(forKey: "fixture.rules"), future)
        XCTAssertEqual(try Data(contentsOf: output), backup)
    }

    func testConfigurationBecomingReadOnlyDuringImportReportsFailureInsteadOfUnchanged() async throws {
        let defaults = try makeDefaults()
        let store = RuleStore(defaults: defaults, storageKey: "fixture.rules")
        let original = AppRule(bundleIdentifier: "fixture.original", displayName: "Original")
        store.upsert(original)
        let previous = store.configurationSnapshot
        let gate = DeferredFileResult<RuleTransfer.Document>()
        let actions = RuleFileActions(read: { _ in try await gate.read() })
        let task = try XCTUnwrap(actions.importRules(from: inputURL, into: store))
        await gate.waitUntilStarted()
        let future = Data(#"{"version":999,"rules":[],"future":{"preserve":true}}"#.utf8)
        defaults.set(future, forKey: "fixture.rules")
        await gate.resolve(.success(.init(rules: [], globalDefaults: GlobalButtonRules())))
        await task.value

        XCTAssertTrue(store.isReadOnly)
        if case .failed = actions.state {} else { XCTFail("An unreadable configuration must report failure") }
        XCTAssertTrue(actions.state.message.contains(try XCTUnwrap(store.writeIssue).localizedDescription))
        XCTAssertFalse(actions.isBusy)
        XCTAssertEqual(store.configurationSnapshot, previous)
        XCTAssertEqual(defaults.data(forKey: "fixture.rules"), future)
    }
}

private actor SimulatedExportDestination {
    private(set) var writes: [String] = []

    func write(_ value: String) {
        writes.append(value)
    }
}

/// A controllable reader/writer that deliberately ignores cancellation to test stale completions.
private actor DeferredFileResult<Value: Sendable> {
    private var result: CheckedContinuation<Value, Error>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func read() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            result = continuation
            startedWaiters.forEach { $0.resume() }
            startedWaiters = []
        }
    }

    func waitUntilStarted() async {
        if result != nil {
            return
        }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func resolve(_ value: Result<Value, Error>) {
        result?.resume(with: value)
        result = nil
    }
}
