@testable import BlinkerApp
import BlinkerCore
import Foundation
import XCTest

@MainActor
final class RuleWorkspaceTests: XCTestCase {
    private let browser = InstalledApp(bundleIdentifier: "fixture.browser", name: "Browser",
                                       path: "/Applications/Browser.app")
    private let editor = InstalledApp(bundleIdentifier: "fixture.editor", name: "Editor",
                                      path: "/Applications/Editor.app")

    func testCatalogMergesInstalledApplicationsAndRulesWithoutLosingUninstalledApplications() throws {
        let rules = [
            AppRule(bundleIdentifier: browser.id, displayName: "Work Browser", closeAction: .quitApp),
            AppRule(bundleIdentifier: "fixture.legacy", displayName: "Legacy", isEnabled: false),
        ]
        let apps = RuleWorkspaceCatalog.applications(installed: [browser, editor], rules: rules)

        XCTAssertEqual(Set(apps.map(\.id)), Set([browser.id, editor.id, "fixture.legacy"]))
        XCTAssertEqual(apps.count, 3, "An installed application and its rule must share one row")
        let configured = try XCTUnwrap(apps.first { $0.id == browser.id })
        XCTAssertEqual(configured.path, browser.path, "Merging a rule must retain the discovered app path")
        XCTAssertEqual(configured.name, "Work Browser")
        XCTAssertTrue(configured.hasRule)
        let unconfigured = try XCTUnwrap(apps.first { $0.id == editor.id })
        XCTAssertEqual(unconfigured.name, editor.name)
        XCTAssertFalse(unconfigured.hasRule)
        let uninstalled = try XCTUnwrap(apps.first { $0.id == "fixture.legacy" })
        XCTAssertNil(uninstalled.path)
        XCTAssertTrue(uninstalled.hasRule, "A disabled rule remains configured and editable")
    }

    func testSearchMatchesNamesAndBundleIdentifiersWithoutChangingTheFullCatalog() {
        let apps = RuleWorkspaceCatalog.applications(installed: [browser, editor], rules: [])
        let byName = RuleWorkspaceCatalog.filtered(apps, query: "  bRoWsEr\n", onlyConfigured: false)
        let byIdentifier = RuleWorkspaceCatalog.filtered(apps, query: " FIXTURE.EDITOR ",
                                                       onlyConfigured: false)
        XCTAssertEqual(byName.map(\.id), [browser.id])
        XCTAssertEqual(byIdentifier.map(\.id), [editor.id])
        XCTAssertEqual(RuleWorkspaceCatalog.filtered(apps, query: " \n\t ", onlyConfigured: false), apps)
        XCTAssertEqual(Set(apps.map(\.id)), Set([browser.id, editor.id]))
    }

    func testSearchAndConfiguredFilterKeepASelectionThatStillExistsInTheFullCatalog() {
        let rules = [AppRule(bundleIdentifier: browser.id, displayName: browser.name, isEnabled: false)]
        let apps = RuleWorkspaceCatalog.applications(installed: [browser, editor], rules: rules)
        let filters = [("Browser", false), ("", true), ("no matching application", true)]

        for (query, onlyConfigured) in filters {
            let visible = RuleWorkspaceCatalog.filtered(apps, query: query, onlyConfigured: onlyConfigured)
            XCTAssertFalse(visible.contains { $0.id == editor.id })
            XCTAssertEqual(RuleWorkspaceCatalog.selection(editor.id, in: apps), editor.id,
                           "Filtering must not redirect edits to another application's rule")
        }
        let configured = RuleWorkspaceCatalog.filtered(apps, query: "", onlyConfigured: true)
        XCTAssertEqual(configured.map(\.id), [browser.id], "Disabled rules still belong in Configured")
    }

    func testInvalidSelectionFallsBackToAConfiguredApplicationAndHandlesAnEmptyCatalog() {
        let rules = [AppRule(bundleIdentifier: "fixture.uninstalled", displayName: "Uninstalled")]
        let apps = RuleWorkspaceCatalog.applications(installed: [browser, editor], rules: rules)
        XCTAssertEqual(RuleWorkspaceCatalog.selection(nil, in: apps), "fixture.uninstalled")
        XCTAssertEqual(RuleWorkspaceCatalog.selection("fixture.removed", in: apps), "fixture.uninstalled")
        XCTAssertEqual(RuleWorkspaceCatalog.selection(editor.id, in: apps), editor.id)
        XCTAssertNil(RuleWorkspaceCatalog.selection(editor.id, in: []))

        let unconfigured = RuleWorkspaceCatalog.applications(installed: [editor], rules: [])
        XCTAssertEqual(RuleWorkspaceCatalog.selection(nil, in: unconfigured), editor.id)
    }

    func testSelectingAnUnconfiguredApplicationDoesNotCreateRulesOrUndoHistory() throws {
        let suite = "Blinker.RuleWorkspaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = AppRule(bundleIdentifier: browser.id, displayName: browser.name, closeAction: .quitApp)
        let key = "fixture.rules"
        let saved = try JSONEncoder().encode([original])
        defaults.set(saved, forKey: key)
        let store = RuleStore(defaults: defaults, storageKey: key)
        let apps = RuleWorkspaceCatalog.applications(installed: [browser, editor], rules: store.snapshot)

        XCTAssertEqual(RuleWorkspaceCatalog.selection(editor.id, in: apps), editor.id)
        XCTAssertEqual(store.snapshot, [original])
        XCTAssertEqual(defaults.data(forKey: key), saved)
        XCTAssertFalse(store.canUndo, "Browsing applications must not become a persisted edit")
        XCTAssertFalse(store.canRedo)
    }

    func testUnconfiguredOrdinaryClickAndLongPressRetainSystemBehavior() {
        let rule = AppRule(bundleIdentifier: browser.id, displayName: browser.name)
        for button in TrafficButton.allCases {
            for variant in [ClickVariant.left, .longPressLeft] {
                XCTAssertEqual(RulePreviewPresentation.summary(rule: rule, button: button, variant: variant),
                               String(localized: "保留系统按钮行为。"))
            }
        }
    }

    func testExplicitNoOperationIsDifferentFromSystemBehaviorForEveryClickVariant() {
        let system = AppRule(bundleIdentifier: browser.id, displayName: browser.name)
        for button in TrafficButton.allCases {
            for variant in ClickVariant.allCases {
                var configured = system
                // Spell out ButtonAction.none: Optional.none would silently test the default instead.
                configured.setAction(ButtonAction.none, button: button, variant: variant)
                let summary = RulePreviewPresentation.summary(rule: configured, button: button,
                                                              variant: variant)
                XCTAssertTrue(summary.contains(ButtonAction.none.localizedLabel))
                let defaultSummary = RulePreviewPresentation.summary(rule: system, button: button,
                                                                     variant: variant)
                XCTAssertNotEqual(summary, defaultSummary)
            }
        }
    }

    func testUnconfiguredLongPressFallsBackToTheSameButtonsOrdinaryAction() {
        let actions: [(TrafficButton, ButtonAction)] = [
            (.close, .quitApp), (.minimize, .hideApp), (.zoom, .maximize),
        ]
        var rule = AppRule(bundleIdentifier: browser.id, displayName: browser.name)
        for (button, action) in actions {
            rule.setAction(action, button: button, variant: .left)
        }
        for (button, action) in actions {
            let summary = RulePreviewPresentation.summary(rule: rule, button: button, variant: .longPressLeft)
            XCTAssertEqual(summary, String(localized: "长按未配置，按普通单击处理：\(action.localizedLabel)。"))
        }
    }

    func testLongPressInheritsExplicitNoOperationUntilItGetsItsOwnAction() {
        var rule = AppRule(bundleIdentifier: browser.id, displayName: browser.name,
                           closeAction: ButtonAction.none)
        let inherited = RulePreviewPresentation.summary(rule: rule, button: .close, variant: .longPressLeft)
        XCTAssertTrue(inherited.contains(ButtonAction.none.localizedLabel))
        XCTAssertNotEqual(inherited, String(localized: "保留系统按钮行为。"))

        rule.setAction(.quitApp, button: .close, variant: .longPressLeft)
        let overridden = RulePreviewPresentation.summary(rule: rule, button: .close, variant: .longPressLeft)
        XCTAssertTrue(overridden.contains(ButtonAction.quitApp.localizedLabel))
        XCTAssertFalse(overridden.contains(ButtonAction.none.localizedLabel))
        XCTAssertNotEqual(overridden, inherited)
    }

    func testExplicitLongPressNoOperationDoesNotFallBackToAConfiguredOrdinaryClick() {
        var rule = AppRule(bundleIdentifier: browser.id, displayName: browser.name, closeAction: .quitApp)
        rule.setAction(ButtonAction.none, button: .close, variant: .longPressLeft)
        let summary = RulePreviewPresentation.summary(rule: rule, button: .close, variant: .longPressLeft)
        XCTAssertTrue(summary.contains(ButtonAction.none.localizedLabel))
        XCTAssertFalse(summary.contains(ButtonAction.quitApp.localizedLabel))
    }

    func testUnconfiguredEnhancedClicksDoNotInheritTheOrdinaryAction() {
        let rule = AppRule(bundleIdentifier: browser.id, displayName: browser.name, closeAction: .quitApp)
        for variant in [ClickVariant.right, .optionLeft, .globeLeft] {
            let summary = RulePreviewPresentation.summary(rule: rule, button: .close, variant: variant)
            XCTAssertEqual(summary, String(localized: "未配置；原生按钮交由系统处理，悬浮按钮不执行操作。"))
            XCTAssertFalse(summary.contains(ButtonAction.quitApp.localizedLabel))
        }
    }

    func testDisabledRuleSuppressesEveryPreviewActionWithoutDiscardingConfiguration() {
        var rule = AppRule(bundleIdentifier: browser.id, displayName: browser.name,
                           closeAction: .quitApp, minimizeAction: ButtonAction.none, zoomAction: .maximize)
        rule.setAction(.centerWindow, button: .zoom, variant: .longPressLeft)
        let enabled = rule
        rule.isEnabled = false

        for button in TrafficButton.allCases {
            for variant in ClickVariant.allCases {
                XCTAssertEqual(RulePreviewPresentation.summary(rule: rule, button: button, variant: variant),
                               String(localized: "此应用的按钮规则已停用，配置保留。"))
            }
        }
        rule.isEnabled = true
        XCTAssertEqual(rule, enabled)
        XCTAssertTrue(RulePreviewPresentation.summary(rule: rule, button: .zoom, variant: .longPressLeft)
            .contains(ButtonAction.centerWindow.localizedLabel))
    }
}
