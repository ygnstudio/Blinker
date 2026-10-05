@testable import BlinkerApp
import XCTest

/// Quick actions section: one-time migration for saves that predate it, and
/// shortcut-slot normalization (trim, dedupe, cap at three, 64 characters).
@MainActor
final class MenuBarQuickActionsPreferencesTests: XCTestCase {
    private final class RecordingDefaults: UserDefaults, @unchecked Sendable {
        var writes = 0

        override func set(_ value: Any?, forKey defaultName: String) {
            writes += 1
            super.set(value, forKey: defaultName)
        }
    }

    private func withDefaults(_ body: (RecordingDefaults) throws -> Void) throws {
        let name = "Blinker.MenuBarQuickActionsPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// Saves from builds that predate the quick actions section list every
    /// older section; the new section is enabled exactly once, appended last.
    func testQuickActionsSectionEnabledOnceForOldSaves() throws {
        try withDefaults { defaults in
            let saved = Data(("{\"sectionOrder\":[\"battery\",\"network\",\"volume\",\"bluetooth\"],"
                + "\"enabledSections\":[\"battery\",\"network\",\"volume\",\"bluetooth\"]}").utf8)
            defaults.set(saved, forKey: MenuBarPreferences.key)
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertTrue(preferences.configuration.enabledSections.contains(.quickActions))
            XCTAssertEqual(preferences.configuration.sectionOrder,
                           [.battery, .network, .volume, .bluetooth, .quickActions])
        }
    }

    func testQuickActionsSectionChoiceIsNotReMigrated() throws {
        try withDefaults { defaults in
            let saved = Data(("{\"sectionOrder\":[\"battery\",\"network\",\"volume\",\"bluetooth\","
                + "\"quickActions\"],\"enabledSections\":[\"battery\",\"network\",\"volume\","
                + "\"bluetooth\"]}").utf8)
            defaults.set(saved, forKey: MenuBarPreferences.key)
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertFalse(preferences.configuration.enabledSections.contains(.quickActions))
        }
    }

    /// Slot names are trimmed, deduplicated, capped at three entries and 64
    /// characters; toggle choices survive a reload.
    func testQuickActionChoicesSurviveReload() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            let longName = String(repeating: "长", count: 80)
            preferences.update {
                $0.showsQuickActionMicMute = false
                $0.showsQuickActionDisplayCleaning = false
                $0.showsQuickActionKeyboardCleaning = false
                $0.shortcutSlots = ["  清洁模式  ", "", "清洁模式", "夜间", longName, "第四个" ]
            }
            let value = MenuBarPreferences(defaults: defaults).configuration
            XCTAssertFalse(value.showsQuickActionMicMute)
            XCTAssertFalse(value.showsQuickActionDisplayCleaning)
            XCTAssertFalse(value.showsQuickActionKeyboardCleaning)
            XCTAssertEqual(value.shortcutSlots, ["清洁模式", "夜间", String(repeating: "长", count: 64)])
        }
    }
}
