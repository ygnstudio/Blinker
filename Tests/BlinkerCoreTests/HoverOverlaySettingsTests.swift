@testable import BlinkerCore
import XCTest

final class HoverOverlaySettingsTests: XCTestCase {
    func testDecodesLegacyJSONWithoutModeKey() throws {
        // Settings persisted by v0.2.0 have no `mode` key; decoding must
        // succeed without resetting the other preferences.
        let legacyJSON = """
        {"isEnabled":true,"enlargedSize":32,"dwellMilliseconds":200,"appliesToAllWindows":false}
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let settings = try JSONDecoder().decode(HoverOverlaySettings.self, from: data)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.enlargedSize, 32)
        XCTAssertEqual(settings.dwellMilliseconds, 200)
        XCTAssertFalse(settings.appliesToAllWindows)
    }

    func testObsoleteModesPreservePreferencesAndAreNotEncodedAgain() throws {
        for mode in ["hotspot", "overlay"] {
            let legacyJSON = """
            {"isEnabled":false,"enlargedSize":40,"dwellMilliseconds":300,
             "appliesToAllWindows":false,"mode":"\(mode)","extraButtonActions":["minimize",null]}
            """
            let settings = try JSONDecoder().decode(HoverOverlaySettings.self, from: Data(legacyJSON.utf8))
            XCTAssertFalse(settings.isEnabled)
            XCTAssertEqual(settings.enlargedSize, 40)
            XCTAssertEqual(settings.dwellMilliseconds, 300)
            XCTAssertFalse(settings.appliesToAllWindows)
            XCTAssertEqual(settings.enabledExtraActions, [.minimize])
            let encoded = try JSONEncoder().encode(settings)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertNil(object["mode"])
            XCTAssertEqual(try JSONDecoder().decode(HoverOverlaySettings.self, from: encoded), settings)
        }
    }

    func testClampsOutOfRangeValues() {
        let settings = HoverOverlaySettings(enlargedSize: 99, dwellMilliseconds: 5000)
        XCTAssertEqual(settings.enlargedSize, 48)
        XCTAssertEqual(settings.dwellMilliseconds, 800)
    }
}
