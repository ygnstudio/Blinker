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

    /// Saves from builds that predate quick actions carry none of its keys;
    /// the page is enabled exactly once for those users. It never joins the
    /// reorderable status blocks.
    func testQuickActionsSectionEnabledOnceForOldSaves() throws {
        try withDefaults { defaults in
            let saved = Data(("{\"sectionOrder\":[\"battery\",\"network\",\"volume\",\"bluetooth\"],"
                + "\"enabledSections\":[\"battery\",\"network\",\"volume\",\"bluetooth\"]}").utf8)
            defaults.set(saved, forKey: MenuBarPreferences.key)
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertTrue(preferences.configuration.enabledSections.contains(.quickActions))
            XCTAssertEqual(preferences.configuration.sectionOrder,
                           [.battery, .network, .volume, .bluetooth, .storage, .performance])
        }
    }

    /// A save written after quick actions shipped always carries its keys,
    /// even when the user hid the page; that choice is never re-migrated.
    /// The page's leftover seat in sectionOrder is stripped on decode.
    func testQuickActionsSectionChoiceIsNotReMigrated() throws {
        try withDefaults { defaults in
            let saved = Data(("{\"sectionOrder\":[\"battery\",\"network\",\"volume\",\"bluetooth\","
                + "\"quickActions\"],\"enabledSections\":[\"battery\",\"network\",\"volume\","
                + "\"bluetooth\"],\"showsQuickActionMicMute\":true,"
                + "\"showsQuickActionDisplayCleaning\":true,"
                + "\"showsQuickActionKeyboardCleaning\":true,\"shortcutSlots\":[]}").utf8)
            defaults.set(saved, forKey: MenuBarPreferences.key)
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertFalse(preferences.configuration.enabledSections.contains(.quickActions))
            XCTAssertEqual(preferences.configuration.sectionOrder,
                           [.battery, .network, .volume, .bluetooth, .storage, .performance])
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
                $0.showsQuickActionEmptyTrash = false
                $0.shortcutSlots = ["  清洁模式  ", "", "清洁模式", "夜间", longName, "第四个" ]
            }
            let value = MenuBarPreferences(defaults: defaults).configuration
            XCTAssertFalse(value.showsQuickActionMicMute)
            XCTAssertFalse(value.showsQuickActionDisplayCleaning)
            XCTAssertFalse(value.showsQuickActionKeyboardCleaning)
            XCTAssertFalse(value.showsQuickActionEmptyTrash)
            XCTAssertEqual(value.shortcutSlots, ["清洁模式", "夜间", String(repeating: "长", count: 64)])
        }
    }

    /// Saves that predate the system switches carry none of their keys;
    /// every row adopts its default and the Bluetooth target stays unset.
    func testSystemSwitchDefaultsApplyToOldSaves() throws {
        try withDefaults { defaults in
            let saved = Data(("{\"showsQuickActionMicMute\":true,"
                + "\"showsQuickActionDisplayCleaning\":true,"
                + "\"showsQuickActionKeyboardCleaning\":true,\"shortcutSlots\":[]}").utf8)
            defaults.set(saved, forKey: MenuBarPreferences.key)
            let value = MenuBarPreferences(defaults: defaults).configuration
            XCTAssertTrue(value.showsQuickActionKeepAwake)
            XCTAssertTrue(value.showsQuickActionDesktopIcons)
            XCTAssertTrue(value.showsQuickActionHiddenFiles)
            XCTAssertTrue(value.showsQuickActionScreenSaver)
            XCTAssertTrue(value.showsQuickActionDisplaySleep)
            XCTAssertTrue(value.showsQuickActionLockScreen)
            XCTAssertTrue(value.showsQuickActionBluetoothConnect)
            XCTAssertEqual(value.quickActionAudioDeviceAddress, "")
            XCTAssertEqual(value.quickActionAudioDeviceName, "")
        }
    }

    /// The Bluetooth target normalizes like slot names, and a cleared
    /// address clears the cached name with it.
    func testBluetoothTargetNormalization() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.showsQuickActionKeepAwake = false
                $0.quickActionAudioDeviceAddress = "  AA:BB:CC:DD:EE:01  "
                $0.quickActionAudioDeviceName = "  耳机  "
            }
            var value = MenuBarPreferences(defaults: defaults).configuration
            XCTAssertFalse(value.showsQuickActionKeepAwake)
            XCTAssertEqual(value.quickActionAudioDeviceAddress, "AA:BB:CC:DD:EE:01")
            XCTAssertEqual(value.quickActionAudioDeviceName, "耳机")
            preferences.update {
                $0.quickActionAudioDeviceAddress = "   "
                $0.quickActionAudioDeviceName = "残留"
            }
            value = MenuBarPreferences(defaults: defaults).configuration
            XCTAssertEqual(value.quickActionAudioDeviceAddress, "")
            XCTAssertEqual(value.quickActionAudioDeviceName, "")
        }
    }
}
