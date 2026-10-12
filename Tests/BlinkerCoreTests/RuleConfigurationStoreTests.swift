@testable import BlinkerCore
import Combine
import XCTest

@MainActor
final class RuleConfigurationStoreTests: XCTestCase {
    private func withStore(_ body: (RuleStore, UserDefaults) throws -> Void) throws {
        let name = "Blinker.InheritanceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(RuleStore(defaults: defaults, storageKey: "rules"), defaults)
    }

    func testLegacyArrayIsBackedUpAndItsNilNeverStartsInheriting() throws {
        try withStore { _, defaults in
            let legacy = [AppRule(bundleIdentifier: "legacy", displayName: "Legacy")]
            let data = try JSONEncoder().encode(legacy)
            defaults.set(data, forKey: "rules")
            let store = RuleStore(defaults: defaults, storageKey: "rules")
            XCTAssertEqual(defaults.data(forKey: "rules"), data)
            XCTAssertEqual(defaults.data(forKey: "rules.legacy-backup"), data)
            var global = GlobalButtonRules()
            global.setAction(.quitApp, button: .close)
            XCTAssertTrue(store.updateGlobalDefaults(global))
            let reloaded = RuleStore(defaults: defaults, storageKey: "rules")
            XCTAssertEqual(reloaded.globalDefaults, global)
            XCTAssertEqual(reloaded.rules.first?.binding(for: .close), .system)
            XCTAssertEqual(defaults.data(forKey: "rules.legacy-backup"), data)
            let envelope = try XCTUnwrap(defaults.data(forKey: "rules"))
            XCTAssertEqual(try RuleTransfer.decodeConfiguration(envelope).globalDefaults, global)
        }
    }

    func testWholeDocumentImportAndUndoRestoreRulesAndDefaultsTogether() throws {
        try withStore { store, defaults in
            store.upsert(AppRule(bundleIdentifier: "old", displayName: "Old", closeAction: .closeWindow))
            let before = store.configurationSnapshot
            var global = GlobalButtonRules()
            global.setAction(.hideApp, button: .close)
            let rule = AppRule.inheritingDefaults(bundleIdentifier: "new", displayName: "New")
            XCTAssertTrue(store.merge(RuleTransfer.Document(rules: [rule], globalDefaults: global)))
            let imported = store.configurationSnapshot
            XCTAssertEqual(imported.rules.count, 2)
            XCTAssertEqual(imported.globalDefaults, global)
            store.undo()
            XCTAssertEqual(store.configurationSnapshot, before)
            XCTAssertEqual(RuleStore(defaults: defaults, storageKey: "rules").configurationSnapshot, before)
            store.redo()
            XCTAssertEqual(store.configurationSnapshot, imported)
            XCTAssertEqual(RuleStore(defaults: defaults, storageKey: "rules").configurationSnapshot, imported)
        }
    }

    func testLegacyImportKeepsExistingDefaultsAndExplicitSystemSlots() throws {
        try withStore { store, _ in
            var global = GlobalButtonRules()
            global.setAction(.quitApp, button: .close)
            store.updateGlobalDefaults(global)
            let data = try RuleTransfer.encode([AppRule(bundleIdentifier: "legacy", displayName: "Legacy")])
            let document = try RuleTransfer.decodeConfiguration(data)
            XCTAssertNil(document.globalDefaults)
            XCTAssertTrue(store.merge(document))
            XCTAssertEqual(store.globalDefaults, global)
            XCTAssertEqual(store.rules.first?.binding(for: .close), .system)
        }
    }

    func testPublishingNeverExposesHalfUpdatedExecutionSnapshot() throws {
        try withStore { store, _ in
            var observed = false
            let subscription = store.$configuration.dropFirst().sink { value in
                observed = true
                XCTAssertEqual(store.configurationSnapshot, value)
            }
            var global = GlobalButtonRules()
            global.setAction(.hideApp, button: .close)
            let rule = AppRule.inheritingDefaults(bundleIdentifier: "app", displayName: "App")
            store.replaceConfiguration(RuleConfiguration(rules: [rule], globalDefaults: global))
            XCTAssertTrue(observed)
            withExtendedLifetime(subscription) {}
        }
    }

    func testDeletingAnExceptionResumesGlobalDefaultsWhileResetKeepsSystem() throws {
        try withStore { store, _ in
            var global = GlobalButtonRules()
            global.setAction(.quitApp, button: .close)
            store.updateGlobalDefaults(global)
            store.upsert(AppRule.inheritingDefaults(bundleIdentifier: "app", displayName: "App"))
            store.reset(bundleIdentifier: "app")
            let reset = store.configurationSnapshot
            XCTAssertNil(RuleEngine(configurationProvider: { reset })
                .action(forBundleIdentifier: "app", button: .close))
            store.remove(bundleIdentifier: "app")
            let removed = store.configurationSnapshot
            XCTAssertEqual(RuleEngine(configurationProvider: { removed })
                .action(forBundleIdentifier: "app", button: .close), .quitApp)
        }
    }

    func testButtonResetPreservesIndependentHoverOptOut() throws {
        try withStore { store, _ in
            var rule = AppRule.inheritingDefaults(bundleIdentifier: "app", displayName: "App")
            rule.isHoverEnabled = false
            rule.isEnabled = false
            store.upsert(rule)
            store.reset(bundleIdentifier: rule.id)
            let reset = try XCTUnwrap(store.rules.first)
            XCTAssertFalse(reset.isHoverEnabled)
            XCTAssertTrue(reset.isEnabled)
            for slot in RuleActionSlot.all {
                XCTAssertEqual(reset.binding(for: slot.button, variant: slot.variant), .system)
            }
            store.undo()
            XCTAssertEqual(store.rules.first, rule)
        }
    }

    func testRefreshingFutureVersionProtectsExportWithoutModifyingEitherSnapshot() throws {
        try withStore { store, defaults in
            store.upsert(AppRule(bundleIdentifier: "existing", displayName: "Existing"))
            store.upsert(AppRule(bundleIdentifier: "second", displayName: "Second"))
            store.undo()
            XCTAssertTrue(store.canUndo)
            XCTAssertTrue(store.canRedo)
            let before = store.configurationSnapshot
            let future = Data(#"{"version":999,"rules":[],"future":"preserve"}"#.utf8)
            defaults.set(future, forKey: "rules")
            store.refreshPersistenceStatus()
            XCTAssertTrue(store.isReadOnly)
            XCTAssertEqual(store.writeIssue, .unsupportedVersion(999))
            XCTAssertFalse(store.canUndo)
            XCTAssertFalse(store.canRedo)
            XCTAssertEqual(store.configurationSnapshot, before)
            XCTAssertEqual(defaults.data(forKey: "rules"), future)
        }
    }

    func testFuturePersistenceIsReadOnlyAndNeverFallsBackOrOverwrites() throws {
        try withStore { _, defaults in
            let data = Data(#"{"version":999,"rules":[],"future":"keep me"}"#.utf8)
            defaults.set(data, forKey: "rules")
            let profile = RuleProfile(id: UUID(), name: "Old", rules: [
                AppRule(bundleIdentifier: "old", displayName: "Old", closeAction: .quitApp),
            ])
            let archive = ProfileArchive(profiles: [profile], activeProfileID: profile.id)
            try defaults.set(JSONEncoder().encode(archive), forKey: "profiles")
            let store = RuleStore(defaults: defaults, storageKey: "rules", profileArchiveKey: "profiles")
            XCTAssertTrue(store.isReadOnly)
            XCTAssertEqual(store.writeIssue, .unsupportedVersion(999))
            XCTAssertTrue(store.rules.isEmpty)
            store.upsert(AppRule(bundleIdentifier: "new", displayName: "New"))
            XCTAssertFalse(store.replaceConfiguration(RuleConfiguration()))
            XCTAssertFalse(store.merge(RuleTransfer.Document(rules: [])))
            store.undo()
            store.redo()
            XCTAssertEqual(defaults.data(forKey: "rules"), data)
            XCTAssertNil(defaults.data(forKey: "rules.corrupt-backup"))
            XCTAssertFalse(store.canUndo)
        }
    }

    func testFutureVersionWrittenDuringTheSessionAlsoPreventsMutation() throws {
        try withStore { store, defaults in
            store.upsert(AppRule(bundleIdentifier: "existing", displayName: "Existing"))
            let before = store.configurationSnapshot
            let future = Data(#"{"version":3,"rules":[]}"#.utf8)
            defaults.set(future, forKey: "rules")
            store.remove(bundleIdentifier: "existing")
            store.undo()
            XCTAssertTrue(store.isReadOnly)
            XCTAssertEqual(store.configurationSnapshot, before)
            XCTAssertEqual(defaults.data(forKey: "rules"), future)
        }
    }

    func testInvalidImportDoesNotPartiallyApplyDefaultsOrHistory() throws {
        try withStore { store, defaults in
            let rule = AppRule(bundleIdentifier: "app", displayName: "App")
            store.upsert(rule)
            let before = store.configurationSnapshot
            let persisted = defaults.data(forKey: "rules")
            var global = GlobalButtonRules()
            global.setAction(.quitApp, button: .close)
            XCTAssertFalse(store.merge(RuleTransfer.Document(rules: [rule, rule], globalDefaults: global)))
            XCTAssertEqual(store.writeIssue, .invalidConfiguration)
            XCTAssertEqual(store.configurationSnapshot, before)
            XCTAssertEqual(defaults.data(forKey: "rules"), persisted)
            store.undo()
            XCTAssertTrue(store.rules.isEmpty)
            XCTAssertFalse(store.globalDefaults.hasConfiguredActions)
        }
    }

    func testV2BackupRoundTripsDefaultsAndInheritanceWithoutLegacyDataLoss() throws {
        var global = GlobalButtonRules()
        global.setAction(ButtonAction.none, button: .zoom, variant: .right)
        var rule = AppRule.inheritingDefaults(bundleIdentifier: "app", displayName: "App")
        rule.setBinding(.system, button: .close)
        let configuration = RuleConfiguration(rules: [rule], globalDefaults: global)
        let data = try RuleTransfer.encode(configuration)
        let document = try RuleTransfer.decodeConfiguration(data)
        XCTAssertEqual(document.rules, configuration.rules)
        XCTAssertEqual(document.globalDefaults, global)
        XCTAssertThrowsError(try RuleTransfer.decode(data), "Old array-only callers cannot drop v2 defaults")
        XCTAssertThrowsError(try RuleTransfer.encode([rule]), "An inheriting rule needs a complete v2 backup")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        XCTAssertEqual(try RuleTransfer.readConfiguration(from: url), document)
    }

    func testDefaultOnlyBackupIsValidAndMissingOrFutureDefaultsAreRejected() throws {
        var global = GlobalButtonRules()
        global.setAction(.hideApp, button: .close)
        let data = try RuleTransfer.encode(RuleConfiguration(globalDefaults: global))
        let document = try RuleTransfer.decodeConfiguration(data)
        XCTAssertTrue(document.rules.isEmpty)
        XCTAssertEqual(document.globalDefaults, global)
        XCTAssertThrowsError(try RuleTransfer.decodeConfiguration(Data(#"{"version":2,"rules":[]}"#.utf8)))
        XCTAssertThrowsError(try RuleTransfer.decodeConfiguration(Data(#"{"version":99,"rules":[]}"#.utf8)))
        XCTAssertThrowsError(try RuleTransfer.decodeConfiguration(Data(repeating: 0, count: 1_048_577)))
    }
}
