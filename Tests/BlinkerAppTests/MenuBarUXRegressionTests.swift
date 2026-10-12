import AppKit
@testable import BlinkerApp
import XCTest

@MainActor
final class MenuBarUXRegressionTests: XCTestCase {
    func testOldPanelWideScrollPreferenceMigratesWithoutLosingOtherSettings() throws {
        let name = "Blinker.MenuBarUXRegressionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var saved = MenuBarConfiguration()
        saved.scrollScope = .panel
        saved.shortcutSlots = ["Focus"]
        saved.quickActionAudioDeviceAddress = "11-22-33-44-55-66"
        try defaults.set(JSONEncoder().encode(saved), forKey: MenuBarPreferences.key)
        let preferences = MenuBarPreferences(defaults: defaults)
        XCTAssertEqual(preferences.configuration.scrollScope, .volumeControl)
        XCTAssertEqual(preferences.configuration.shortcutSlots, ["Focus"])
        XCTAssertEqual(preferences.configuration.quickActionAudioDeviceAddress,
                       saved.quickActionAudioDeviceAddress)
    }

    func testBatteryResetPreservesShortcutsDevicesAndOtherPageValues() {
        var saved = MenuBarConfiguration()
        saved.showsBatteryDetails.toggle()
        saved.shortcutSlots = ["Focus", "Notes"]
        saved.quickActionAudioDeviceAddress = "headphones"
        saved.outputDeviceLimit = 9
        saved.showsUptime.toggle()
        var expected = saved
        expected.showsBatteryDetails = MenuBarConfiguration().showsBatteryDetails
        XCTAssertEqual(saved.resetting(.battery), expected)
    }

    func testQuickActionsResetPreservesPanelAndAudioPreferences() {
        var saved = MenuBarConfiguration()
        saved.shortcutSlots = ["Focus"]
        saved.quickActionAudioDeviceAddress = "headphones"
        saved.quickActionAudioDeviceName = "Headphones"
        saved.enabledSections = [.volume]
        saved.outputDeviceLimit = 9
        var expected = saved
        expected.shortcutSlots = []
        expected.quickActionAudioDeviceAddress = ""
        expected.quickActionAudioDeviceName = ""
        XCTAssertEqual(saved.resetting(.quickActions), expected)
    }

    func testAudioResetIncludesMovedControlsWithoutResettingPanelLayout() {
        var saved = MenuBarConfiguration()
        saved.outputDeviceLimit = 9
        saved.outputDeviceOrder = ["headphones"]
        saved.scrollAdjustsVolume.toggle()
        saved.enabledSections = [.volume]
        var expected = MenuBarConfiguration()
        expected.enabledSections = saved.enabledSections
        XCTAssertEqual(saved.resetting(.audio), expected)
    }

    func testOnlyVisibleVolumeControlAcceptsScrollAndDeviceListsKeepScrolling() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
        window.contentView = root
        let volume = NSView(frame: NSRect(x: 20, y: 100, width: 320, height: 40))
        volume.identifier = NSUserInterfaceItemIdentifier("BlinkerVolumeControl")
        root.addSubview(volume)
        XCTAssertTrue(MenuBarVolumeScroll.acceptsScroll(at: NSPoint(x: 40, y: 120), in: window))
        XCTAssertFalse(MenuBarVolumeScroll.acceptsScroll(at: NSPoint(x: 40, y: 200), in: window),
                       "A non-clipping marker must not capture the area outside its own bounds")
        let devices = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        devices.identifier = NSUserInterfaceItemIdentifier("BlinkerAudioDeviceList")
        volume.addSubview(devices)
        XCTAssertFalse(MenuBarVolumeScroll.acceptsScroll(at: NSPoint(x: 40, y: 120), in: window))
        devices.removeFromSuperview()
        volume.isHidden = true
        XCTAssertFalse(MenuBarVolumeScroll.acceptsScroll(at: NSPoint(x: 40, y: 120), in: window))
        volume.removeFromSuperview()
        XCTAssertFalse(MenuBarVolumeScroll.acceptsScroll(at: NSPoint(x: 40, y: 120), in: window),
                       "The Quick Actions page has no volume control")
    }

    func testSplitPagesResetOnlyTheirOwnFields() {
        var saved = MenuBarConfiguration()
        saved.showsPublicIPAddress = true
        saved.outputDeviceOrder = ["headphones"]
        saved.replacesNetworkWithBluetooth.toggle()
        let network = saved.resetting(.network)
        XCTAssertFalse(network.showsPublicIPAddress)
        XCTAssertEqual(network.outputDeviceOrder, saved.outputDeviceOrder)
        XCTAssertEqual(network.replacesNetworkWithBluetooth, saved.replacesNetworkWithBluetooth)
        let audio = saved.resetting(.audio)
        XCTAssertTrue(audio.showsPublicIPAddress)
        XCTAssertTrue(audio.outputDeviceOrder.isEmpty)
        XCTAssertEqual(audio.replacesNetworkWithBluetooth, saved.replacesNetworkWithBluetooth)
        let icon = saved.resetting(.icon)
        XCTAssertTrue(icon.showsPublicIPAddress)
        XCTAssertEqual(icon.outputDeviceOrder, saved.outputDeviceOrder)
        XCTAssertEqual(icon.replacesNetworkWithBluetooth, MenuBarConfiguration().replacesNetworkWithBluetooth)
    }

    func testOldConfigurationKeepsFieldsWhenDesktopActionKeyIsMissing() throws {
        var saved = MenuBarConfiguration()
        saved.showsQuickActionDesktopIcons = false
        saved.shortcutSlots = ["Focus"]
        saved.outputDeviceOrder = ["headphones"]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))
            as? [String: Any])
        object.removeValue(forKey: "showsQuickActionShowDesktop")
        let decoded = try JSONDecoder().decode(MenuBarConfiguration.self,
                                               from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, saved)
        saved.showsQuickActionShowDesktop = false
        XCTAssertEqual(try JSONDecoder().decode(MenuBarConfiguration.self,
                                                from: JSONEncoder().encode(saved)), saved)
    }
}
