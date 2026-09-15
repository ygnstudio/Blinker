import CoreGraphics
import Foundation
import os

/// Hosts a `CGEventTap` on a dedicated thread with a synchronized, ordered
/// teardown. Shared by every long-lived tap (interceptor, hover detection,
/// snapper) so all of them get the same lifecycle guarantees:
///
/// - `start()` creates the tap synchronously on the calling thread, so
///   failures report immediately and never leak a spawned thread.
/// - `stop()` cancels the thread *before* stopping its run loop (otherwise
///   the thread re-enters `run(mode:before:)` and blocks forever on its wake
///   port), removes the source, invalidates the mach port, and waits for the
///   thread to exit. After `stop()` returns no callback can be running or
///   scheduled, so the tap's owner — whose raw pointer is the `userInfo` —
///   is safe to deallocate.
///
/// - Note: `start()` and `stop()` must be driven from a single thread.
///   They are not safe to call concurrently: the initial `tap != nil`
///   check in `start()` happens before `CGEvent.tapCreate`, so a `stop()`
///   racing inside that window could return before the tap is attached,
///   leaving the new tap running. All call sites (AppDelegate switches,
///   `deinit`-triggered teardown) run on the main thread — keep it that way.
final class EventTapThreadHost {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: DedicatedTapThread?
    private let threadName: String
    private let logger = Logger(subsystem: "com.ygnstudio.blinker", category: "tap-host")

    /// How long `stop()` waits for the tap thread to acknowledge exit before
    /// giving up (and logging). Defensive only: the thread cannot block once
    /// its run loop is stopped and it is cancelled.
    private static let stopTimeout: TimeInterval = 2

    init(threadName: String) {
        self.threadName = threadName
    }

    var isRunning: Bool {
        lock.withLock { tap != nil }
    }

    /// Creates the tap (synchronously) and hosts it on a new dedicated
    /// thread. Returns `false` when the system refuses the tap; nothing is
    /// leaked in that case.
    ///
    /// - Parameter userInfo: Raw pointer handed back to the callback on every
    ///   event. The owner behind it must outlive every callback; `stop()`
    ///   provides that guarantee by waiting for the thread to exit before
    ///   returning, so an owner that calls `stop()` from `deinit` is safe.
    @discardableResult
    func start(
        mask: CGEventMask,
        options: CGEventTapOptions,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> Bool {
        lock.lock()
        if tap != nil {
            lock.unlock()
            return true
        }
        lock.unlock()

        guard
            let newTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: options,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            )
        else {
            logger.error("CGEvent.tapCreate returned nil (\(self.threadName, privacy: .public))")
            return false
        }
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)

        // Installing on the tap thread must race safely against a stop() (or
        // a restart) that may already be in flight: attach the source only
        // while this tap is still the current one under the lock.
        let newThread = DedicatedTapThread(name: threadName) { [weak self] runLoop in
            guard let self else { return }
            let cfRunLoop = runLoop.getCFRunLoop()
            lock.lock()
            if tap === newTap {
                CFRunLoopAddSource(cfRunLoop, newSource, .commonModes)
                CGEvent.tapEnable(tap: newTap, enable: true)
                self.runLoop = cfRunLoop
            }
            lock.unlock()
        }

        lock.lock()
        tap = newTap
        source = newSource
        thread = newThread
        lock.unlock()
        newThread.start()
        return true
    }

    /// Tears the tap down completely. Idempotent and safe to call from
    /// `deinit` (it briefly blocks until the tap thread has exited).
    func stop() {
        lock.lock()
        guard let oldTap = tap else {
            lock.unlock()
            return
        }
        let oldSource = source
        let oldRunLoop = runLoop
        let oldThread = thread
        tap = nil
        source = nil
        runLoop = nil
        thread = nil
        lock.unlock()

        // Cancel before stopping the run loop: the thread's run loop wakes
        // from CFRunLoopStop, returns, and would otherwise re-enter
        // run(mode:before:.distantFuture) — blocking forever on its wake
        // port. With the cancel flag set, the loop exits instead.
        oldThread?.cancel()
        CGEvent.tapEnable(tap: oldTap, enable: false)
        if let oldSource, let oldRunLoop {
            CFRunLoopRemoveSource(oldRunLoop, oldSource, .commonModes)
        }
        if let oldRunLoop {
            CFRunLoopStop(oldRunLoop)
        }
        // Invalidate so no further callback can ever be scheduled on this
        // port, even if some queued event were still in flight.
        CFMachPortInvalidate(oldTap)

        // Wait for the thread to exit: only then is no callback running and
        // the owner (whose raw pointer is the tap's userInfo) safe to free.
        if let oldThread, oldThread.waitUntilExited(timeout: Self.stopTimeout) == .timedOut {
            logger.error("tap thread \(self.threadName, privacy: .public) did not exit in time")
        }
    }

    /// Re-enables the tap after the system disabled it (timeout / user
    /// input). No-op when the host is stopped.
    func enableTap() {
        let currentTap = lock.withLock { tap }
        if let currentTap {
            CGEvent.tapEnable(tap: currentTap, enable: true)
        }
    }

    deinit {
        stop()
    }
}

/// The dedicated thread a tap's run loop lives on. `waitUntilExited` blocks
/// until the thread's `main` has returned — exactly once — which lets
/// `stop()` guarantee no callback is still in flight.
final class DedicatedTapThread: Thread {
    private let configure: (RunLoop) -> Void
    private let didExit = DispatchSemaphore(value: 0)

    init(name: String, configure: @escaping (RunLoop) -> Void) {
        self.configure = configure
        super.init()
        self.name = name
    }

    override func main() {
        let runLoop = RunLoop.current
        // An empty wake port keeps the run loop from exiting immediately
        // when it has no other sources (or all of them were removed).
        runLoop.add(Port(), forMode: .default)
        if !isCancelled {
            configure(runLoop)
        }
        while !isCancelled {
            _ = runLoop.run(mode: .default, before: .distantFuture)
        }
        didExit.signal()
    }

    /// Blocks (up to `timeout` seconds) until the thread's main has returned.
    func waitUntilExited(timeout: TimeInterval) -> DispatchTimeoutResult {
        didExit.wait(timeout: .now() + timeout)
    }
}
