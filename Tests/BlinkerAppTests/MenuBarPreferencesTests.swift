@testable import BlinkerApp
import XCTest

@MainActor
final class MenuBarPreferencesTests: XCTestCase {
    private final class RecordingDefaults: UserDefaults, @unchecked Sendable {
        var writes = 0

        override func set(_ value: Any?, forKey defaultName: String) {
            writes += 1
            super.set(value, forKey: defaultName)
        }
    }

    private func withDefaults(_ body: (RecordingDefaults) throws -> Void) throws {
        let name = "Blinker.MenuBarPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testInitialDefaultsDoNotWriteAndUsePanelLeftClick() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertEqual(preferences.configuration, MenuBarConfiguration())
            XCTAssertEqual(preferences.configuration.leftClick, .panel)
            XCTAssertEqual(preferences.configuration.visibleSections,
                           [.battery, .network, .volume, .bluetooth])
            XCTAssertEqual(defaults.writes, 0)
        }
    }

    func testPartialSavedConfigurationPreservesValuesAndDefaultsNewFields() throws {
        try withDefaults { defaults in
            defaults.set(Data(#"{"iconSize":31,"stroke":"bold"}"#.utf8), forKey: MenuBarPreferences.key)
            let writes = defaults.writes
            let preferences = MenuBarPreferences(defaults: defaults)
            var expected = MenuBarConfiguration()
            expected.iconSize = 31
            expected.stroke = .bold
            XCTAssertEqual(preferences.configuration, expected)
            XCTAssertEqual(defaults.writes, writes)
        }
    }

    func testMalformedSavedDataFallsBackWithoutReplacingOriginal() throws {
        try withDefaults { defaults in
            let malformed = Data("not valid JSON".utf8)
            defaults.set(malformed, forKey: MenuBarPreferences.key)
            let writes = defaults.writes
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertEqual(preferences.configuration, MenuBarConfiguration())
            XCTAssertEqual(defaults.data(forKey: MenuBarPreferences.key), malformed)
            XCTAssertEqual(defaults.writes, writes)
        }
    }

    /// A save from before the bluetooth section existed has no trace of it in
    /// sectionOrder; those users get the section enabled exactly once.
    func testPreBluetoothSaveMigratesSectionOn() throws {
        try withDefaults { defaults in
            let legacy = Data(("{\"sectionOrder\":[\"battery\",\"network\",\"volume\"],"
                + "\"enabledSections\":[\"battery\",\"network\",\"volume\"]}").utf8)
            defaults.set(legacy, forKey: MenuBarPreferences.key)
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertEqual(preferences.configuration.sectionOrder,
                           [.battery, .network, .volume, .bluetooth])
            XCTAssertTrue(preferences.configuration.enabledSections.contains(.bluetooth))
            XCTAssertEqual(preferences.configuration.visibleSections,
                           [.battery, .network, .volume, .bluetooth])
        }
    }

    /// Once a save lists the bluetooth section, its enabled state is the
    /// user's own choice and is never re-migrated.
    func testBluetoothSectionChoiceIsNotReMigrated() throws {
        try withDefaults { defaults in
            let saved = Data(("{\"sectionOrder\":[\"battery\",\"network\",\"volume\",\"bluetooth\"],"
                + "\"enabledSections\":[\"battery\",\"network\",\"volume\"]}").utf8)
            defaults.set(saved, forKey: MenuBarPreferences.key)
            let preferences = MenuBarPreferences(defaults: defaults)
            XCTAssertFalse(preferences.configuration.enabledSections.contains(.bluetooth))
            XCTAssertEqual(preferences.configuration.visibleSections, [.battery, .network, .volume])
        }
    }

    func testBluetoothDeviceManagementChoicesSurviveReload() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.bluetoothDeviceLimit = 3
                $0.alwaysShowsAllBluetoothDevices = true
                $0.bluetoothDeviceOrder = ["AA:BB", "CC:DD"]
                $0.hiddenBluetoothDevices = ["EE:FF"]
                $0.hidesUnpairedBluetoothDevices = false
                $0.scansNearbyBluetoothDevices = true
            }
            let reloaded = MenuBarPreferences(defaults: defaults)
            let value = reloaded.configuration
            XCTAssertEqual(value.bluetoothDeviceLimit, 3)
            XCTAssertTrue(value.alwaysShowsAllBluetoothDevices)
            XCTAssertEqual(value.bluetoothDeviceOrder, ["AA:BB", "CC:DD"])
            XCTAssertEqual(value.hiddenBluetoothDevices, ["EE:FF"])
            XCTAssertFalse(value.hidesUnpairedBluetoothDevices)
            XCTAssertTrue(value.scansNearbyBluetoothDevices)
        }
    }

    func testAppearanceAndInteractionChoicesSurviveReload() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.placement = .both
                $0.dockBackground = .transparent
                $0.iconSize = 32
                $0.stroke = .bold
                $0.showsBatteryPercentage = false
                $0.showsChargingIndicator = false
                $0.showsPercentageWhenConnected = true
                $0.usesBatteryColors = false
                $0.batteryCriticalThreshold = 30
                $0.batterySymbolScale = 1.1
                $0.showsChargingEffect = false
                $0.showsChargingHeartbeat = false
                $0.wifiSymbolScale = 1.4
                $0.showsWiFiForWired = true
                $0.showsWiFiForHotspot = true
                $0.showsWiFiForTemporary = true
                $0.showsWiFiForSharing = true
                $0.showsBatteryInCenter = true
                $0.volumeStyle = .arc
                $0.replacesNetworkWithBluetooth = true
                $0.usesBluetoothVolumeColor = true
                $0.prioritizesNetworkErrors = false
                $0.bluetoothSymbolScale = 1.2
                $0.refreshInterval = 45
                $0.leftClick = .rules
                $0.sectionOrder = [.volume, .network, .battery]
                $0.enabledSections = [.volume]
                $0.scrollAdjustsVolume = false
                $0.scrollScope = .volumeControl
                $0.scrollDirection = .down
                $0.naturalScrolling = true
                $0.outputDeviceLimit = 8
                $0.alwaysShowsAllOutputDevices = true
                $0.outputDeviceOrder = ["headphones", "speakers"]
                $0.showsVPNStatus = false
                $0.showsWiFiName = true
                $0.showsAudioInput = false
            }
            let expected = preferences.configuration
            let reloaded = MenuBarPreferences(defaults: defaults)
            XCTAssertEqual(reloaded.configuration, expected)
            XCTAssertEqual(reloaded.configuration.visibleSections, [.volume])
        }
    }

    func testInvalidNumericValuesAreNormalizedBeforePersistence() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.iconSize = .infinity
                $0.batteryCriticalThreshold = .nan
                $0.batterySymbolScale = -.infinity
                $0.wifiSymbolScale = .nan
                $0.bluetoothSymbolScale = .infinity
                $0.refreshInterval = -.infinity
                $0.outputDeviceLimit = Int.max
            }
            let value = preferences.configuration
            XCTAssertEqual(value.iconSize, 20)
            XCTAssertEqual(value.batteryCriticalThreshold, 20)
            XCTAssertEqual(value.batterySymbolScale, 1)
            XCTAssertEqual(value.wifiSymbolScale, 1.6)
            XCTAssertEqual(value.bluetoothSymbolScale, 1.6)
            XCTAssertEqual(value.refreshInterval, 15)
            XCTAssertEqual(value.outputDeviceLimit, 20)
            let saved = try XCTUnwrap(defaults.data(forKey: MenuBarPreferences.key))
            XCTAssertEqual(try JSONDecoder().decode(MenuBarConfiguration.self, from: saved), value)
        }
    }

    func testNumericBoundsMatchControls() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.iconSize = 1
                $0.batteryCriticalThreshold = -1
                $0.batterySymbolScale = 0
                $0.wifiSymbolScale = 0
                $0.bluetoothSymbolScale = 9
                $0.refreshInterval = 100
                $0.outputDeviceLimit = 0
            }
            let value = preferences.configuration
            XCTAssertEqual(value.iconSize, 16)
            XCTAssertEqual(value.batteryCriticalThreshold, 0)
            XCTAssertEqual(value.batterySymbolScale, 0.5)
            XCTAssertEqual(value.wifiSymbolScale, 1)
            XCTAssertEqual(value.bluetoothSymbolScale, 1.8)
            XCTAssertEqual(value.refreshInterval, 60)
            XCTAssertEqual(value.outputDeviceLimit, 1)
        }
    }

    func testSectionOrderingRemainsCompleteAndAllSectionsCanBeHidden() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.sectionOrder = [.volume, .volume, .battery]
                $0.enabledSections = []
            }
            XCTAssertEqual(preferences.configuration.sectionOrder,
                           [.volume, .battery, .network, .bluetooth])
            XCTAssertEqual(preferences.configuration.visibleSections, [])
            preferences.update { $0.enabledSections.insert(.battery) }
            XCTAssertEqual(preferences.configuration.visibleSections, [.battery])
            XCTAssertEqual(MenuBarPreferences(defaults: defaults).configuration, preferences.configuration)
        }
    }

    func testDeviceOrderIsUniqueNonemptyAndBounded() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.outputDeviceOrder = ["", "headphones", "headphones", "speakers"]
                    + (0 ..< 150).map { "device-\($0)" }
            }
            let order = preferences.configuration.outputDeviceOrder
            XCTAssertEqual(Array(order.prefix(2)), ["headphones", "speakers"])
            XCTAssertEqual(order.count, 100)
            XCTAssertEqual(Set(order).count, order.count)
            XCTAssertFalse(order.contains(""))
        }
    }

    func testEquivalentNormalizedUpdateDoesNotWriteAgain() throws {
        try withDefaults { defaults in
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update { $0.iconSize = 100 }
            XCTAssertEqual(preferences.configuration.iconSize, 36)
            let writes = defaults.writes
            preferences.update { $0.iconSize = 1000 }
            XCTAssertEqual(defaults.writes, writes)
        }
    }

    func testResetPreservesUnrelatedPreferences() throws {
        try withDefaults { defaults in
            defaults.set("keep", forKey: "unrelated")
            let preferences = MenuBarPreferences(defaults: defaults)
            preferences.update {
                $0.placement = .dock
                $0.enabledSections = []
                $0.outputDeviceOrder = ["headphones"]
            }
            preferences.reset()
            XCTAssertEqual(preferences.configuration, MenuBarConfiguration())
            XCTAssertEqual(MenuBarPreferences(defaults: defaults).configuration, MenuBarConfiguration())
            XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
            let writes = defaults.writes
            preferences.reset()
            XCTAssertEqual(defaults.writes, writes)
        }
    }
}
