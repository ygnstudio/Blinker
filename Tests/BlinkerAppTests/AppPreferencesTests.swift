@testable import BlinkerApp
import XCTest

@MainActor
final class AppPreferencesTests: XCTestCase {
    private final class RecordingDefaults: UserDefaults, @unchecked Sendable {
        var mutations = 0

        override func set(_ value: Any?, forKey defaultName: String) {
            mutations += 1
            super.set(value, forKey: defaultName)
        }

        override func removeObject(forKey defaultName: String) {
            mutations += 1
            super.removeObject(forKey: defaultName)
        }

        override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
            mutations += 1
            super.setPersistentDomain(domain, forName: domainName)
        }

        override func removePersistentDomain(forName domainName: String) {
            mutations += 1
            super.removePersistentDomain(forName: domainName)
        }
    }

    private func withDefaults(_ body: (RecordingDefaults, String) throws -> Void) throws {
        let domainName = "Blinker.AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: domainName))
        defer { defaults.removePersistentDomain(forName: domainName) }
        try body(defaults, domainName)
    }

    func testInitializationDoesNotWriteOrTreatInheritedLanguageAsAnOverride() throws {
        try withDefaults { defaults, domainName in
            let inheritedName = "\(domainName).inherited"
            let inheritedDefaults = try XCTUnwrap(UserDefaults(suiteName: inheritedName))
            defer {
                defaults.removeSuite(named: inheritedName)
                inheritedDefaults.removePersistentDomain(forName: inheritedName)
            }
            inheritedDefaults.set(["en"], forKey: "AppleLanguages")
            defaults.addSuite(named: inheritedName)
            XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])

            let preferences = AppPreferences(defaults: defaults, domainName: domainName)

            XCTAssertEqual(preferences.language, .system)
            XCTAssertFalse(preferences.languageNeedsRestart)
            XCTAssertEqual(defaults.mutations, 0)
            XCTAssertTrue((defaults.persistentDomain(forName: domainName) ?? [:]).isEmpty)
        }
    }

    func testExplicitLanguagesPersistAndBecomeTheNextLaunchBaseline() throws {
        let choices: [(AppLanguage, String)] = [(.chinese, "zh-Hans"), (.english, "en")]
        for (language, identifier) in choices {
            try withDefaults { defaults, domainName in
                let preferences = AppPreferences(defaults: defaults, domainName: domainName)
                preferences.language = language

                XCTAssertEqual(
                    defaults.persistentDomain(forName: domainName)?["AppleLanguages"] as? [String],
                    [identifier]
                )
                XCTAssertTrue(preferences.languageNeedsRestart)

                let reloadedDefaults = try XCTUnwrap(RecordingDefaults(suiteName: domainName))
                let reloaded = AppPreferences(defaults: reloadedDefaults, domainName: domainName)
                XCTAssertEqual(reloaded.language, language)
                XCTAssertFalse(reloaded.languageNeedsRestart)
                XCTAssertEqual(reloadedDefaults.mutations, 0)
            }
        }
    }

    func testFollowingSystemRemovesOnlyTheLocalOverride() throws {
        try withDefaults { defaults, domainName in
            defaults.register(defaults: ["AppleLanguages": ["en"], "registeredFlag": true])
            let registration = defaults.volatileDomain(
                forName: UserDefaults.registrationDomain
            ) as NSDictionary
            defaults.set(["zh-Hans"], forKey: "AppleLanguages")
            defaults.set("keep", forKey: "unrelatedPreference")
            defaults.set(true, forKey: "isSnapEnabled")
            let preferences = AppPreferences(defaults: defaults, domainName: domainName)

            preferences.language = .system

            let persistent = try XCTUnwrap(defaults.persistentDomain(forName: domainName))
            XCTAssertNil(persistent["AppleLanguages"])
            XCTAssertEqual(persistent["unrelatedPreference"] as? String, "keep")
            XCTAssertEqual(persistent["isSnapEnabled"] as? Bool, true)
            XCTAssertEqual(
                defaults.volatileDomain(forName: UserDefaults.registrationDomain) as NSDictionary,
                registration
            )
            XCTAssertTrue(preferences.languageNeedsRestart)
            let reloaded = AppPreferences(defaults: defaults, domainName: domainName)
            XCTAssertEqual(reloaded.language, .system)
            XCTAssertFalse(reloaded.languageNeedsRestart)
        }
    }

    func testReturningToTheLaunchLanguageClearsTheRestartRequirement() throws {
        let choices: [(AppLanguage, [String]?)] = [
            (.system, nil), (.chinese, ["zh-Hans"]), (.english, ["en"]),
        ]
        for (initialLanguage, identifiers) in choices {
            try withDefaults { defaults, domainName in
                if let identifiers {
                    defaults.set(identifiers, forKey: "AppleLanguages")
                }
                let preferences = AppPreferences(defaults: defaults, domainName: domainName)
                XCTAssertEqual(preferences.language, initialLanguage)
                XCTAssertFalse(preferences.languageNeedsRestart)

                for (language, _) in choices {
                    preferences.language = language
                    XCTAssertEqual(preferences.languageNeedsRestart, language != initialLanguage)
                    preferences.language = initialLanguage
                    XCTAssertFalse(preferences.languageNeedsRestart)
                }
            }
        }
    }
}
