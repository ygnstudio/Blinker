import AppKit
@testable import BlinkerCore
import XCTest

final class ProductBehaviorTests: XCTestCase {
    func testHoverExclusionDoesNotDisableRemapping() {
        let rule = AppRule(bundleIdentifier: "test", displayName: "Test", closeAction: .quitApp,
                           isHoverEnabled: false)
        let engine = RuleEngine { [rule] }
        XCTAssertEqual(engine.action(forBundleIdentifier: "test", button: .close), .quitApp)
        XCTAssertFalse(engine.allowsHover(for: "test", allWindows: true))
        XCTAssertFalse(engine.allowsHover(for: "test", allWindows: false))
    }

    func testDisabledRemappingCanStillHaveHoverInRuleScope() {
        let rule = AppRule(bundleIdentifier: "test", displayName: "Test", isEnabled: false)
        let engine = RuleEngine { [rule] }
        XCTAssertFalse(engine.hasRule(forBundleIdentifier: "test"))
        XCTAssertTrue(engine.allowsHover(for: "test", allWindows: false))
        XCTAssertFalse(engine.allowsHover(for: "other", allWindows: false))
        XCTAssertTrue(engine.allowsHover(for: "other", allWindows: true))
    }

    func testSessionPauseBlocksBothPathsWithoutChangingRules() {
        let pause = SessionPause()
        let rule = AppRule(bundleIdentifier: "test", displayName: "Test", closeAction: .quitApp)
        let engine = RuleEngine(isAppPaused: { pause.contains($0) }, rulesProvider: { [rule] })
        pause.toggle("test")
        XCTAssertFalse(engine.hasRule(forBundleIdentifier: "test"))
        XCTAssertNil(engine.action(forBundleIdentifier: "test", button: .close))
        XCTAssertFalse(engine.allowsHover(for: "test", allWindows: true))
        pause.toggle("test")
        XCTAssertEqual(engine.action(forBundleIdentifier: "test", button: .close), .quitApp)
        XCTAssertTrue(engine.allowsHover(for: "test", allWindows: true))
    }

    func testPresentationUsesMappedActionAndModifierSlot() {
        var rule = AppRule(bundleIdentifier: "test", displayName: "Test", closeAction: .quitApp)
        rule.setAction(.minimize, button: .close, variant: .optionLeft)
        let saved = rule
        let engine = RuleEngine { [saved] }
        let ordinary = OverlayActionPresentation.resolve(engine: engine, bundleID: "test",
                                                         button: .close, variant: .left)
        XCTAssertEqual(ordinary.action, .quitApp)
        XCTAssertEqual(ordinary.symbol, "power")
        XCTAssertEqual(ordinary.label, ButtonAction.quitApp.localizedLabel)
        XCTAssertEqual(OverlayActionPresentation.resolve(engine: engine, bundleID: "test",
                                                         button: .close, variant: .optionLeft).action,
                       .minimize)
        XCTAssertNil(OverlayActionPresentation.resolve(engine: engine, bundleID: "test",
                                                       button: .close, variant: .globeLeft).action)
    }

    func testAppearanceDelayRestartsAfterLeavingOrChangingWindow() {
        var gate = OverlayWakeGate()
        XCTAssertEqual(gate.remaining(for: "one", now: 1, delayMilliseconds: 100), 0.1, accuracy: 0.001)
        XCTAssertEqual(gate.remaining(for: "one", now: 1.05, delayMilliseconds: 100), 0.05, accuracy: 0.001)
        XCTAssertEqual(gate.remaining(for: "two", now: 1.06, delayMilliseconds: 100), 0.1, accuracy: 0.001)
        gate.reset()
        XCTAssertEqual(gate.remaining(for: "two", now: 1.15, delayMilliseconds: 100), 0.1, accuracy: 0.001)
        XCTAssertEqual(gate.remaining(for: "two", now: 1.3, delayMilliseconds: 100), 0)
    }

    func testLegacyRulesAndProtectionMigrateWithoutChangingBehavior() throws {
        let data = Data(#"{"bundleIdentifier":"test","displayName":"Test","isEnabled":false}"#.utf8)
        let rule = try JSONDecoder().decode(AppRule.self, from: data)
        XCTAssertFalse(rule.isEnabled)
        XCTAssertTrue(rule.isHoverEnabled)
        let settings = try JSONDecoder().decode(HoverOverlaySettings.self,
                                                from: Data(#"{"dwellMilliseconds":300}"#.utf8))
        XCTAssertFalse(settings.protectQuitOnly)
        XCTAssertEqual(settings.dwellMilliseconds, 300)
        XCTAssertTrue(HoverOverlaySettings().protectQuitOnly)
    }

    func testOnlyRegisteredTestWindowBypassesOwnAppExclusion() {
        let pid = ProcessInfo.processInfo.processIdentifier
        HoverTestWindow.register(windowID: 71)
        defer { HoverTestWindow.register(windowID: nil) }
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        XCTAssertTrue(HoverTestWindow.contains(.init(processIdentifier: pid, bounds: frame, windowID: 71)))
        XCTAssertFalse(HoverTestWindow.contains(.init(processIdentifier: pid, bounds: frame, windowID: 72)))
        XCTAssertFalse(HoverTestWindow.contains(.init(
            processIdentifier: pid + 1,
            bounds: frame,
            windowID: 71
        )))
    }
}
