import Foundation

/// One monotonic deadline and request allowance shared by every read in a scan.
/// Node limits alone do not bound IPC inside large tab groups or slow providers.
struct WindowAXReadBudget {
    private let now: () -> TimeInterval
    private let deadline: TimeInterval
    private var remaining: Int

    init(duration: TimeInterval = 0.25, requests: Int = 800,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        deadline = now() + duration
        remaining = requests
    }

    var isAvailable: Bool {
        remaining > 0 && now() < deadline
    }

    mutating func nextTimeout() -> Float? {
        let interval = min(0.04, deadline - now())
        guard remaining > 0, interval > 0 else { return nil }
        remaining -= 1
        return Float(interval)
    }
}
