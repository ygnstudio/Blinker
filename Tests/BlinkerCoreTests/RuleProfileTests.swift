@testable import BlinkerCore
import XCTest

/// Tests for `RuleStore` persistence, including migration from the removed
/// profile-era archive format.
final class RuleProfileTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "RuleProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    func testLegacyFlatRulesRoundTrip() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RuleStore(defaults: defaults)
        store.upsert(AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .quitApp
        ))

        let reloaded = RuleStore(defaults: defaults)
        XCTAssertEqual(reloaded.snapshot.count, 1)
        XCTAssertEqual(reloaded.snapshot.first?.closeAction, .quitApp)
    }

    func testProfileArchiveMigratesIntoFlatRules() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Simulate the profile-era storage: one profile holding the rules.
        let profile = RuleProfile(
            id: UUID(),
            name: "默认",
            rules: [
                AppRule(
                    bundleIdentifier: "com.apple.Safari",
                    displayName: "Safari",
                    closeAction: .quitApp,
                    zoomAction: .maximize
                ),
                AppRule(
                    bundleIdentifier: "app.cyan.markedit",
                    displayName: "MarkEdit",
                    closeAction: .closeWindow
                ),
            ]
        )
        let archive = ProfileArchive(profiles: [profile], activeProfileID: profile.id)
        try defaults.set(JSONEncoder().encode(archive), forKey: "com.ygnstudio.blinker.ruleProfiles")

        let store = RuleStore(defaults: defaults)
        XCTAssertEqual(store.snapshot.count, 2, "active profile's rules survive migration")
        XCTAssertEqual(store.snapshot.first?.bundleIdentifier, "com.apple.Safari")

        // The first mutation rewrites the flat key, ending the migration.
        store.setEnabled(false, bundleIdentifier: "com.apple.Safari")
        let reloaded = RuleStore(defaults: defaults)
        XCTAssertEqual(reloaded.snapshot.first?.isEnabled, false)
    }
}
