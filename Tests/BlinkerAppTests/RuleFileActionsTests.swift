@testable import BlinkerApp
import BlinkerCore
import Foundation
import XCTest

@MainActor
final class RuleFileActionsTests: XCTestCase {
    private let inputURL = URL(fileURLWithPath: "/rule-transfer-fixture.json")

    private func makeStore() throws -> RuleStore {
        let suite = "Blinker.RuleFileActionsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return RuleStore(defaults: defaults)
    }

    func testImportReportsProgressRejectsDuplicateAndMergesAsOneUndoableChange() async throws {
        let gate = DeferredFileResult<[AppRule]>()
        let actions = RuleFileActions(read: { _ in try await gate.read() })
        let store = try makeStore()
        let original = AppRule(bundleIdentifier: "fixture.original", displayName: "Original")
        store.upsert(original)
        let task = try XCTUnwrap(actions.importRules(from: inputURL, into: store))
        await gate.waitUntilStarted()
        XCTAssertEqual(actions.state, .importing)
        XCTAssertTrue(actions.isBusy)
        XCTAssertNil(actions.importRules(from: inputURL, into: store))
        XCTAssertNil(actions.exportRules(store.snapshot, to: inputURL))
        let imported = [
            AppRule(bundleIdentifier: "fixture.one", displayName: "One"),
            AppRule(bundleIdentifier: "fixture.two", displayName: "Two"),
        ]
        await gate.resolve(.success(imported))
        await task.value
        XCTAssertEqual(actions.state, .imported(2))
        XCTAssertFalse(actions.isBusy)
        XCTAssertEqual(store.snapshot, [original] + imported)
        store.undo()
        XCTAssertEqual(store.snapshot, [original])
    }

    func testCancelledOldReadCannotMergeOrReplaceTheNewOperationsStatus() async throws {
        let oldGate = DeferredFileResult<[AppRule]>()
        let newGate = DeferredFileResult<[AppRule]>()
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
        await oldGate.resolve(.success([AppRule(bundleIdentifier: "fixture.old", displayName: "Old")]))
        await oldTask.value
        XCTAssertTrue(store.snapshot.isEmpty)
        XCTAssertEqual(actions.state, .importing)
        let current = AppRule(bundleIdentifier: "fixture.current", displayName: "Current")
        await newGate.resolve(.success([current]))
        await newTask.value
        XCTAssertEqual(store.snapshot, [current])
        XCTAssertEqual(actions.state, .imported(1))
    }

    func testReleasingTheControllerPreventsADeferredImport() async throws {
        let gate = DeferredFileResult<[AppRule]>()
        var actions: RuleFileActions? = RuleFileActions(read: { _ in try await gate.read() })
        let controllerExists = { [weak actions] in actions != nil }
        let store = try makeStore()
        let task = try XCTUnwrap(actions?.importRules(from: inputURL, into: store))
        await gate.waitUntilStarted()
        actions = nil
        XCTAssertFalse(controllerExists())
        await gate.resolve(.success([AppRule(bundleIdentifier: "fixture.old", displayName: "Old")]))
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
            let actions = RuleFileActions(read: { _ in imported })
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
        let actions = RuleFileActions(write: { rules, _ in
            let name = rules[0].displayName
            if name == "Old" {
                try await gate.read()
            }
            await output.write(name)
        })
        let old = [AppRule(bundleIdentifier: "fixture.export", displayName: "Old")]
        let new = [AppRule(bundleIdentifier: "fixture.export", displayName: "New")]
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
        let rules = [AppRule(bundleIdentifier: "fixture.export", displayName: "Export")]
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
        let task = try XCTUnwrap(actions.exportRules([invalid], to: url))
        await task.value
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(actions.state, .failed(RuleTransfer.ExportError.invalidRules.localizedDescription))
        XCTAssertFalse(actions.isBusy)
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
