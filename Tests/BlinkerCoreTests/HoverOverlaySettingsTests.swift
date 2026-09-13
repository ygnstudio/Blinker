@testable import BlinkerCore
import XCTest

final class HoverOverlaySettingsTests: XCTestCase {
    func testDecodesLegacyJSONWithoutModeKey() throws {
        // Settings persisted by v0.2.0 have no `mode` key; decoding must
        // succeed and fall back to the default overlay mode.
        let legacyJSON = """
        {"isEnabled":true,"enlargedSize":32,"dwellMilliseconds":200,"appliesToAllWindows":false}
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let settings = try JSONDecoder().decode(HoverOverlaySettings.self, from: data)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.enlargedSize, 32)
        XCTAssertEqual(settings.dwellMilliseconds, 200)
        XCTAssertFalse(settings.appliesToAllWindows)
        XCTAssertEqual(settings.mode, .overlay)
    }

    func testHotspotModeForcesImmediateDwell() {
        var settings = HoverOverlaySettings(dwellMilliseconds: 300, mode: .hotspot)
        XCTAssertEqual(settings.effectiveDwellMilliseconds, 0)

        settings.mode = .overlay
        XCTAssertEqual(settings.effectiveDwellMilliseconds, 300)
    }

    func testClampsOutOfRangeValues() {
        let settings = HoverOverlaySettings(enlargedSize: 99, dwellMilliseconds: 5000)
        XCTAssertEqual(settings.enlargedSize, 48)
        XCTAssertEqual(settings.dwellMilliseconds, 800)
    }
}
