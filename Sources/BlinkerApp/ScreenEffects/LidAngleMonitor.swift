import Combine
import Foundation

enum LidSensorStatus: Equatable, Sendable {
    case idle, reading, available, unavailable, failed
}

struct LidAngleReading: Equatable, Sendable {
    var angle: Double?
    var status: LidSensorStatus
}

@MainActor
protocol LidAngleReadingSource: AnyObject {
    func read(completion: @escaping @MainActor @Sendable (LidAngleReading) -> Void)
    func stop()
}

/// Polling retains at most one hardware read and one pending refresh. A stalled
/// synchronous HID call never causes replacement workers or stale effects.
@MainActor
final class LidAngleMonitor: ObservableObject {
    @Published private(set) var angle: Double?
    @Published private(set) var status: LidSensorStatus = .idle
    // Changes on every valid hardware response, even when the angle stays identical.
    private(set) var readingSequence: UInt64 = 0
    private let source: any LidAngleReadingSource
    private let pollInterval: TimeInterval
    private let failureBackoff: TimeInterval
    private let readTimeout: TimeInterval
    private var timer: Timer?
    private var deadline: Timer?
    private var running = false
    private var generation: UInt64 = 0
    private var inFlight = false
    private var pending = false
    private var readID: UInt64 = 0
    private var readExpired = false
    private var nextPoll = Date.distantPast

    convenience init() {
        self.init(source: LidAngleReader())
    }

    init(source: any LidAngleReadingSource, pollInterval: TimeInterval = 0.05,
         failureBackoff: TimeInterval = 2, readTimeout: TimeInterval = 1) {
        self.source = source
        self.pollInterval = pollInterval.isFinite ? max(0.05, pollInterval) : 0.05
        self.failureBackoff = failureBackoff.isFinite ? max(0.05, failureBackoff) : 2
        self.readTimeout = readTimeout.isFinite ? max(0.001, readTimeout) : 1
    }

    func start() {
        guard !running else { return }
        running = true
        generation &+= 1
        status = .reading
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        timer.tolerance = min(0.01, pollInterval / 5)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        generation &+= 1
        pending = false
        timer?.invalidate()
        timer = nil
        deadline?.invalidate()
        deadline = nil
        angle = nil
        status = .idle
        source.stop()
    }

    func refresh() {
        guard running else { return }
        guard !inFlight else {
            pending = true
            armDeadline()
            return
        }
        pending = false
        inFlight = true
        readExpired = false
        readID &+= 1
        armDeadline()
        let session = generation
        source.read { [weak self] reading in
            guard let self else { return }
            inFlight = false
            deadline?.invalidate()
            deadline = nil
            guard running else { return }
            if session == generation, !readExpired {
                apply(reading)
            }
            if session != generation || (pending && status == .available) {
                refresh()
            } else {
                pending = false
            }
        }
    }

    private func poll() {
        guard Date() >= nextPoll else { return }
        refresh()
    }

    private func apply(_ reading: LidAngleReading) {
        if reading.status == .available, let value = reading.angle,
           value.isFinite, (0 ... 360).contains(value) {
            readingSequence &+= 1
            if angle != value {
                angle = value
            }
            if status != .available {
                status = .available
            }
            nextPoll = .distantPast
        } else {
            angle = nil
            status = reading.status == .unavailable ? .unavailable : .failed
            nextPoll = Date().addingTimeInterval(failureBackoff)
        }
    }

    private func armDeadline() {
        guard deadline == nil else { return }
        let session = generation
        let expectedRead = readID
        let timer = Timer(timeInterval: readTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, running, inFlight, generation == session,
                      readID == expectedRead else { return }
                readExpired = true
                angle = nil
                status = .failed
                nextPoll = Date().addingTimeInterval(failureBackoff)
                // Keep the in-flight latch until the synchronous HID call returns.
            }
        }
        deadline = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit {
        timer?.invalidate()
        deadline?.invalidate()
    }
}
