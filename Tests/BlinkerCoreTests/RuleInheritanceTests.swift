@testable import BlinkerCore
import XCTest

final class RuleInheritanceTests: XCTestCase {
    func testLegacyMissingBindingsRemainExplicitSystemForEverySlot() throws {
        let data = Data(#"{"bundleIdentifier":"legacy","displayName":"Legacy"}"#.utf8)
        let rule = try JSONDecoder().decode(AppRule.self, from: data)
        XCTAssertTrue(rule.inheritedSlots.isEmpty)
        for slot in RuleActionSlot.all {
            XCTAssertEqual(rule.binding(for: slot.button, variant: slot.variant), .system)
        }
    }

    func testNewExceptionInheritsEverySlotWithoutInventingAnApplicationIdentity() {
        let rule = AppRule.inheritingDefaults(bundleIdentifier: "app.real", displayName: "Real")
        XCTAssertEqual(rule.id, "app.real")
        XCTAssertEqual(rule.inheritedSlots.count, TrafficButton.allCases.count * ClickVariant.allCases.count)
        for slot in RuleActionSlot.all {
            XCTAssertEqual(rule.binding(for: slot.button, variant: slot.variant), .inherit)
        }
    }

    func testBindingTransitionsDistinguishSystemInheritanceAndInterceptedNoOp() throws {
        var rule = AppRule.inheritingDefaults(bundleIdentifier: "app", displayName: "App")
        rule.setBinding(.action(.none), button: .close)
        XCTAssertEqual(rule.binding(for: .close), .action(.none))
        XCTAssertEqual(rule.action(for: .close, variant: .left), ButtonAction.none)
        rule.setBinding(.system, button: .close)
        XCTAssertEqual(rule.binding(for: .close), .system)
        XCTAssertNil(rule.action(for: .close, variant: .left))
        rule.setBinding(.inherit, button: .close)
        XCTAssertEqual(rule.binding(for: .close), .inherit)
        XCTAssertNil(rule.action(for: .close, variant: .left))
        XCTAssertEqual(try JSONDecoder().decode(AppRule.self, from: JSONEncoder().encode(rule)), rule)
    }

    func testLegacySetterAlwaysReplacesInheritanceWithAnExplicitChoice() {
        var rule = AppRule.inheritingDefaults(bundleIdentifier: "app", displayName: "App")
        rule.setAction(nil, button: .zoom, variant: .optionLeft)
        XCTAssertEqual(rule.binding(for: .zoom, variant: .optionLeft), .system)
        rule.setAction(.tileLeft, button: .close, variant: .left)
        XCTAssertEqual(rule.binding(for: .close), .action(.tileLeft))
        XCTAssertEqual(rule.binding(for: .minimize), .inherit)
    }

    func testCopyIncludesBindingsAndKeepsTargetIdentity() {
        var source = AppRule.inheritingDefaults(bundleIdentifier: "source", displayName: "Source")
        source.setBinding(.system, button: .close)
        source.setBinding(.action(.none), button: .zoom, variant: .right)
        source.isHoverEnabled = false
        let target = AppRule(bundleIdentifier: "target", displayName: "Target")
        let result = RuleTransfer.copying(source, to: target)
        XCTAssertEqual(result.id, target.id)
        XCTAssertEqual(result.displayName, target.displayName)
        XCTAssertEqual(result.inheritedSlots, source.inheritedSlots)
        XCTAssertEqual(result.binding(for: .zoom, variant: .right), .action(.none))
        XCTAssertFalse(result.isHoverEnabled)
    }

    func testUnlistedApplicationUsesGlobalActionsForEveryVariant() {
        var defaults = GlobalButtonRules()
        for variant in ClickVariant.allCases {
            defaults.setAction(.hideApp, button: .close, variant: variant)
        }
        let configuration = RuleConfiguration(globalDefaults: defaults)
        let engine = RuleEngine(configurationProvider: { configuration })
        XCTAssertTrue(engine.hasRule(forBundleIdentifier: "unlisted"))
        for variant in ClickVariant.allCases {
            XCTAssertEqual(engine.action(forBundleIdentifier: "unlisted", button: .close, variant: variant),
                           .hideApp)
        }
        XCTAssertNil(engine.action(forBundleIdentifier: "unlisted", button: .zoom))
    }

    func testOldExplicitSystemDoesNotFallThroughToGlobalQuit() {
        var defaults = GlobalButtonRules()
        defaults.setAction(.quitApp, button: .close)
        defaults.setAction(.hideApp, button: .close, variant: .longPressLeft)
        let rule = AppRule(bundleIdentifier: "legacy", displayName: "Legacy")
        let configuration = RuleConfiguration(rules: [rule], globalDefaults: defaults)
        let engine = RuleEngine(configurationProvider: { configuration })
        XCTAssertNil(engine.action(forBundleIdentifier: "legacy", button: .close))
        XCTAssertNil(engine.action(forBundleIdentifier: "legacy", button: .close, variant: .longPressLeft))
        XCTAssertEqual(engine.action(forBundleIdentifier: "other", button: .close), .quitApp)
    }

    func testExplicitOverrideWinsAndInheritedSlotsTrackTheirOwnGlobalVariant() {
        var defaults = GlobalButtonRules()
        defaults.setAction(.quitApp, button: .close)
        defaults.setAction(.tileRight, button: .zoom, variant: .optionLeft)
        var rule = AppRule.inheritingDefaults(bundleIdentifier: "app", displayName: "App")
        rule.setBinding(.action(.none), button: .close)
        rule.setBinding(.system, button: .zoom)
        let configuration = RuleConfiguration(rules: [rule], globalDefaults: defaults)
        let engine = RuleEngine(configurationProvider: { configuration })
        XCTAssertEqual(engine.action(forBundleIdentifier: "app", button: .close), ButtonAction.none)
        XCTAssertNil(engine.action(forBundleIdentifier: "app", button: .zoom))
        XCTAssertEqual(engine.action(forBundleIdentifier: "app", button: .zoom, variant: .optionLeft),
                       .tileRight)
    }

    func testDisabledRuleSuppressesGlobalFallbackButKeepsIndependentHover() {
        var defaults = GlobalButtonRules()
        defaults.setAction(.quitApp, button: .close)
        var rule = AppRule.inheritingDefaults(bundleIdentifier: "disabled", displayName: "Disabled")
        rule.isEnabled = false
        let configuration = RuleConfiguration(rules: [rule], globalDefaults: defaults)
        let engine = RuleEngine(configurationProvider: { configuration })
        XCTAssertFalse(engine.hasRule(forBundleIdentifier: "disabled"))
        XCTAssertNil(engine.action(forBundleIdentifier: "disabled", button: .close))
        XCTAssertTrue(engine.allowsHover(for: "disabled", allWindows: false))
    }

    func testPauseWinsOverGlobalActionsAndHoverForUnlistedApplications() {
        var defaults = GlobalButtonRules()
        defaults.setAction(.quitApp, button: .close)
        let configuration = RuleConfiguration(globalDefaults: defaults)
        let engine = RuleEngine(isAppPaused: { $0 == "paused" }, configurationProvider: { configuration })
        XCTAssertFalse(engine.hasRule(forBundleIdentifier: "paused"))
        XCTAssertNil(engine.action(forBundleIdentifier: "paused", button: .close))
        XCTAssertFalse(engine.allowsHover(for: "paused", allWindows: true))
        XCTAssertTrue(engine.hasRule(forBundleIdentifier: "other"))
    }

    func testGlobalRulesDoNotExpandApplicationScopedHoverOrEmptyInterception() {
        var defaults = GlobalButtonRules()
        defaults.setAction(ButtonAction.none, button: .close)
        let configuration = RuleConfiguration(globalDefaults: defaults)
        let engine = RuleEngine(configurationProvider: { configuration })
        XCTAssertTrue(engine.hasRule(forBundleIdentifier: "unlisted"))
        XCTAssertFalse(engine.allowsHover(for: "unlisted", allWindows: false))
        XCTAssertTrue(engine.allowsHover(for: "unlisted", allWindows: true))
        defaults.setAction(nil, button: .close)
        XCTAssertFalse(defaults.hasConfiguredActions)
        let empty = RuleEngine(configurationProvider: { RuleConfiguration() })
        XCTAssertFalse(empty.hasRule(forBundleIdentifier: "unlisted"))
    }
}
