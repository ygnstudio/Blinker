@testable import BlinkerApp
import Combine
import IOKit.ps
import XCTest

@MainActor
final class SystemStatusMonitorTests: XCTestCase {
    private final class Reader: SystemStatusReading {
        var onChange: (@MainActor @Sendable () -> Void)?
        var completions: [@MainActor @Sendable (MenuBarSystemSnapshot) -> Void] = []
        var paths: [SystemNetworkPath?] = []
        var stopCount = 0

        func read(path: SystemNetworkPath?,
                  completion: @escaping @MainActor @Sendable (MenuBarSystemSnapshot) -> Void) {
            paths.append(path)
            completions.append(completion)
        }

        func stop() {
            stopCount += 1
        }

        func complete(_ value: MenuBarSystemSnapshot) {
            completions.removeFirst()(value)
        }
    }

    private final class Events: SystemStatusEventObserving {
        var startCount = 0
        var stopCount = 0
        var pathCallbacks: [@MainActor @Sendable (SystemNetworkPath) -> Void] = []

        func start(onChange _: @escaping @MainActor @Sendable () -> Void,
                   onPath: @escaping @MainActor @Sendable (SystemNetworkPath) -> Void) {
            startCount += 1
            pathCallbacks.append(onPath)
        }

        func stop() {
            stopCount += 1
        }
    }

    private let healthy = MenuBarSystemSnapshot(
        battery: .init(percentage: 75, isCharging: false, isConnectedToPower: false, isLowPower: false),
        network: .wired, volume: .init(scalar: 0.5, isMuted: false)
    )
    private let wifi = SystemNetworkPath(isSatisfied: true, usesWiFi: true, usesWired: false)

    func testInitializationDoesNoWorkAndLifecycleIsIdempotent() {
        let reader = Reader()
        let events = Events()
        let monitor = SystemStatusMonitor(reader: reader, events: events)
        XCTAssertEqual(monitor.snapshot, .unknown)
        monitor.refresh()
        monitor.stop()
        XCTAssertTrue(reader.paths.isEmpty)
        XCTAssertEqual(events.startCount, 0)
        monitor.start()
        monitor.start()
        XCTAssertEqual(reader.paths.count, 1)
        XCTAssertEqual(events.startCount, 1)
        monitor.stop()
        monitor.stop()
        XCTAssertEqual(reader.stopCount, 1)
        XCTAssertEqual(events.stopCount, 1)
        reader.complete(healthy)
        XCTAssertEqual(monitor.snapshot, .unknown)
    }

    func testRefreshBurstRetainsOnlyOneFollowUpAndDeduplicatesPublications() {
        let reader = Reader()
        let monitor = SystemStatusMonitor(reader: reader, events: Events())
        var publications = 0
        let subscription = monitor.$snapshot.sink { _ in publications += 1 }
        monitor.start()
        for _ in 0 ..< 100 {
            monitor.refresh()
        }
        XCTAssertEqual(reader.paths.count, 1)
        reader.complete(healthy)
        XCTAssertEqual(reader.paths.count, 2)
        XCTAssertEqual(reader.completions.count, 1)
        reader.complete(healthy)
        XCTAssertEqual(publications, 2)
        XCTAssertTrue(reader.completions.isEmpty)
        monitor.stop()
        withExtendedLifetime(subscription) {}
    }

    func testStopStartKeepsOldReadBoundedAndRejectsItsResultAndOldEvents() {
        let reader = Reader()
        let events = Events()
        let monitor = SystemStatusMonitor(reader: reader, events: events)
        monitor.start()
        monitor.stop()
        monitor.start()
        events.pathCallbacks[0](wifi)
        for _ in 0 ..< 100 {
            monitor.refresh()
        }
        XCTAssertEqual(reader.paths.count, 1, "Restart must not bypass the blocked worker")
        reader.complete(healthy)
        XCTAssertEqual(monitor.snapshot, .unknown)
        XCTAssertEqual(reader.paths.count, 2)
        XCTAssertEqual(reader.paths, [nil, nil])
        reader.complete(healthy)
        XCTAssertEqual(monitor.snapshot, healthy)
        monitor.stop()
    }

    func testChangedNetworkPathRejectsAReadingTakenForTheOldPath() {
        let reader = Reader()
        let events = Events()
        let monitor = SystemStatusMonitor(reader: reader, events: events)
        monitor.start()
        events.pathCallbacks[0](wifi)
        monitor.refresh()
        reader.complete(healthy)
        XCTAssertEqual(monitor.snapshot, .unknown)
        XCTAssertEqual(reader.paths.last, wifi)
        var updated = healthy
        updated.network = .wifi(strength: 2)
        reader.complete(updated)
        XCTAssertEqual(monitor.snapshot, updated)
        monitor.stop()
    }

    func testTimeoutClearsStaleStatusWithoutStartingMoreWorkersAndCanRecover() async {
        let reader = Reader()
        let monitor = SystemStatusMonitor(reader: reader, events: Events(), readTimeout: 0.01)
        monitor.start()
        reader.complete(healthy)
        let timedOut = expectation(description: "Stalled hardware stops reporting healthy status")
        let subscription = monitor.$snapshot.dropFirst().sink { value in
            if value == .unknown {
                timedOut.fulfill()
            }
        }
        monitor.refresh()
        await fulfillment(of: [timedOut], timeout: 1)
        for _ in 0 ..< 100 {
            monitor.refresh()
        }
        XCTAssertEqual(reader.paths.count, 2)
        XCTAssertEqual(reader.completions.count, 1)
        reader.complete(healthy)
        XCTAssertEqual(monitor.snapshot, healthy)
        XCTAssertEqual(reader.paths.count, 3, "Only the coalesced follow-up may start")
        reader.complete(healthy)
        monitor.stop()
        withExtendedLifetime(subscription) {}
    }

    func testRefreshIntervalClampsWithoutRestartingObserversOrStartingReads() {
        let reader = Reader()
        let events = Events()
        let monitor = SystemStatusMonitor(reader: reader, events: events)
        monitor.setRefreshInterval(2)
        XCTAssertEqual(monitor.refreshInterval, 5)
        monitor.start()
        monitor.setRefreshInterval(500)
        XCTAssertEqual(monitor.refreshInterval, 60)
        monitor.setRefreshInterval(.nan)
        XCTAssertEqual(monitor.refreshInterval, 60)
        monitor.setRefreshInterval(15)
        XCTAssertEqual(monitor.refreshInterval, 15)
        XCTAssertEqual(events.startCount, 1)
        XCTAssertEqual(events.stopCount, 0)
        XCTAssertEqual(reader.paths.count, 1)
        monitor.stop()
    }

    func testBatteryParsingKeepsMissingAndInvalidCapacityUnknown() {
        XCTAssertNil(SystemStatusReader.battery(from: [kIOPSTypeKey: "UPS"], lowPower: false))
        var source: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType,
                                     kIOPSCurrentCapacityKey: 20, kIOPSMaxCapacityKey: 80,
                                     kIOPSPowerSourceStateKey: kIOPSACPowerValue]
        XCTAssertEqual(SystemStatusReader.battery(from: source, lowPower: true),
                       .init(percentage: 25, isCharging: false, isConnectedToPower: true, isLowPower: true))
        source[kIOPSMaxCapacityKey] = 0
        XCTAssertNil(SystemStatusReader.battery(from: source, lowPower: false)?.percentage)
        source[kIOPSMaxCapacityKey] = Double.nan
        XCTAssertNil(SystemStatusReader.battery(from: source, lowPower: false)?.percentage)
        source[kIOPSIsPresentKey] = false
        XCTAssertNil(SystemStatusReader.battery(from: source, lowPower: false))
    }

    func testNetworkNeverUsesDisabledWiFiToHideAWiredRouteOrAssumesInternet() {
        let wired = SystemNetworkPath(isSatisfied: true, usesWiFi: false, usesWired: true)
        XCTAssertEqual(
            SystemStatusReader.network(path: wired, powerOn: false, associated: false, rssi: nil),
            .wired
        )
        XCTAssertEqual(
            SystemStatusReader.network(path: nil, powerOn: true, associated: true, rssi: -40),
            .unknown
        )
        XCTAssertEqual(
            SystemStatusReader.network(path: wifi, powerOn: false, associated: false, rssi: 0),
            .off
        )
        for (rssi, strength) in [(-60, 3), (-61, 2), (-78, 2), (-79, 1), (-88, 1), (-89, 0), (0, 0)] {
            XCTAssertEqual(
                SystemStatusReader.network(path: wifi, powerOn: true, associated: true, rssi: rssi),
                .wifi(strength: strength)
            )
        }
        XCTAssertEqual(
            SystemStatusReader.network(path: wifi, powerOn: true, associated: false, rssi: -40),
            .unknown
        )
    }

    func testNetworkClassifiesHotspotAdHocAndSharingInUpstreamOrder() {
        let expensive = SystemNetworkPath(isSatisfied: true, usesWiFi: true, usesWired: false,
                                          isExpensive: true)
        XCTAssertEqual(
            SystemStatusReader.network(path: expensive, powerOn: true, associated: true, rssi: -55),
            .personalHotspot(strength: 3)
        )
        XCTAssertEqual(
            SystemStatusReader.network(path: wifi, powerOn: true, associated: true,
                                       adHoc: true, rssi: -55),
            .temporary
        )
        XCTAssertEqual(
            SystemStatusReader.network(path: wifi, powerOn: true, associated: true,
                                       rssi: -55, sharing: true),
            .sharing
        )
        // Sharing wins over ad-hoc and hotspot; ad-hoc wins over hotspot.
        XCTAssertEqual(
            SystemStatusReader.network(path: expensive, powerOn: true, associated: true,
                                       adHoc: true, rssi: -55, sharing: true),
            .sharing
        )
        XCTAssertEqual(
            SystemStatusReader.network(path: expensive, powerOn: true, associated: true,
                                       adHoc: true, rssi: -55),
            .temporary
        )
    }

    func testInvalidAudioScalarsRemainUnknownAndValidChannelsAreAveraged() {
        XCTAssertNil(SystemAudioStatusReader.average([]))
        XCTAssertNil(SystemAudioStatusReader.average([.nan, .infinity, -1, 2]))
        XCTAssertEqual(SystemAudioStatusReader.average([0.25, 0.75, .nan]), 0.5)
    }
}
