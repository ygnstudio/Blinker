import AppKit
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

    func testDecodesLegacyJSONWithoutGlassTintKey() throws {
        // Settings persisted before the Liquid Glass tint existed have no
        // `glassTintColorHex` key; decoding must fall back to "follow the
        // system accent" instead of failing.
        let legacyJSON = """
        {"isEnabled":true,"enlargedSize":28,"dwellMilliseconds":150,"appliesToAllWindows":true}
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let settings = try JSONDecoder().decode(HoverOverlaySettings.self, from: data)

        XCTAssertNil(settings.glassTintColorHex)
    }

    func testGlassTintRoundTripsThroughCodable() throws {
        let settings = HoverOverlaySettings(glassTintColorHex: "#3366CC")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(HoverOverlaySettings.self, from: data)

        XCTAssertEqual(decoded.glassTintColorHex, "#3366CC")
    }

    func testGlassTintHexColorRoundTrip() {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        let hex = GlassTint.hexString(from: color)
        XCTAssertEqual(hex, "#3366CC")

        let decoded = GlassTint.color(fromHex: hex)
        let srgb = decoded?.usingColorSpace(.sRGB)
        XCTAssertEqual(srgb?.redComponent ?? 0, 0.2, accuracy: 0.005)
        XCTAssertEqual(srgb?.greenComponent ?? 0, 0.4, accuracy: 0.005)
        XCTAssertEqual(srgb?.blueComponent ?? 0, 0.8, accuracy: 0.005)

        // Malformed payloads resolve to "no tint".
        XCTAssertNil(GlassTint.color(fromHex: "#XYZ"))
        XCTAssertNil(GlassTint.color(fromHex: "12345"))
        XCTAssertNil(GlassTint.resolved(hex: nil))
    }
}
