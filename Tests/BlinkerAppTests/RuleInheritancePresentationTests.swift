@testable import BlinkerApp
import BlinkerCore
import XCTest

final class RuleInheritancePresentationTests: XCTestCase {
    private var inheritingRule: AppRule {
        .inheritingDefaults(bundleIdentifier: "fixture.browser", displayName: "Browser")
    }

    func testPreviewResolvesEveryInheritedSlotThroughTheRuntimeEngine() {
        for button in TrafficButton.allCases {
            for variant in ClickVariant.allCases {
                var defaults = GlobalButtonRules()
                defaults.setAction(.tileLeft, button: button, variant: variant)
                XCTAssertEqual(RulePreviewPresentation.resolvedAction(
                    rule: inheritingRule, defaults: defaults, button: button, variant: variant
                ), .tileLeft)
                XCTAssertTrue(RulePreviewPresentation.source(
                    rule: inheritingRule, defaults: defaults, button: button, variant: variant
                ).contains(ButtonAction.tileLeft.localizedLabel))
            }
        }
    }

    func testChangingDefaultsRefreshesInheritedPreviewButNotExplicitSystem() {
        var defaults = GlobalButtonRules()
        defaults.setAction(.tileLeft, button: .zoom)
        let rule = inheritingRule
        XCTAssertEqual(RulePreviewPresentation.resolvedAction(
            rule: rule, defaults: defaults, button: .zoom, variant: .left
        ), .tileLeft)
        defaults.setAction(.tileRight, button: .zoom)
        XCTAssertEqual(RulePreviewPresentation.resolvedAction(
            rule: rule, defaults: defaults, button: .zoom, variant: .left
        ), .tileRight)
        var explicit = rule
        explicit.setBinding(.system, button: .zoom)
        XCTAssertNil(RulePreviewPresentation.resolvedAction(
            rule: explicit, defaults: defaults, button: .zoom, variant: .left
        ))
        XCTAssertFalse(RulePreviewPresentation.source(
            rule: explicit, defaults: defaults, button: .zoom, variant: .left
        ).contains(ButtonAction.tileRight.localizedLabel))
    }

    func testLongPressFallbackUsesTheResolvedOrdinaryActionAndPreservesNoOperation() {
        var defaults = GlobalButtonRules()
        defaults.setAction(.quitApp, button: .close)
        var rule = inheritingRule
        XCTAssertEqual(RulePreviewPresentation.resolvedAction(
            rule: rule, defaults: defaults, button: .close, variant: .longPressLeft
        ), .quitApp)
        rule.setBinding(.action(.none), button: .close, variant: .longPressLeft)
        XCTAssertEqual(RulePreviewPresentation.resolvedAction(
            rule: rule, defaults: defaults, button: .close, variant: .longPressLeft
        ), ButtonAction.none)
    }

    func testDisabledRuleSuppressesInheritedDiagramAndSummary() {
        var defaults = GlobalButtonRules()
        defaults.setAction(.quitApp, button: .close)
        var rule = inheritingRule
        rule.isEnabled = false
        XCTAssertNil(RulePreviewPresentation.resolvedAction(
            rule: rule, defaults: defaults, button: .close, variant: .left
        ))
        XCTAssertEqual(RulePreviewPresentation.summary(
            rule: rule, defaults: defaults, button: .close, variant: .left
        ), String(localized: "此应用的按钮规则已停用，配置保留。"))
    }

    func testLegacySystemSlotsDoNotAcquireGlobalActionsInThePreview() {
        let legacy = AppRule(bundleIdentifier: "fixture.legacy", displayName: "Legacy")
        var defaults = GlobalButtonRules()
        defaults.setAction(.quitApp, button: .close)
        XCTAssertNil(RulePreviewPresentation.resolvedAction(
            rule: legacy, defaults: defaults, button: .close, variant: .left
        ))
        XCTAssertEqual(RulePreviewPresentation.summary(
            rule: legacy, defaults: defaults, button: .close, variant: .left
        ), String(localized: "保留系统按钮行为。"))
    }
}
