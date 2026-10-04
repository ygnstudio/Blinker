@testable import BlinkerApp
import Combine
import XCTest

@MainActor
final class LidAngleMonitorTests: XCTestCase {
    private final class Source: LidAngleReadingSource {
        var reads = 0
        var stops = 0
        var completions: [@MainActor @Sendable (LidAngleReading) -> Void] = []

        func read(completion: @escaping @MainActor @Sendable (LidAngleReading) -> Void) {
            reads += 1
            completions.append(completion)
        }

        func stop() {
            stops += 1
        }

        func complete(_ angle: Double?, status: LidSensorStatus = .available) {
            completions.removeFirst()(.init(angle: angle, status: status))
        }
    }

    func testInitialIdleAndIdempotentLifecycleNeverInventAnAngle() {
        let source = Source()
        let monitor = LidAngleMonitor(source: source)
        XCTAssertEqual(monitor.status, .idle)
        XCTAssertNil(monitor.angle)
        monitor.refresh()
        XCTAssertEqual(source.reads, 0)
        monitor.start()
        monitor.start()
        XCTAssertEqual(source.reads, 1)
        XCTAssertEqual(monitor.status, .reading)
        source.complete(90)
        XCTAssertEqual(monitor.angle, 90)
        XCTAssertEqual(monitor.status, .available)
        monitor.stop()
        monitor.stop()
        XCTAssertEqual(source.stops, 1)
        XCTAssertEqual(monitor.status, .idle)
        XCTAssertNil(monitor.angle)
    }

    func testRefreshBurstKeepsOneHardwareReadAndOnePendingRefresh() {
        let source = Source()
        let monitor = LidAngleMonitor(source: source)
        monitor.start()
        for _ in 0 ..< 1000 {
            monitor.refresh()
        }
        XCTAssertEqual(source.reads, 1)
        XCTAssertEqual(source.completions.count, 1)
        source.complete(120)
        XCTAssertEqual(source.reads, 2)
        source.complete(110)
        XCTAssertEqual(monitor.angle, 110)
        XCTAssertEqual(source.reads, 2)
        monitor.stop()
    }

    func testReadingSequenceDistinguishesFreshIdenticalSamplesFromCachedOrInvalidData() {
        let source = Source()
        let monitor = LidAngleMonitor(source: source)
        monitor.start()
        defer { monitor.stop() }
        XCTAssertEqual(monitor.readingSequence, 0)
        source.complete(90)
        XCTAssertEqual(monitor.readingSequence, 1)
        monitor.refresh()
        XCTAssertEqual(monitor.readingSequence, 1, "A pending read is not new hardware evidence")
        source.complete(90)
        XCTAssertEqual(monitor.readingSequence, 2, "A fresh identical angle still confirms a held position")
        monitor.refresh()
        source.complete(nil, status: .failed)
        XCTAssertEqual(monitor.readingSequence, 2)
        monitor.refresh()
        monitor.stop()
        source.complete(80)
        XCTAssertEqual(monitor.readingSequence, 2, "Late readings cannot confirm an earlier gesture")
    }

    func testStopAndRestartRejectLateResultsWithoutCreatingParallelReads() {
        let source = Source()
        let monitor = LidAngleMonitor(source: source)
        monitor.start()
        monitor.stop()
        monitor.start()
        XCTAssertEqual(source.reads, 1)
        source.complete(15)
        XCTAssertEqual(monitor.readingSequence, 0)
        XCTAssertNil(monitor.angle)
        XCTAssertEqual(monitor.status, .reading)
        XCTAssertEqual(source.reads, 2)
        source.complete(95)
        XCTAssertEqual(monitor.angle, 95)
        monitor.stop()
        XCTAssertNil(monitor.angle)
    }

    func testResultAfterStopCannotRestoreAnEffect() {
        let source = Source()
        let monitor = LidAngleMonitor(source: source)
        monitor.start()
        monitor.stop()
        source.complete(0)
        XCTAssertNil(monitor.angle)
        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(source.reads, 1)
    }

    func testUnavailableInvalidAndFailedReadsClearPreviousAngle() {
        let source = Source()
        let monitor = LidAngleMonitor(source: source)
        monitor.start()
        source.complete(80)
        monitor.refresh()
        source.complete(nil, status: .unavailable)
        XCTAssertNil(monitor.angle)
        XCTAssertEqual(monitor.status, .unavailable)
        for invalid in [Double.nan, .infinity, -1, 361] {
            monitor.refresh()
            source.complete(invalid)
            XCTAssertNil(monitor.angle)
            XCTAssertEqual(monitor.status, .failed)
        }
        monitor.refresh()
        source.complete(0, status: .failed)
        XCTAssertNil(monitor.angle)
        monitor.refresh()
        source.complete(0)
        XCTAssertEqual(monitor.angle, 0, "A genuine closed-lid report remains valid")
        monitor.stop()
    }

    func testUnavailableSensorBacksOffInsteadOfOpeningAtPollingFrequency() async throws {
        let source = Source()
        let monitor = LidAngleMonitor(source: source, failureBackoff: 60)
        monitor.start()
        source.complete(nil, status: .unavailable)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(source.reads, 1)
        monitor.refresh()
        XCTAssertEqual(source.reads, 2, "Explicit retry bypasses automatic polling backoff")
        monitor.stop()
    }

    func testTimeoutClearsAngleAndCannotPublishLateSampleOrLeakWorkers() async {
        let source = Source()
        let monitor = LidAngleMonitor(source: source, pollInterval: 60, readTimeout: 0.01)
        monitor.start()
        source.complete(75)
        let failed = expectation(description: "A blocked sensor clears the last available angle")
        let subscription = monitor.$status.filter { $0 == .failed }.prefix(1).sink { _ in failed.fulfill() }
        monitor.refresh()
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertNil(monitor.angle)
        for _ in 0 ..< 1000 {
            monitor.refresh()
        }
        XCTAssertEqual(source.reads, 2)
        source.complete(10)
        XCTAssertNil(monitor.angle)
        XCTAssertEqual(monitor.status, .failed)
        XCTAssertEqual(source.reads, 2)
        monitor.refresh()
        source.complete(100)
        XCTAssertEqual(monitor.angle, 100)
        XCTAssertEqual(monitor.status, .available)
        monitor.stop()
        withExtendedLifetime(subscription) {}
    }

    func testFeatureReportAcceptsOnlyExpectedIDSizeAndLittleEndianRange() {
        XCTAssertEqual(LidAngleHardware.decodeReport([1, 0, 0]), 0)
        XCTAssertEqual(LidAngleHardware.decodeReport([1, 180, 0]), 180)
        XCTAssertEqual(LidAngleHardware.decodeReport([1, 14, 1]), 270)
        XCTAssertEqual(LidAngleHardware.decodeReport([1, 104, 1, 0, 0, 0, 0, 0]), 360)
        for invalid: [UInt8] in [[], [1], [1, 90], [2, 90, 0], [1, 105, 1],
                                 [1, 255, 255], [1, 90, 0, 0, 0, 0, 0, 0, 0]] {
            XCTAssertNil(LidAngleHardware.decodeReport(invalid))
        }
    }
}
