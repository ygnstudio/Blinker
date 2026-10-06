@testable import BlinkerApp
import XCTest

/// Resolution switching: option filtering, ordering and titles are pure
/// over injected mode facts; the controller re-lists after every apply.
@MainActor
final class SystemDisplayModesTests: XCTestCase {
    private func raw(_ width: Int, _ height: Int,
                     pixels pixelWidth: Int? = nil, _ pixelHeight: Int? = nil,
                     rate: Double = 60) -> RawDisplayMode {
        RawDisplayMode(width: width, height: height,
                       pixelWidth: pixelWidth ?? width,
                       pixelHeight: pixelHeight ?? height,
                       refreshRate: rate)
    }

    private func option(_ width: Int, _ height: Int,
                        pixels pixelWidth: Int? = nil, _ pixelHeight: Int? = nil,
                        rate: Double = 60, isCurrent: Bool = false) -> DisplayModeOption {
        DisplayModeOption(width: width, height: height,
                          pixelWidth: pixelWidth ?? width,
                          pixelHeight: pixelHeight ?? height,
                          refreshRate: rate,
                          isHiDPI: (pixelWidth ?? width) > width,
                          isCurrent: isCurrent)
    }

    func testEmptyAndDuplicateModesDrop() {
        let options = SystemDisplayModes.makeOptions(
            from: [raw(0, 0), raw(2560, 1440), raw(2560, 1440)], current: nil)
        XCTAssertEqual(options.count, 1)
    }

    func testHiDPIFlagFollowsPixelDensity() {
        let options = SystemDisplayModes.makeOptions(
            from: [raw(2560, 1440, pixels: 5120, 2880), raw(2560, 1440)], current: nil)
        XCTAssertEqual(options.map(\.isHiDPI), [true, false])
    }

    /// Area descends, refresh descends within one area, and the HiDPI
    /// variant leads its standard twin.
    func testOrdering() {
        let options = SystemDisplayModes.makeOptions(from: [
            raw(1920, 1080),
            raw(2560, 1440, rate: 60),
            raw(2560, 1440, pixels: 5120, 2880, rate: 60),
            raw(2560, 1440, rate: 120),
        ], current: nil)
        XCTAssertEqual(options.map(\.refreshRate), [120, 60, 60, 60])
        XCTAssertEqual(options[1].isHiDPI, true)
        XCTAssertEqual(options[3].width, 1920)
    }

    func testCurrentModeMarkedByExactMatch() {
        let options = SystemDisplayModes.makeOptions(
            from: [raw(2560, 1440), raw(1920, 1080)],
            current: raw(1920, 1080))
        XCTAssertEqual(options.map(\.isCurrent), [false, true])
        XCTAssertTrue(SystemDisplayModes.makeOptions(
            from: [raw(2560, 1440)], current: nil).allSatisfy { !$0.isCurrent })
    }

    func testTitleComposition() {
        XCTAssertEqual(option(2560, 1440, rate: 0).title, "2560 × 1440")
        XCTAssertEqual(option(2560, 1440, pixels: 5120, 2880, rate: 0).title, "2560 × 1440 · HiDPI")
        XCTAssertEqual(option(2560, 1440, rate: 59.94).title, "2560 × 1440 · 60Hz")
        // Sub-1 refresh rates mean "not advertised" and stay hidden.
        XCTAssertEqual(option(2560, 1440, rate: 0).title, "2560 × 1440")
    }

    func testControllerAppliesAndReLists() {
        let mode = option(1920, 1080)
        let entry = DisplayEntry(id: 1, name: "内建显示器", modes: [mode])
        var listCalls = 0
        let controller = DisplayModesController(
            listDisplays: { listCalls += 1; return [entry] },
            apply: { _, _ in true }
        )
        XCTAssertEqual(controller.displays, [entry])
        XCTAssertEqual(listCalls, 1)
        controller.setMode(mode, for: entry)
        XCTAssertFalse(controller.applyFailed)
        XCTAssertEqual(listCalls, 2)
    }

    /// A refused switch surfaces once and the re-read list keeps the real
    /// current mode checked.
    func testControllerReportsFailure() {
        let mode = option(1920, 1080)
        let entry = DisplayEntry(id: 1, name: "内建显示器", modes: [mode])
        let controller = DisplayModesController(
            listDisplays: { [entry] },
            apply: { _, _ in false }
        )
        controller.setMode(mode, for: entry)
        XCTAssertTrue(controller.applyFailed)
    }
}
