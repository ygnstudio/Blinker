import AppKit
import Combine

struct WindowVisibilityResult: Sendable {
    var ownedCount: Int
    var failures: Int
}

/// Only this cancellation flag crosses queues. A cancelled write still gets its
/// readback so windows already minimized remain eligible for an explicit restore.
final class WindowVisibilityCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

@MainActor
protocol WindowMinimizationOperating: AnyObject {
    func minimize(pid: Int32?, eligibleWindowIDs: Set<UInt32>?, cancellation: WindowVisibilityCancellation,
                  completion: @escaping @MainActor (WindowVisibilityResult) -> Void) -> Bool
    func restore(activateOriginal: Bool, cancellation: WindowVisibilityCancellation,
                 completion: @escaping @MainActor (WindowVisibilityResult) -> Void) -> Bool
    func discard()
}

/// Owns one reversible batch for either Show Desktop or a single Dock app.
/// Space changes discard the batch: public APIs cannot safely locate minimized
/// windows' Spaces, and restoring must never pull the user to another desktop.
@MainActor
public final class WindowVisibilitySession: ObservableObject {
    @Published public private(set) var hasMinimizedWindows = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastFailureCount = 0
    private let backend: any WindowMinimizationOperating
    private var cancellation: WindowVisibilityCancellation?
    private var generation: UInt64 = 0
    private var paused = false
    private var spaceObserver: NSObjectProtocol?
    private let operationTimeout: TimeInterval
    private var deadline: Timer?
    private var timedOut = false

    public convenience init(service: WindowMinimizationService? = nil) {
        self.init(backend: WindowMinimizationBackend(service: service ?? .shared), observeSpaces: true)
    }

    init(backend: any WindowMinimizationOperating, observeSpaces: Bool = false,
         operationTimeout: TimeInterval = 4) {
        self.backend = backend
        self.operationTimeout = operationTimeout
        if observeSpaces {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
    }

    /// Returns false when paused or another batch is still in flight; no callback then runs.
    @discardableResult
    public func minimize(processIdentifier: Int32? = nil, eligibleWindowIDs: Set<UInt32>? = nil,
                         completion: (() -> Void)? = nil) -> Bool {
        perform(completion: completion) { token, finish in
            backend.minimize(pid: processIdentifier, eligibleWindowIDs: eligibleWindowIDs,
                             cancellation: token, completion: finish)
        }
    }

    @discardableResult
    public func restore(activateOriginal: Bool = false, completion: (() -> Void)? = nil) -> Bool {
        guard hasMinimizedWindows else { return false }
        return perform(completion: completion) { token, finish in
            backend.restore(activateOriginal: activateOriginal, cancellation: token, completion: finish)
        }
    }

    public func setPaused(_ value: Bool) {
        paused = value
        if value {
            cancelPending()
        }
    }

    /// Stops further writes while preserving verified successes from this batch.
    public func cancelPending() {
        cancellation?.cancel()
    }

    /// Discards restore eligibility without changing any window. Already minimized
    /// windows remain accessible through the Dock, including after a Space change.
    public func stop() {
        generation &+= 1
        cancellation?.cancel()
        deadline?.invalidate()
        deadline = nil
        backend.discard()
        hasMinimizedWindows = false
        lastFailureCount = 0
    }

    private func perform(completion: (() -> Void)?,
                         action: (WindowVisibilityCancellation,
                                  @escaping @MainActor (WindowVisibilityResult) -> Void) -> Bool) -> Bool {
        guard !paused, cancellation == nil else { return false }
        let token = WindowVisibilityCancellation()
        let session = generation
        cancellation = token
        isBusy = true
        lastFailureCount = 0
        timedOut = false
        let accepted = action(token) { [weak self] result in
            guard let self else { return }
            cancellation = nil
            isBusy = false
            deadline?.invalidate()
            deadline = nil
            if generation == session {
                hasMinimizedWindows = result.ownedCount > 0
                lastFailureCount = max(result.failures, timedOut ? 1 : 0)
            }
            completion?()
        }
        if !accepted {
            cancellation = nil
            isBusy = false
        } else if cancellation === token {
            installDeadline(token)
        }
        return accepted
    }

    private func installDeadline(_ token: WindowVisibilityCancellation) {
        let timer = Timer(timeInterval: operationTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, cancellation === token else { return }
                timedOut = true
                lastFailureCount = max(1, lastFailureCount)
                token.cancel()
                // Retain the busy slot until the worker returns, even after a timeout.
            }
        }
        deadline = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit {
        cancellation?.cancel()
        deadline?.invalidate()
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
    }
}
