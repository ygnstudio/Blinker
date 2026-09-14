@testable import BlinkerCore
import XCTest

final class RuleEngineTests: XCTestCase {
    func testReturnsNilWhenNoRuleMatches() {
        let engine = RuleEngine(rulesProvider: { [] })
        XCTAssertNil(engine.action(forBundleIdentifier: "com.apple.Safari", button: .close))
        XCTAssertFalse(engine.hasRule(forBundleIdentifier: "com.apple.Safari"))
    }

    func testReturnsConfiguredActions() {
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
        XCTAssertTrue(engine.hasRule(forBundleIdentifier: "com.apple.Safari"))
    }

    func testNilActionMeansPassthrough() {
        let rules = [
            AppRule(bundleIdentifier: "com.apple.Safari", displayName: "Safari"),
        ]
        let engine = RuleEngine(rulesProvider: { rules })

        XCTAssertTrue(engine.hasRule(forBundleIdentifier: "com.apple.Safari"))
        XCTAssertNil(engine.action(forBundleIdentifier: "com.apple.Safari", button: .close))
        XCTAssertNil(engine.action(forBundleIdentifier: "com.apple.Safari", button: .zoom))
    }

    func testDisabledRuleIsIgnored() {
        var rule = AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .quitApp
        )
        rule.isEnabled = false
        let engine = RuleEngine(rulesProvider: { [rule] })

        XCTAssertFalse(engine.hasRule(forBundleIdentifier: "com.apple.Safari"))
        XCTAssertNil(engine.action(forBundleIdentifier: "com.apple.Safari", button: .close))
    }

    func testMinimizeButtonRespectsRule() {
        let rules = [
            AppRule(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                closeAction: .quitApp,
                minimizeAction: .hideApp
            ),
        ]
        let engine = RuleEngine(rulesProvider: { rules })

        XCTAssertEqual(engine.action(forBundleIdentifier: "com.apple.Safari", button: .minimize), .hideApp)
    }

    func testMinimizeButtonPassthroughWithoutRule() {
        let rules = [
            AppRule(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                closeAction: .quitApp
            ),
        ]
        let engine = RuleEngine(rulesProvider: { rules })
        XCTAssertNil(engine.action(forBundleIdentifier: "com.apple.Safari", button: .minimize))
    }

    /// Rules persisted by versions without `minimizeAction` must still load.
    func testLegacyRuleWithoutMinimizeActionDecodes() throws {
        let legacyJSON = """
        [{"bundleIdentifier":"com.apple.Safari","displayName":"Safari",
          "closeAction":"quitApp","zoomAction":null,"isEnabled":true}]
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode([AppRule].self, from: data)

        XCTAssertEqual(decoded.first?.closeAction, .quitApp)
        XCTAssertNil(decoded.first?.minimizeAction)
    }

    /// Settings persisted by an older version (no `maskStyle`, no
    /// `extraButtonActions`) decode with defaults instead of resetting.
    func testLegacyHoverSettingsWithoutMaskStyleDecode() throws {
        let legacyJSON = """
        {"isEnabled":true,"enlargedSize":36,"dwellMilliseconds":200,
         "appliesToAllWindows":true,"mode":"overlay"}
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(HoverOverlaySettings.self, from: data)

        XCTAssertEqual(decoded.mode, .overlay)
        XCTAssertEqual(decoded.enlargedSize, 36)
    }

    func testRuleStoreRoundTripsThroughDefaults() throws {
        let suiteName = "RuleStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RuleStore(defaults: defaults)
        store.upsert(AppRule(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            closeAction: .quitApp,
            zoomAction: .maximize
        ))

        let reloaded = RuleStore(defaults: defaults)
        XCTAssertEqual(reloaded.snapshot.count, 1)
        XCTAssertEqual(reloaded.snapshot.first?.closeAction, .quitApp)
        XCTAssertEqual(reloaded.snapshot.first?.zoomAction, .maximize)

        reloaded.remove(bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(RuleStore(defaults: defaults).snapshot.isEmpty)
    }
}
