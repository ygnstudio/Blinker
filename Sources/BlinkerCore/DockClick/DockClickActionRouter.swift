import Foundation

@MainActor
protocol DockClickWindowSession: AnyObject {
    var hasMinimizedWindows: Bool { get }
    var isBusy: Bool { get }
    func minimize(processIdentifier: Int32?, eligibleWindowIDs: Set<UInt32>?, completion: (() -> Void)?)
        -> Bool
    func restore(activateOriginal: Bool, completion: (() -> Void)?) -> Bool
    func setPaused(_ value: Bool)
    func stop()
}

extension WindowVisibilitySession: DockClickWindowSession {}

/// Restores only this feature's owned windows. A newly activated Dock app with
/// no such batch belongs entirely to the system's ordinary click behavior.
@MainActor
final class DockClickActionRouter {
    var onWillToggle: (() -> Void)?
    private let makeSession: @MainActor () -> any DockClickWindowSession
    private var sessions: [Int32: any DockClickWindowSession] = [:]
    private var paused = true

    init(makeSession: (@MainActor () -> any DockClickWindowSession)? = nil) {
        self.makeSession = makeSession ?? { WindowVisibilitySession() }
    }

    @discardableResult
    func route(pid: Int32, frontmostPIDAtDown: Int32?, currentPID: Int32?,
               eligibleWindowIDs: Set<UInt32>?, isAllowed: Bool) -> Bool {
        guard !paused, isAllowed, currentPID == pid else { return false }
        let existing = sessions[pid]
        guard existing?.isBusy != true else { return false }
        if frontmostPIDAtDown == pid {
            // nil is an unknown/late snapshot; [] is affirmative evidence that
            // native Dock reopening must take precedence over minimization.
            guard let eligibleWindowIDs else { return false }
            if !eligibleWindowIDs.isEmpty {
                let session = existing ?? makeSession()
                sessions[pid] = session
                onWillToggle?()
                return session.minimize(processIdentifier: pid, eligibleWindowIDs: eligibleWindowIDs,
                                        completion: nil)
            }
        }
        if let existing, existing.hasMinimizedWindows {
            onWillToggle?()
            return existing.restore(activateOriginal: false, completion: nil)
        }
        return false
    }

    func hasOwnedWindows(pid: Int32) -> Bool {
        sessions[pid]?.hasMinimizedWindows == true
    }

    func setPaused(_ value: Bool) {
        paused = value
        for session in sessions.values {
            session.setPaused(value)
        }
    }

    func discard(pid: Int32) {
        sessions.removeValue(forKey: pid)?.stop()
    }

    func stop() {
        paused = true
        for session in sessions.values {
            session.stop()
        }
        sessions.removeAll()
    }
}
