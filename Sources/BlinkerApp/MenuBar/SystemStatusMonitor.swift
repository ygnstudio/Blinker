// Monitoring design adapted from Status Trio, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: restartable, read-only, bounded workers, no device names or SSIDs.
// See ThirdParty/StatusTrio for license and attribution.
import Combine
import Foundation
import IOKit.ps
import Network

struct SystemNetworkPath: Equatable, Sendable {
    var isSatisfied: Bool
    var usesWiFi: Bool
    var usesWired: Bool
    var isExpensive = false
}

@MainActor
protocol SystemStatusReading: AnyObject {
    var onChange: (@MainActor @Sendable () -> Void)? { get set }
    func read(
        path: SystemNetworkPath?,
        completion: @escaping @MainActor @Sendable (MenuBarSystemSnapshot) -> Void
    )
    func stop()
}

@MainActor
protocol SystemStatusEventObserving: AnyObject {
    func start(onChange: @escaping @MainActor @Sendable () -> Void,
               onPath: @escaping @MainActor @Sendable (SystemNetworkPath) -> Void)
    func stop()
}

/// One read may be outstanding, even across stop/start. A stuck system service
/// costs at most that worker; events retain one follow-up, never another queue.
@MainActor
final class SystemStatusMonitor: ObservableObject {
    @Published private(set) var snapshot = MenuBarSystemSnapshot.unknown
    private let reader: any SystemStatusReading
    private let events: any SystemStatusEventObserving
    private(set) var refreshInterval: TimeInterval
    private let readTimeout: TimeInterval
    private var timer: Timer?
    private var debounce: Timer?
    private var deadline: Timer?
    private var readID: UInt64 = 0
    private var readTimedOut = false
    private var path: SystemNetworkPath?
    private var isRunning = false
    private var generation: UInt64 = 0
    private var inFlight = false
    private var pending = false

    convenience init() {
        self.init(reader: SystemStatusReader(), events: SystemStatusEvents())
    }

    init(reader: any SystemStatusReading, events: any SystemStatusEventObserving,
         refreshInterval: TimeInterval = 30, readTimeout: TimeInterval = 5) {
        self.reader = reader
        self.events = events
        self.refreshInterval = refreshInterval.isFinite ? min(60, max(5, refreshInterval)) : 30
        self.readTimeout = readTimeout
        reader.onChange = { [weak self] in self?.scheduleRefresh() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation &+= 1
        let session = generation
        events.start(onChange: { [weak self] in
            guard let self, isRunning, generation == session else { return }
            scheduleRefresh()
        }, onPath: { [weak self] update in
            guard let self, isRunning, generation == session, path != update else { return }
            path = update
            scheduleRefresh()
        })
        installRefreshTimer()
        refresh()
    }

    func setRefreshInterval(_ seconds: Double) {
        guard seconds.isFinite else { return }
        let interval = min(60, max(5, seconds))
        guard interval != refreshInterval else { return }
        refreshInterval = interval
        if isRunning {
            installRefreshTimer()
        }
    }

    private func installRefreshTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer.tolerance = refreshInterval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        pending = false
        path = nil
        timer?.invalidate()
        timer = nil
        debounce?.invalidate()
        debounce = nil
        deadline?.invalidate()
        deadline = nil
        readTimedOut = false
        events.stop()
        reader.stop()
    }

    func refresh() {
        guard isRunning else { return }
        guard !inFlight else {
            pending = true
            armReadTimeout()
            return
        }
        debounce?.invalidate()
        debounce = nil
        inFlight = true
        pending = false
        readID &+= 1
        readTimedOut = false
        armReadTimeout()
        let session = generation
        let capturedPath = path
        reader.read(path: capturedPath) { [weak self] value in
            guard let self else { return }
            inFlight = false
            deadline?.invalidate()
            deadline = nil
            guard isRunning else { return }
            if session == generation, capturedPath == path, value != snapshot {
                snapshot = value
            }
            if pending || session != generation || capturedPath != path {
                refresh()
            }
        }
    }

    private func armReadTimeout() {
        guard deadline == nil, !readTimedOut else { return }
        let session = generation
        let expectedRead = readID
        let timer = Timer(timeInterval: readTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isRunning, inFlight, generation == session,
                      readID == expectedRead else { return }
                readTimedOut = true
                deadline = nil
                if snapshot != .unknown {
                    snapshot = .unknown
                }
                // The hardware call is not cancellable. Keep its latch and worker
                // instead of leaking another thread on each watchdog timeout.
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadline = timer
    }

    private func scheduleRefresh() {
        guard isRunning, debounce == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        debounce = timer
    }

    deinit {
        timer?.invalidate()
        debounce?.invalidate()
        deadline?.invalidate()
    }
}

/// The C callback owns no object pointer, so a late power notification cannot
/// dereference an already stopped monitor. Other callbacks also carry a session.
@MainActor
private final class SystemStatusEvents: SystemStatusEventObserving {
    private static let powerChanged = Notification.Name("BlinkerMenuBarPowerChanged")
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "Blinker.MenuBar.Network", qos: .utility)

    func start(onChange: @escaping @MainActor @Sendable () -> Void,
               onPath: @escaping @MainActor @Sendable (SystemNetworkPath) -> Void) {
        guard pathMonitor == nil else { return }
        for name in [Self.powerChanged, .NSProcessInfoPowerStateDidChange] {
            observers
                .append(NotificationCenter.default
                    .addObserver(forName: name, object: nil, queue: .main) { _ in
                        Task { @MainActor in onChange() }
                    })
        }
        source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(
                name: Notification.Name("BlinkerMenuBarPowerChanged"),
                object: nil
            )
        }, nil)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let value = SystemNetworkPath(isSatisfied: path.status == .satisfied,
                                          usesWiFi: path.usesInterfaceType(.wifi),
                                          usesWired: path.usesInterfaceType(.wiredEthernet),
                                          isExpensive: path.isExpensive)
            Task { @MainActor in onPath(value) }
        }
        pathMonitor = monitor
        monitor.start(queue: pathQueue)
    }

    func stop() {
        if let source {
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    deinit {
        if let source {
            CFRunLoopSourceInvalidate(source)
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        pathMonitor?.cancel()
    }
}
