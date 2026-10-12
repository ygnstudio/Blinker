@testable import BlinkerApp
import XCTest

@MainActor
final class WorkbenchNavigationTests: XCTestCase {
    func testEveryExistingLeafHasTheAgreedSection() {
        let expected: [(SettingsDestination, WorkbenchSection)] = [
            (.general, .settings), (.permissions, .settings), (.effects, .system),
            (.hover, .windows), (.browser, .windows), (.windows, .windows),
            (.shortcuts, .windows), (.workspaces, .scenes),
        ]
        for (destination, section) in expected {
            XCTAssertEqual(WorkbenchNavigation.section(for: destination), section)
        }
        for page in MenuBarSettingsPage.allCases {
            let expected: WorkbenchSection = [.panel, .quickActions].contains(page) ? .system : .devices
            XCTAssertEqual(WorkbenchNavigation.section(for: .menuBar, menuBarPage: page), expected)
        }
    }

    func testSwitchingSectionsRestoresTheirOwnLeafWithoutChangingRules() {
        let navigation = WorkbenchNavigation()
        let settings = SettingsNavigation()
        let rules = RulesNavigation()
        rules.selection = "com.apple.Safari"
        rules.searchText = "Safari"
        settings.selection = .menuBar
        settings.menuBarPage = .audio
        navigation.showSettings(using: settings)
        navigation.show(.windows, settings: settings)
        XCTAssertEqual(settings.selection, .hover)
        settings.selection = .shortcuts
        navigation.showSettings(using: settings)
        navigation.show(.devices, settings: settings)
        XCTAssertEqual(settings.selection, .menuBar)
        XCTAssertEqual(settings.menuBarPage, .audio)
        navigation.show(.windows, settings: settings)
        XCTAssertEqual(settings.selection, .shortcuts)
        XCTAssertEqual(rules.selection, "com.apple.Safari")
        XCTAssertEqual(rules.searchText, "Safari")
    }

    func testDiagnosticDeepLinkRoutesToSettingsAndRetainsRequestedApplication() {
        let navigation = WorkbenchNavigation()
        let settings = SettingsNavigation()
        settings.openDiagnostics("com.apple.Notes")
        navigation.showSettings(using: settings)
        XCTAssertEqual(navigation.section, .settings)
        XCTAssertEqual(settings.diagnosticBundleID, "com.apple.Notes")
        navigation.showApplications()
        XCTAssertEqual(navigation.section, .apps)
        XCTAssertEqual(settings.diagnosticBundleID, "com.apple.Notes")
    }

    func testCatalogSectionsDoNotReplaceStoredSettingsDestination() {
        let navigation = WorkbenchNavigation()
        let settings = SettingsNavigation()
        settings.selection = .menuBar
        settings.menuBarPage = .network
        navigation.showSettings(using: settings)
        for section in [WorkbenchSection.library, .tools, .apps] {
            navigation.show(section, settings: settings)
            XCTAssertEqual(navigation.section, section)
            XCTAssertEqual(settings.selection, .menuBar)
            XCTAssertEqual(settings.menuBarPage, .network)
        }
        navigation.show(.devices, settings: settings)
        XCTAssertEqual(settings.menuBarPage, .network)
    }

    func testSectionDefaultsLandOnExistingUsablePages() {
        let cases: [WorkbenchSection: SettingsSidebarSelection] = [
            .windows: .destination(.hover), .devices: .menuBar(.icon),
            .system: .menuBar(.quickActions), .scenes: .destination(.workspaces),
            .settings: .destination(.general),
        ]
        for (section, destination) in cases {
            let navigation = WorkbenchNavigation()
            let settings = SettingsNavigation()
            navigation.show(section, settings: settings)
            XCTAssertEqual(navigation.section, section)
            XCTAssertEqual(settings.sidebarSelection, destination)
        }
    }
}
