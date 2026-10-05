@testable import BlinkerApp
import XCTest

final class SystemNetworkActivityTests: XCTestCase {
    // MARK: Rate

    func testRateAveragesDeltaOverElapsed() {
        let rate = SystemNetworkActivity.rate(previous: 1_000, current: 31_000, elapsed: 15)
        XCTAssertEqual(rate ?? 0, 2_000, accuracy: 0.001)
    }

    func testRateRecoversOneThirtyTwoBitWrap() {
        let previous = UInt64(UInt32.max) - 100
        let rate = SystemNetworkActivity.rate(previous: previous, current: 399, elapsed: 5)
        // 101 counts up to the wrap, then 399 more.
        XCTAssertEqual(rate ?? 0, 100, accuracy: 0.001)
    }

    func testRateRejectsTightBurstsAndNonFiniteElapsed() {
        XCTAssertNil(SystemNetworkActivity.rate(previous: 0, current: 100, elapsed: 0.1))
        XCTAssertNil(SystemNetworkActivity.rate(previous: 0, current: 100, elapsed: .nan))
    }

    // MARK: Formatting

    func testFormatRateScalesAndRounds() {
        XCTAssertEqual(SystemNetworkActivity.formatRate(nil), "0 B/s")
        XCTAssertEqual(SystemNetworkActivity.formatRate(0), "0 B/s")
        XCTAssertEqual(SystemNetworkActivity.formatRate(.nan), "0 B/s")
        XCTAssertEqual(SystemNetworkActivity.formatRate(512), "512 B/s")
        XCTAssertEqual(SystemNetworkActivity.formatRate(1_200), "1.2 KB/s")
        XCTAssertEqual(SystemNetworkActivity.formatRate(1_200_000), "1.2 MB/s")
        XCTAssertEqual(SystemNetworkActivity.formatRate(120_000_000), "120 MB/s")
        XCTAssertEqual(SystemNetworkActivity.formatRate(1_500_000_000), "1.5 GB/s")
    }

    // MARK: Aggregation

    func testTotalsSumCountersAndPickFirstAddress() {
        let totals = SystemNetworkActivity.totals(interfaces: [
            .init(name: "en0", bytesIn: 10, bytesOut: 20, ipv4Address: nil),
            .init(name: "en0", bytesIn: 0, bytesOut: 0, ipv4Address: "192.168.1.5"),
            .init(name: "en1", bytesIn: 5, bytesOut: 7, ipv4Address: "10.0.0.2"),
        ])
        XCTAssertEqual(totals?.bytesIn, 15)
        XCTAssertEqual(totals?.bytesOut, 27)
        XCTAssertEqual(totals?.localIPv4, "192.168.1.5")
    }

    func testTotalsPreferRoutableAddressOverLinkLocal() {
        let totals = SystemNetworkActivity.totals(interfaces: [
            .init(name: "en3", bytesIn: 0, bytesOut: 0, ipv4Address: "169.254.10.20"),
            .init(name: "en0", bytesIn: 1, bytesOut: 1, ipv4Address: "172.20.10.4"),
        ])
        XCTAssertEqual(totals?.localIPv4, "172.20.10.4")
        let linkLocalOnly = SystemNetworkActivity.totals(interfaces: [
            .init(name: "en3", bytesIn: 0, bytesOut: 0, ipv4Address: "169.254.10.20"),
        ])
        XCTAssertEqual(linkLocalOnly?.localIPv4, "169.254.10.20")
    }

    func testTotalsNilWithoutInterfacesAndEligibilityIsEnOnly() {
        XCTAssertNil(SystemNetworkActivity.totals(interfaces: []))
        XCTAssertTrue(SystemNetworkActivity.isEligible(name: "en0"))
        XCTAssertTrue(SystemNetworkActivity.isEligible(name: "en12"))
        XCTAssertFalse(SystemNetworkActivity.isEligible(name: "lo0"))
        XCTAssertFalse(SystemNetworkActivity.isEligible(name: "utun4"))
        XCTAssertFalse(SystemNetworkActivity.isEligible(name: "awdl0"))
        XCTAssertFalse(SystemNetworkActivity.isEligible(name: "bridge0"))
    }

    // MARK: Public address sanitizing

    func testSanitizedAcceptsPlainAddresses() {
        XCTAssertEqual(PublicIPProbe.sanitized("203.0.113.7"), "203.0.113.7")
        XCTAssertEqual(PublicIPProbe.sanitized("  203.0.113.7\n"), "203.0.113.7")
        XCTAssertEqual(PublicIPProbe.sanitized("2001:db8::1"), "2001:db8::1")
    }

    func testSanitizedRejectsMarkupAndGarbage() {
        XCTAssertNil(PublicIPProbe.sanitized(""))
        XCTAssertNil(PublicIPProbe.sanitized("   "))
        XCTAssertNil(PublicIPProbe.sanitized("<html>203.0.113.7</html>"))
        XCTAssertNil(PublicIPProbe.sanitized("not an address"))
        XCTAssertNil(PublicIPProbe.sanitized("...."))
        XCTAssertNil(PublicIPProbe.sanitized(String(repeating: "1.", count: 40)))
    }
}
