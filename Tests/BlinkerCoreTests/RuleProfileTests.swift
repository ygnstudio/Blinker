@testable import BlinkerCore
import XCTest

/// Tests for named rule profiles: legacy migration, active-profile
/// isolation, deletion guard and persistence round-trips.
final class RuleProfileTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "RuleProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    private func legacyRuleJSON() throws -> Data {
        let json = """
        [{"bundleIdentifier":"com.apple.Safari","displayName":"Safari",
          "closeAction":"quitApp","minimizeAction":null,"zoomAction":"maximize",
          "isEnabled":true}]
        """
        return try XCTUnwrap(json.data(using: .utf8))
    }

    func testLegacyFlatRulesMigrateIntoDefaultProfile() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        try defaults.set(legacyRuleJSON(), forKey: "com.ygnstudio.blinker.rules")

        let store = RuleStore(
            defaults: defaults,
            defaultProfileName: "默认"
        )

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.name, "默认")
        XCTAssertEqual(store.snapshot.first?.bundleIdentifier, "com.apple.Safari")
    }

    func testProfilesIsolateRules() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RuleStore(defaults: defaults)
        store.upsert(AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .quitApp
        ))

        store.createProfile(named: "工作")
        XCTAssertTrue(store.snapshot.isEmpty, "new profile starts empty")

        store.upsert(AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .hideApp
        ))

        store.switchProfile(to: store.profiles[0].id)
        XCTAssertEqual(store.snapshot.first?.closeAction, .quitApp, "first profile untouched")

        store.switchProfile(to: store.profiles[1].id)
        XCTAssertEqual(store.snapshot.first?.closeAction, .hideApp)
    }

    func testDuplicateCopiesRulesAndActivates() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RuleStore(defaults: defaults)
        store.upsert(AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .quitApp
        ))

        store.duplicateProfile()

        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertEqual(store.activeProfileID, store.profiles[1].id)
        XCTAssertEqual(store.profiles[1].name, "默认 - 副本")
        XCTAssertEqual(store.snapshot.first?.closeAction, .quitApp)

        // Editing the copy must not leak into the source profile.
        store.upsert(AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .minimize
        ))
        store.switchProfile(to: store.profiles[0].id)
        XCTAssertEqual(store.snapshot.first?.closeAction, .quitApp)
    }

    func testLastProfileCannotBeDeleted() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RuleStore(defaults: defaults)
        let onlyID = try XCTUnwrap(store.activeProfileID)

        store.deleteProfile(id: onlyID)
        XCTAssertEqual(store.profiles.count, 1, "the last profile is protected")
        XCTAssertEqual(store.activeProfileID, onlyID)
    }

    func testDeleteSwitchesToNeighbor() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RuleStore(defaults: defaults)
        store.createProfile(named: "工作")
        let workID = try XCTUnwrap(store.activeProfileID)
        store.createProfile(named: "个人")
        let personalID = try XCTUnwrap(store.activeProfileID)
        XCTAssertEqual(store.profiles.count, 3)

        store.deleteProfile(id: personalID)
        XCTAssertEqual(store.activeProfileID, workID, "deletion falls back to the neighbor")
        XCTAssertEqual(store.profiles.count, 2)
    }

    func testProfilesRoundTripThroughDefaults() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RuleStore(defaults: defaults)
        store.upsert(AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .quitApp
        ))
        store.createProfile(named: "工作")
        let activeID = try XCTUnwrap(store.activeProfileID)

        let reloaded = RuleStore(defaults: defaults)
        XCTAssertEqual(reloaded.profiles.map(\.name), ["默认", "工作"])
        XCTAssertEqual(reloaded.activeProfileID, activeID)
        XCTAssertEqual(reloaded.snapshot.count, 0, "active profile persisted as 工作")
    }
}
