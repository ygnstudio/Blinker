import AppKit
import Combine

/// Optional Dock click behavior. Disabling observation preserves explicit
/// restore eligibility; stop() discards it without changing any user window.
@MainActor
public final class DockClickController: ObservableObject {
    @Published public private(set) var isAvailable = false
    public var onWillToggle: (() -> Void)?
    private var isEnabled = false
    private let actions = DockClickActionRouter()
    private var pendingActivation: DockClickCandidate?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screensObserver: NSObjectProtocol?
    private lazy var observer = DockClickEventObserver { [weak self] candidate in
        // The tap is listen-only. Wait until normal Dock dispatch can activate
        // the app, then validate the current frontmost identity once more.
        DispatchQueue.main.async { [weak self] in self?.handle(candidate) }
    }

    public init() {
        actions.onWillToggle = { [weak self] in self?.onWillToggle?() }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFrontmost() }
        })
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreens() }
        }
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated { self?.applicationTerminated(app) }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.dock" else { return }
            MainActor.assumeIsolated {
                guard let self, self.isEnabled else { return }
                self.configure(isEnabled: true)
            }
        })
    }

    /// No permission prompt is issued. Calling true again also retries a failed tap.
    public func configure(isEnabled: Bool) {
        self.isEnabled = isEnabled
        observer.stop()
        pendingActivation = nil
        isAvailable = false
        guard isEnabled, AccessibilityPermission.isTrusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
              .first
        else { actions.setPaused(true); return }
        refreshFrontmost()
        refreshScreens()
        isAvailable = observer.start(dockPID: dock.processIdentifier,
                                     maximumPressDuration: max(0.3, NSEvent.doubleClickInterval))
        actions.setPaused(!isAvailable)
    }

    public func stop() {
        isEnabled = false
        isAvailable = false
        observer.stop()
        pendingActivation = nil
        actions.stop()
    }

    private func refreshFrontmost() {
        observer.setFrontmostPID(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        if let pending = pendingActivation {
            pendingActivation = nil
            handle(pending, waitForActivation: false)
        }
    }

    private func refreshScreens() {
        let screens = NSScreen.screens.map(\.frame)
        observer.setCandidateRegions(DockClickScreenRegions.make(
            screens: screens, coordinatePivotY: screens.first?.maxY ?? 0
        ))
    }

    private func handle(_ candidate: DockClickCandidate, waitForActivation: Bool = true) {
        guard isEnabled, isAvailable, observer.isCurrent(candidate.ticket), AccessibilityPermission.isTrusted,
              candidate.isFresh(at: ProcessInfo.processInfo.systemUptime),
              NSEvent.pressedMouseButtons == 0,
              let application = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleURL?.standardizedFileURL == candidate.applicationURL
              }), !application.isTerminated, application.activationPolicy == .regular,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let allowed = !SessionPause.shared.contains(application.bundleIdentifier ?? "")
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if waitForActivation, allowed, currentPID != application.processIdentifier,
           actions.hasOwnedWindows(pid: application.processIdentifier) {
            pendingActivation = candidate
            return
        }
        actions.route(pid: application.processIdentifier, frontmostPIDAtDown: candidate.frontmostPIDAtDown,
                      currentPID: currentPID, eligibleWindowIDs: candidate.eligibleWindowIDs,
                      isAllowed: allowed)
    }

    private func applicationTerminated(_ app: NSRunningApplication) {
        actions.discard(pid: app.processIdentifier)
        if app.bundleIdentifier == "com.apple.dock" {
            observer.stop()
            isAvailable = false
            actions.setPaused(true)
        }
    }

    deinit {
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        if let screensObserver {
            NotificationCenter.default.removeObserver(screensObserver)
        }
    }
}
