@testable import BlinkerApp
import XCTest

final class SystemPerformanceTests: XCTestCase {
    private func ticks(_ user: UInt64, _ system: UInt64, _ idle: UInt64,
                       _ nice: UInt64 = 0) -> SystemPerformance.CPUTicks {
        SystemPerformance.CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    func testUsageAveragesBusyTicksAcrossCores() {
        // core 0: 50 busy of 100; core 1: 20 busy of 100 → 70 / 200 = 0.35
        let previous = [ticks(0, 0, 100), ticks(0, 0, 100)]
        let current = [ticks(50, 0, 150), ticks(10, 10, 180)]
        XCTAssertEqual(SystemPerformance.usage(previous: previous, current: current)!,
                       0.35, accuracy: 0.0001)
    }

    func testUsageCountsNiceAsBusy() {
        // 100 ticks pass; 20 of them idle, the other 80 are niced work.
        let previous = [ticks(0, 0, 100)]
        let current = [ticks(0, 0, 120, 80)]
        XCTAssertEqual(SystemPerformance.usage(previous: previous, current: current)!,
                       0.8, accuracy: 0.0001)
    }

    func testUsageRejectsEmptyMismatchedStalledOrRegressingSamples() {
        XCTAssertNil(SystemPerformance.usage(previous: [], current: []))
        XCTAssertNil(SystemPerformance.usage(previous: [ticks(0, 0, 100)], current: []))
        XCTAssertNil(SystemPerformance.usage(previous: [ticks(0, 0, 100)],
                                             current: [ticks(0, 0, 100)]))
        XCTAssertNil(SystemPerformance.usage(previous: [ticks(0, 0, 100)],
                                             current: [ticks(0, 0, 50)]))
    }

    func testUsageIsZeroWhenOnlyIdleAdvances() {
        XCTAssertEqual(SystemPerformance.usage(previous: [ticks(0, 0, 100)],
                                               current: [ticks(0, 0, 200)])!, 0)
    }

    func testUsedMemoryBytesSumsActiveWiredCompressed() {
        XCTAssertEqual(SystemPerformance.usedMemoryBytes(active: 100, wired: 50,
                                                         compressed: 25, pageSize: 16_384),
                       175 * 16_384)
    }

    func testFormatUptimePicksTheLargestTwoUnits() {
        XCTAssertEqual(SystemPerformance.formatUptime(3 * 86_400 + 4 * 3_600 + 30 * 60),
                       "3d 4h")
        XCTAssertEqual(SystemPerformance.formatUptime(5 * 3_600 + 12 * 60), "5h 12m")
        XCTAssertEqual(SystemPerformance.formatUptime(7 * 60), "7m")
        XCTAssertEqual(SystemPerformance.formatUptime(30), "1m")
        XCTAssertEqual(SystemPerformance.formatUptime(0), "1m")
        XCTAssertEqual(SystemPerformance.formatUptime(.nan), "—")
    }
}
