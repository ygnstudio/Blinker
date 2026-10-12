@testable import BlinkerApp
import XCTest

final class SettingsNavigationTests: XCTestCase {
    func testOpeningRulesDoesNotChangePreferencesDestination() {
        let settings = SettingsNavigation()
        let rules = RulesNavigation()
        settings.sidebarSelection = .menuBar(.audio)
        rules.reveal("com.apple.Notes")
        XCTAssertEqual(settings.sidebarSelection, .menuBar(.audio))
        XCTAssertEqual(rules.selection, "com.apple.Notes")
    }

    func testGenericReopenPreservesRuleSearchAndSelection() {
        let rules = RulesNavigation()
        rules.reveal("com.apple.Notes")
        rules.searchText = "Notes"
        rules.reveal()
        XCTAssertEqual(rules.searchText, "Notes")
        XCTAssertEqual(rules.selection, "com.apple.Notes")
    }

    func testExplicitRuleDeepLinkClearsFilterThatCouldHideTarget() {
        let rules = RulesNavigation()
        rules.searchText = "Notes"
        rules.reveal("com.apple.Safari")
        XCTAssertEqual(rules.searchText, "")
        XCTAssertEqual(rules.selection, "com.apple.Safari")
    }

    func testPanelDeepLinksSelectMatchingSidebarEntry() {
        let navigation = SettingsNavigation()
        navigation.selection = .menuBar
        for page in MenuBarSettingsPage.sidebarOrder {
            navigation.menuBarPage = page
            XCTAssertEqual(navigation.sidebarSelection, .menuBar(page))
            XCTAssertEqual(navigation.title, page.title)
        }
    }

    func testSidebarSelectionUpdatesExistingRoutes() {
        let navigation = SettingsNavigation()
        navigation.sidebarSelection = .menuBar(.quickActions)
        XCTAssertEqual(navigation.selection, .menuBar)
        XCTAssertEqual(navigation.menuBarPage, .quickActions)
        navigation.sidebarSelection = .destination(.permissions)
        XCTAssertEqual(navigation.selection, .permissions)
        XCTAssertEqual(navigation.title, SettingsDestination.permissions.title)
        navigation.sidebarSelection = nil
        XCTAssertEqual(navigation.selection, .permissions)
    }

    func testDiagnosticsDoesNotDiscardOpenRuleEditorOrSearch() {
        let settings = SettingsNavigation()
        let rules = RulesNavigation()
        rules.reveal("com.apple.Safari")
        rules.searchText = "Safari"
        settings.openDiagnostics("com.apple.Safari")
        XCTAssertEqual(settings.selection, .permissions)
        XCTAssertEqual(settings.diagnosticBundleID, "com.apple.Safari")
        XCTAssertEqual(rules.selection, "com.apple.Safari")
        XCTAssertEqual(rules.searchText, "Safari")
    }

    func testRepeatedDiagnosticRequestRefreshesEvenForTheSameApplication() {
        let navigation = SettingsNavigation()
        navigation.openDiagnostics("com.apple.Safari")
        let first = navigation.diagnosticRequest
        navigation.openDiagnostics("com.apple.Safari")
        XCTAssertNotEqual(navigation.diagnosticRequest, first)
    }
}
