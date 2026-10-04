import AppKit

/// One admission gate and one AX queue are shared by Dock and Show Desktop.
/// Busy requests are rejected instead of building an unbounded operation queue.
@MainActor
public final class WindowMinimizationService {
    public static let shared = WindowMinimizationService()
    let queue = DispatchQueue(label: "Blinker.WindowVisibility.AX", qos: .userInitiated)
    private var active: WindowVisibilityCancellation?
    private var reasons = Set<String>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public init() {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if session["CGSSessionScreenIsLocked"] as? Bool == true {
                reasons.insert("lock")
            }
            if session[kCGSessionOnConsoleKey as String] as? Bool == false {
                reasons.insert("session")
            }
        } else {
            reasons.insert("session")
        }
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.willSleepNotification, reason: "sleep", suspended: true)
        observe(center, NSWorkspace.didWakeNotification, reason: "sleep", suspended: false)
        observe(center, NSWorkspace.screensDidSleepNotification, reason: "display", suspended: true)
        observe(center, NSWorkspace.screensDidWakeNotification, reason: "display", suspended: false)
        observe(center, NSWorkspace.sessionDidResignActiveNotification, reason: "session", suspended: true)
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification, reason: "session", suspended: false)
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, .init("com.apple.screenIsLocked"), reason: "lock", suspended: true)
        observe(distributed, .init("com.apple.screenIsUnlocked"), reason: "lock", suspended: false)
    }

    func acquire(_ token: WindowVisibilityCancellation) -> Bool {
        guard active == nil, reasons.isEmpty, AccessibilityPermission.isTrusted else { return false }
        active = token
        return true
    }

    func finish(_ token: WindowVisibilityCancellation) {
        if active === token {
            active = nil
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         reason: String, suspended: Bool) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if suspended {
                    self.reasons.insert(reason); self.active?.cancel()
                } else {
                    self.reasons.remove(reason)
                }
            }
        }
        observers.append((center, observer))
    }

    deinit { for (center, observer) in observers {
        center.removeObserver(observer)
    } }
}

@MainActor
final class WindowMinimizationBackend: WindowMinimizationOperating {
    @MainActor
    private final class NativeTarget {
        weak var window: NSWindow?
        let number: Int
        let wasFocused: Bool
        init(_ window: NSWindow, focused: Bool) {
            self.window = window
            number = window.windowNumber
            wasFocused = focused
        }
    }

    private struct NativeBatch {
        let requests: [NativeTarget]
        let minimized: Bool
        let activateOriginal: Bool
        let deadline: TimeInterval
    }

    private let service: WindowMinimizationService
    private let worker: AXWindowMinimizer
    private let invalidation = WindowBatchInvalidation()
    private var native: [NativeTarget] = []

    init(service: WindowMinimizationService) {
        self.service = service
        worker = AXWindowMinimizer(queue: service.queue)
    }

    func minimize(pid: Int32?, eligibleWindowIDs: Set<UInt32>?, cancellation: WindowVisibilityCancellation,
                  completion: @escaping @MainActor (WindowVisibilityResult) -> Void) -> Bool {
        guard service.acquire(cancellation) else { return false }
        let version = invalidation.version
        let deadline = ProcessInfo.processInfo.systemUptime + WindowMinimizationConfirmation.timeout
        let focused = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != ownPID
                && (pid == nil || $0.processIdentifier == pid)
        }.prefix(100).compactMap(WindowProcessIdentity.init(application:))
        let pivot = AXQuery.coordinatePivotY
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: pivot - $0.frame.maxY,
                   width: $0.frame.width, height: $0.frame.height)
        }
        let context = WindowMinimizationContext(applications: applications, screens: screens,
                                                focusedPID: focused, eligibleWindowIDs: eligibleWindowIDs,
                                                deadline: deadline)
        let requests = pid == nil || pid == ownPID
            ? minimizeNative(focused: focused == ownPID, allowed: eligibleWindowIDs, token: cancellation) : []
        return run(token: cancellation, version: version,
                   nativeBatch: .init(requests: requests, minimized: true, activateOriginal: false,
                                      deadline: deadline),
                   completion: completion) { [worker] in
            worker.minimize(context: context, cancellation: cancellation)
        }
    }

    func restore(activateOriginal: Bool, cancellation: WindowVisibilityCancellation,
                 completion: @escaping @MainActor (WindowVisibilityResult) -> Void) -> Bool {
        guard service.acquire(cancellation) else { return false }
        let version = invalidation.version
        let deadline = ProcessInfo.processInfo.systemUptime + WindowMinimizationConfirmation.timeout
        let requests = restoreNative(token: cancellation)
        return run(token: cancellation, version: version,
                   nativeBatch: .init(
                       requests: requests,
                       minimized: false,
                       activateOriginal: activateOriginal,
                       deadline: deadline
                   ),
                   completion: completion) { [worker] in
            worker.restore(activateOriginal: activateOriginal, deadline: deadline, cancellation: cancellation)
        }
    }

    private func run(token: WindowVisibilityCancellation, version: UInt64,
                     nativeBatch: NativeBatch,
                     completion: @escaping @MainActor (WindowVisibilityResult) -> Void,
                     operation: @escaping @Sendable () -> WindowMinimizationOutcome) -> Bool {
        let worker = worker
        let invalidation = invalidation
        let service = service
        // AppKit animations settle while the AX worker handles other applications.
        // Both confirmations consume the same deadline instead of adding two waits.
        let nativeConfirmation = Task { @MainActor [weak self] in
            await self?.confirmNative(nativeBatch, token: token, version: version) ?? 0
        }
        service.queue.async { [weak self] in
            let result = operation()
            if version != invalidation.version {
                worker.discard()
            }
            Task { @MainActor [weak self] in
                let finish: (WindowVisibilityResult) -> Void = {
                    service.finish(token)
                    completion($0)
                }
                guard let self else { finish(.init(ownedCount: 0, failures: result.failures)); return }
                guard version == invalidation.version else {
                    finish(.init(ownedCount: 0, failures: 0))
                    return
                }
                let ownFailures = await nativeConfirmation.value
                guard version == invalidation.version else {
                    finish(.init(ownedCount: 0, failures: 0))
                    return
                }
                if !token.isCancelled, let focus = result.focus, focus.isCurrent() {
                    NSRunningApplication(processIdentifier: focus.pid)?.activate(options: [])
                }
                finish(.init(ownedCount: result.ownedCount + native.count,
                             failures: result.failures + ownFailures))
            }
        }
        return true
    }

    private func minimizeNative(focused: Bool, allowed: Set<UInt32>?,
                                token: WindowVisibilityCancellation) -> [NativeTarget] {
        native.removeAll { target in
            target.window == nil || target.window?.windowNumber != target.number
        }
        var requests: [NativeTarget] = []
        for window in (NSApp?.windows ?? []).prefix(100) {
            guard !token.isCancelled else { break }
            guard window.windowNumber > 0, allowed?.contains(UInt32(window.windowNumber)) ?? true,
                  window.isVisible, window.isOnActiveSpace, !window.isMiniaturized,
                  window.styleMask.contains(.miniaturizable), !window.styleMask.contains(.fullScreen),
                  window.level == .normal, window.sheetParent == nil else { continue }
            native.removeAll { $0.window === window }
            let target = NativeTarget(window, focused: focused && window.isKeyWindow)
            window.miniaturize(nil)
            requests.append(target)
        }
        return requests
    }

    private func restoreNative(token: WindowVisibilityCancellation) -> [NativeTarget] {
        native.removeAll { target in
            guard let window = target.window else { return true }
            return window.windowNumber != target.number || !window.isMiniaturized
                || NSApp?.windows.contains(where: { $0 === window }) != true
                || window.styleMask.contains(.fullScreen)
        }
        var requests: [NativeTarget] = []
        for target in native.reversed() {
            guard !token.isCancelled else { break }
            guard let window = target.window else { continue }
            window.deminiaturize(nil)
            requests.append(target)
        }
        return requests
    }

    private func confirmNative(_ batch: NativeBatch,
                               token: WindowVisibilityCancellation, version: UInt64) async -> Int {
        let reads: [() -> Bool?] = batch.requests.map { target in
            {
                guard let window = target.window, window.windowNumber == target.number,
                      NSApp?.windows.contains(where: { $0 === window }) == true else { return nil }
                return window.isMiniaturized
            }
        }
        let result = await WindowMinimizationConfirmation.native(
            expected: batch.minimized, reads: reads,
            isCurrent: { self.invalidation.version == version }, deadline: .init(time: batch.deadline)
        )
        guard invalidation.version == version else { return 0 }
        let confirmed = result.confirmed.map { batch.requests[$0] }
        if batch.minimized {
            native.append(contentsOf: confirmed)
        } else {
            native.removeAll { target in
                target.window == nil || confirmed.contains(where: { $0 === target })
            }
        }
        if batch.activateOriginal, !token.isCancelled,
           let focused = confirmed.first(where: \.wasFocused)?.window {
            NSApp.activate()
            focused.makeKeyAndOrderFront(nil)
        }
        return result.pending.count
    }

    func discard() {
        native.removeAll()
        guard invalidation.requestCleanup() else { return }
        let worker = worker
        let invalidation = invalidation
        service.queue.async {
            worker.discard()
            invalidation.finishedCleanup()
        }
    }

    deinit {
        let worker = worker
        service.queue.async { worker.discard() }
    }
}

/// Only this version/cancellation bookkeeping crosses queues, under one lock.
private final class WindowBatchInvalidation: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var cleanupQueued = false
    var version: UInt64 {
        lock.withLock { revision }
    }

    func requestCleanup() -> Bool {
        lock.withLock {
            revision &+= 1
            guard !cleanupQueued else { return false }
            cleanupQueued = true
            return true
        }
    }

    func finishedCleanup() {
        lock.withLock { cleanupQueued = false }
    }
}
