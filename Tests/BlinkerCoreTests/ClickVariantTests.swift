@testable import BlinkerCore
import CoreGraphics
import XCTest

final class ClickVariantTests: XCTestCase {
    func testRuleEngineVariantLookupUsesLegacyFieldsForLeftClick() {
        let rules = [
            AppRule(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                closeAction: .quitApp,
                zoomAction: .maximize
            ),
        ]
        let engine = RuleEngine(rulesProvider: { rules })

        XCTAssertEqual(engine.action(forBundleIdentifier: "com.apple.Safari", button: .close), .quitApp)
        XCTAssertEqual(engine.action(forBundleIdentifier: "com.apple.Safari", button: .zoom), .maximize)
        XCTAssertNil(engine.action(forBundleIdentifier: "com.apple.Safari", button: .minimize))
    }

    func testRuleEngineVariantLookupReadsExtraSlotsPerButton() {
        var rule = AppRule(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        rule.setAction(.tileLeft, button: .close, variant: .right)
        rule.setAction(.quitApp, button: .close, variant: .optionLeft)
        rule.setAction(.centerWindow, button: .zoom, variant: .longPressLeft)
        let engine = RuleEngine(rulesProvider: { [rule] })

        XCTAssertEqual(
            engine.action(forBundleIdentifier: "com.apple.Safari", button: .close, variant: .right),
            .tileLeft
        )
        XCTAssertEqual(
            engine.action(forBundleIdentifier: "com.apple.Safari", button: .close, variant: .optionLeft),
            .quitApp
        )
        XCTAssertEqual(
            engine.action(forBundleIdentifier: "com.apple.Safari", button: .zoom, variant: .longPressLeft),
            .centerWindow
        )
        // Unconfigured slots and other buttons stay on defaults.
        XCTAssertNil(engine.action(
            forBundleIdentifier: "com.apple.Safari",
            button: .minimize,
            variant: .right
        ))
        XCTAssertNil(engine.action(
            forBundleIdentifier: "com.apple.Safari",
            button: .close,
            variant: .globeLeft
        ))
    }

    func testSetActionNilRestoresDefault() {
        var rule = AppRule(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        rule.setAction(.maximize, button: .close, variant: .globeLeft)
        XCTAssertEqual(rule.action(for: .close, variant: .globeLeft), .maximize)
        rule.setAction(nil, button: .close, variant: .globeLeft)
        XCTAssertNil(rule.action(for: .close, variant: .globeLeft))
        XCTAssertFalse(rule.hasExtraVariantActions == true && rule.extraVariantActions.isEmpty)
    }

    func testHasExtraVariantActionsReflectsConfiguration() {
        var rule = AppRule(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        XCTAssertFalse(rule.hasExtraVariantActions)
        rule.setAction(.quitApp, button: .close, variant: .right)
        XCTAssertTrue(rule.hasExtraVariantActions)
    }

    /// Rules persisted by versions without `extraVariantActions` must still
    /// load and land on the plain left-click slots.
    func testLegacyRuleWithoutVariantActionsDecodes() throws {
        let legacyJSON = """
        [{"bundleIdentifier":"com.apple.Safari","displayName":"Safari",
          "closeAction":"quitApp","minimizeAction":null,"zoomAction":null,"isEnabled":true}]
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode([AppRule].self, from: data)

        XCTAssertEqual(decoded.first?.closeAction, .quitApp)
        XCTAssertTrue(decoded.first?.extraVariantActions.isEmpty ?? false)
        XCTAssertEqual(decoded.first?.action(for: .close, variant: .left), .quitApp)
        XCTAssertNil(decoded.first?.action(for: .close, variant: .right))
    }

    func testRuleRoundTripsThroughJSON() throws {
        var rule = AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .quitApp
        )
        rule.setAction(.tileRight, button: .minimize, variant: .right)
        rule.setAction(.almostMaximize, button: .zoom, variant: .longPressLeft)

        let data = try JSONEncoder().encode([rule])
        let decoded = try JSONDecoder().decode([AppRule].self, from: data)

        XCTAssertEqual(decoded.first, rule)
        XCTAssertEqual(decoded.first?.action(for: .minimize, variant: .right), .tileRight)
        XCTAssertEqual(decoded.first?.action(for: .zoom, variant: .longPressLeft), .almostMaximize)
    }
}
