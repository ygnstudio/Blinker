import Foundation

struct DockClickHit: Sendable {
    let applicationURL: URL
    let frame: CGRect
}

struct DockClickCandidate: Sendable {
    let ticket: UUID
    let applicationURL: URL
    let frontmostPIDAtDown: Int32?
    let eligibleWindowIDs: Set<UInt32>?
    let releasedAt: TimeInterval

    func isFresh(at uptime: TimeInterval) -> Bool {
        let age = uptime - releasedAt
        return age.isFinite && age >= 0 && age < 1
    }
}

/// Joins asynchronous Dock hit testing with the original down/up pair. The app
/// that becomes active on mouse-up must never replace the down-time identity.
struct DockClickGesture {
    private struct Press {
        let ticket: UUID
        let point: CGPoint
        let started: TimeInterval
        let frontmostPID: Int32?
        var hit: DockClickHit?
        var released: (point: CGPoint, time: TimeInterval)?
        var eligibleWindowIDs: Set<UInt32>?
    }

    private var press: Press?
    private(set) var ticket = UUID()
    let maximumPressDuration: TimeInterval

    init(maximumPressDuration: TimeInterval = 0.5) {
        self.maximumPressDuration = maximumPressDuration
    }

    mutating func begin(at point: CGPoint, time: TimeInterval, frontmostPID: Int32?,
                        isPlainSingleClick: Bool, candidateRegions: [CGRect]? = nil) -> UUID? {
        cancel()
        guard isPlainSingleClick, time.isFinite else { return nil }
        if let candidateRegions, !candidateRegions.contains(where: { $0.contains(point) }) {
            return nil
        }
        press = Press(ticket: ticket, point: point, started: time, frontmostPID: frontmostPID)
        return ticket
    }

    mutating func resolve(_ hit: DockClickHit?, for request: UUID) -> DockClickCandidate? {
        guard var current = press, current.ticket == request else { return nil }
        guard let hit, hit.frame.contains(current.point) else { cancel(); return nil }
        current.hit = hit
        press = current
        return finishIfReady()
    }

    /// A late snapshot may already contain a window the Dock just restored.
    /// Only evidence collected while the original button is still down counts.
    mutating func snapshot(_ windowIDs: Set<UInt32>, for request: UUID) {
        guard var current = press, current.ticket == request, current.released == nil else { return }
        current.eligibleWindowIDs = windowIDs
        press = current
    }

    mutating func end(at point: CGPoint, time: TimeInterval,
                      isPlainSingleClick: Bool) -> DockClickCandidate? {
        guard var current = press else { return nil }
        let elapsed = time - current.started
        guard isPlainSingleClick, elapsed.isFinite, elapsed >= 0,
              elapsed <= maximumPressDuration else { cancel(); return nil }
        current.released = (point, time)
        press = current
        return finishIfReady()
    }

    mutating func cancel() {
        ticket = UUID()
        press = nil
    }

    private mutating func finishIfReady() -> DockClickCandidate? {
        guard let current = press, let hit = current.hit, let released = current.released else { return nil }
        guard hit.frame.contains(released.point) else { cancel(); return nil }
        press = nil
        return DockClickCandidate(ticket: current.ticket, applicationURL: hit.applicationURL,
                                  frontmostPIDAtDown: current.frontmostPID,
                                  eligibleWindowIDs: current.eligibleWindowIDs, releasedAt: released.time)
    }
}
