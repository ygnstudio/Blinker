import AppKit
import Combine

/// Sensor inspection, gesture timing and capture share a single lifecycle owner.
@MainActor
final class ScreenEffectController: ObservableObject {
    let sensor: LidAngleMonitor
    let preferences: LidEffectPreferences
    @Published private(set) var progress = 0.0
    @Published private(set) var isPaused = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionGranted = false
    @Published private(set) var isPresenting = false
    @Published private(set) var isSuspended = false
    @Published private(set) var reducesMotion = false
    private let overlay: any LidEffectPresenting
    private let permissionCheck: () -> Bool
    private var subscriptions = Set<AnyCancellable>()
    private var suspensionReasons = Set<String>()
    private var inspecting = false
    private var running = false
    private var ticker: Timer?
    private var gesture = LidEffectGesture()
    private var lastReadingSequence: UInt64?
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?

    convenience init() {
        self.init(sensor: LidAngleMonitor(), preferences: .shared, overlay: LidEffectOverlay(),
                  permissionCheck: { CGPreflightScreenCaptureAccess() })
    }

    init(sensor: LidAngleMonitor, preferences: LidEffectPreferences,
         overlay: any LidEffectPresenting, permissionCheck: @escaping () -> Bool) {
        self.sensor = sensor
        self.preferences = preferences
        self.overlay = overlay
        self.permissionCheck = permissionCheck
        overlay.onFailure = { [weak self] message in
            self?.errorMessage = message
            self?.pause()
        }
        overlay.onFirstFrame = { [weak self] in self?.isPresenting = true }
        overlay.onFinished = { [weak self] in
            self?.isPresenting = false
            self?.removeEscapeMonitors()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if Self.sessionIsLocked {
            suspensionReasons.insert("lock")
        }
        isSuspended = !suspensionReasons.isEmpty
        preferences.$configuration.sink { [weak self] configuration in
            self?.configurationChanged(configuration)
        }.store(in: &subscriptions)
        observeLifecycle()
    }

    func stop() {
        running = false
        clearPresentation()
        ticker?.invalidate()
        ticker = nil
        sensor.stop()
        subscriptions.removeAll()
        suspensionReasons.removeAll()
        inspecting = false
    }

    func setInspecting(_ value: Bool) {
        inspecting = value
        refreshPermission()
        reconcile(configuration: preferences.configuration)
    }

    func refreshPermission() {
        let granted = permissionCheck()
        let changed = permissionGranted != granted
        if changed {
            permissionGranted = granted
        }
        if !granted {
            clearPresentation()
        }
        if changed {
            reconcile(configuration: preferences.configuration)
        }
    }

    func calibrate() {
        guard let angle = sensor.angle, (20 ... 180).contains(angle) else { return }
        preferences.update { $0.referenceAngle = angle }
    }

    func pause() {
        isPaused = true
        clearPresentation()
        reconcile(configuration: preferences.configuration)
    }

    func resume() {
        isPaused = false
        errorMessage = nil
        gesture.reset()
        refreshPermission()
        reconcile(configuration: preferences.configuration)
        sensor.refresh()
    }

    private func configurationChanged(_ configuration: LidEffectConfiguration) {
        gesture.reset()
        clearPresentation()
        if !configuration.isEnabled {
            isPaused = false
            errorMessage = nil
        }
        refreshPermission()
        reconcile(configuration: configuration)
    }

    private func reconcile(configuration: LidEffectConfiguration) {
        guard running else { return }
        let enabled = configuration.isEnabled && !isPaused && !isSuspended && !reducesMotion
        if !isSuspended, inspecting || (enabled && permissionGranted) {
            sensor.start()
        } else {
            sensor.stop()
        }
        if enabled, permissionGranted {
            if ticker == nil {
                let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.tick(time: ProcessInfo.processInfo.systemUptime) }
                }
                timer.tolerance = 0.01
                ticker = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            ticker?.invalidate()
            ticker = nil
            clearPresentation()
        }
    }

    /// Kept independent from the timer so invalid readings and timing can be exercised deterministically.
    func tick(time: TimeInterval) {
        guard running, preferences.configuration.isEnabled, !isPaused, !isSuspended, !reducesMotion,
              permissionGranted else { clearPresentation(); return }
        guard time.isFinite, let angle = sensor.angle, angle.isFinite, (0 ... 360).contains(angle) else {
            clearPresentation()
            return
        }
        let isFreshReading = lastReadingSequence != sensor.readingSequence
        lastReadingSequence = sensor.readingSequence
        let next = gesture.update(angle: angle, time: time, configuration: preferences.configuration,
                                  isFreshReading: isFreshReading)
        if next != progress {
            progress = next
        }
        if next > 0 || gesture.openingStartProgress != nil {
            overlay.update(progress: next, configuration: preferences.configuration,
                           openingStartProgress: gesture.openingStartProgress)
            installEscapeMonitors()
        } else {
            overlay.finish()
        }
    }

    private func clearPresentation() {
        overlay.clear()
        if progress != 0 {
            progress = 0
        }
        if isPresenting {
            isPresenting = false
        }
        gesture.reset()
        lastReadingSequence = nil
        removeEscapeMonitors()
    }

    private func removeEscapeMonitors() {
        for monitor in [escapeMonitor, localEscapeMonitor]
            .compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitor = nil
        localEscapeMonitor = nil
    }

    private func installEscapeMonitors() {
        guard localEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.pause()
            }
            return event
        }
        // A convenience only: the system menu remains usable even without AX key monitoring access.
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.pause()
            }
        }
    }

    private func setSuspended(_ value: Bool, reason: String) {
        if value {
            suspensionReasons.insert(reason)
        } else {
            suspensionReasons.remove(reason)
        }
        isSuspended = !suspensionReasons.isEmpty
        clearPresentation()
        refreshPermission()
        reconcile(configuration: preferences.configuration)
    }

    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        let pauses: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "system"),
            (NSWorkspace.screensDidSleepNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, "session"),
        ]
        let resumes: [(Notification.Name, String)] = [
            (NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session"),
        ]
        for (name, reason) in pauses {
            observe(workspace, name) { $0.setSuspended(true, reason: reason) }
        }
        for (name, reason) in resumes {
            observe(workspace, name) { $0.setSuspended(false, reason: reason) }
        }
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsLocked")) {
            $0.setSuspended(true, reason: "lock")
        }
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked")) {
            $0.setSuspended(false, reason: "lock")
        }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            $0.reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            $0.clearPresentation()
            $0.reconcile(configuration: $0.preferences.configuration)
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.clearPresentation() }
        observe(.default, .NSProcessInfoPowerStateDidChange) { $0.clearPresentation() }
        observe(.default, NSApplication.didBecomeActiveNotification) {
            $0.refreshPermission()
            $0.reconcile(configuration: $0.preferences.configuration)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (ScreenEffectController) -> Void) {
        center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
            if let self {
                action(self)
            }
        }.store(in: &subscriptions)
    }

    private static var sessionIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
            || session[kCGSessionOnConsoleKey as String] as? Bool == false
    }
}
