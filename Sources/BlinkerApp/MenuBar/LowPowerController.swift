import BlinkerHelperXPC
import Foundation
import OSLog
import ServiceManagement

private let lowPowerLog = OSLog(subsystem: "Blinker", category: "LowPower")

/// The app owns this state beyond the transient status panel. Reads use
/// the native ProcessInfo API, so opening the page never waits for pmset.
/// Privileged writes retain their approval and bounded recovery flow.
@MainActor
final class LowPowerController: ObservableObject {
    enum HelperIssue: Equatable {
        /// SMAppService reports .requiresApproval: the user must allow the
        /// background item in System Settings → Login Items. The settings
        /// pane is opened automatically when this surfaces.
        case approvalRequired
        /// The daemon property list is not inside this bundle — the app is
        /// running unpackaged (swift run) or the helper failed to register.
        case helperUnavailable
        /// The XPC write or pmset itself failed.
        case writeFailed
    }

    enum DaemonStatus: Equatable {
        case enabled
        case requiresApproval
        case unavailable
    }

    @Published private(set) var isOn = false
    @Published private(set) var issue: HelperIssue?
    @Published private(set) var isApplying = false

    private var powerStateObserver: NSObjectProtocol?
    private let appBundleID: String
    private let readSystemState: () -> Bool
    private let registerDaemon: () -> DaemonStatus
    private let unregisterDaemon: (@escaping (Error?) -> Void) -> Void
    private let callHelper: (Bool, @escaping (Int) -> Void) -> Void
    private let openLoginItemsSettings: () -> Void

    init(appBundleID: String = Bundle.main.bundleIdentifier ?? "",
         readSystemState: (() -> Bool)? = nil,
         registerDaemon: (() -> DaemonStatus)? = nil,
         unregisterDaemon: ((@escaping (Error?) -> Void) -> Void)? = nil,
         callHelper: ((Bool, @escaping (Int) -> Void) -> Void)? = nil,
         openLoginItemsSettings: (() -> Void)? = nil) {
        self.appBundleID = appBundleID
        self.readSystemState = readSystemState ?? { ProcessInfo.processInfo.isLowPowerModeEnabled }
        self.registerDaemon = registerDaemon ?? {
            LowPowerController.registerDaemon(
                plistName: LowPowerHelperNames.plistName(appBundleID: appBundleID)
            )
        }
        self.unregisterDaemon = unregisterDaemon ?? { completion in
            LowPowerController.unregisterDaemon(
                plistName: LowPowerHelperNames.plistName(appBundleID: appBundleID),
                completion: completion
            )
        }
        self.callHelper = callHelper ?? { enabled, reply in
            LowPowerController.callHelper(
                machServiceName: LowPowerHelperNames.machServiceName(appBundleID: appBundleID),
                enabled: enabled, reply: reply
            )
        }
        self.openLoginItemsSettings = openLoginItemsSettings ?? {
            SMAppService.openSystemSettingsLoginItems()
        }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
    }

    /// Reads the effective system state without launching a subprocess.
    func refresh() {
        isOn = readSystemState()
    }

    func setLowPowerMode(_ enabled: Bool) {
        guard !isApplying else { return }
        issue = nil
        isApplying = true
        runWrite(enabled, allowRepair: true)
    }

    /// One register → write attempt. When the helper never answers
    /// (launchd lost the bundle reference after an in-place app swap, so
    /// the spawn fails before any listener exists), the registration is
    /// rebuilt once and the attempt repeated once; approval and
    /// availability are re-evaluated on that second pass.
    private func runWrite(_ enabled: Bool, allowRepair: Bool) {
        let daemon = registerDaemon()
        os_log(.info, log: lowPowerLog, "low power write %{public}@: daemon status %{public}@",
               enabled ? "on" : "off", String(describing: daemon))
        switch daemon {
        case .requiresApproval:
            isApplying = false
            issue = .approvalRequired
            openLoginItemsSettings()
            refresh()
            return
        case .unavailable:
            isApplying = false
            issue = .helperUnavailable
            refresh()
            return
        case .enabled:
            break
        }
        callHelper(enabled) { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                os_log(.info, log: lowPowerLog, "low power helper replied %d", status)
                let unreachable = status == LowPowerHelperRejection.connectionFailed.rawValue
                    || status == LowPowerHelperRejection.timedOut.rawValue
                if unreachable, allowRepair {
                    os_log(.info, log: lowPowerLog,
                           "helper unreachable; rebuilding the daemon registration")
                    self.repairRegistrationThenWrite(enabled)
                    return
                }
                self.isApplying = false
                if status != 0 {
                    self.issue = .writeFailed
                }
                // Whether the write landed or failed, the row mirrors the
                // system's actual state — never the intent.
                self.refresh()
            }
        }
    }

    /// SMAppService only guarantees that re-registration is safe after
    /// the asynchronous unregister completion. Keep the switch busy until
    /// that result arrives, and never retry after failed cleanup.
    private func repairRegistrationThenWrite(_ enabled: Bool) {
        unregisterDaemon { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil else {
                    os_log(.error, log: lowPowerLog, "daemon unregistration failed: %{public}@",
                           String(describing: error))
                    self.isApplying = false
                    self.issue = .writeFailed
                    self.refresh()
                    return
                }
                self.runWrite(enabled, allowRepair: false)
            }
        }
    }

    // MARK: - System boundaries

    static func registerDaemon(plistName: String) -> DaemonStatus {
        let service = SMAppService.daemon(plistName: plistName)
        try? service.register()
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        default:
            return .unavailable
        }
    }

    static func unregisterDaemon(plistName: String, completion: @escaping (Error?) -> Void) {
        SMAppService.daemon(plistName: plistName).unregister(completionHandler: completion)
    }

    /// One connection per write, invalidated after the reply: the daemon is
    /// on-demand under launchd, so holding a connection open would keep it
    /// resident for no benefit. The reply fires exactly once, whichever
    /// comes first: the helper's answer, a connection error, or the
    /// watchdog — a dead registration pends without an error, so the
    /// watchdog is what guarantees the switch always settles.
    static func callHelper(machServiceName: String, enabled: Bool,
                           timeout: TimeInterval = 8,
                           reply: @escaping (Int) -> Void) {
        let connection = NSXPCConnection(machServiceName: machServiceName,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: LowPowerHelperXPC.self)
        connection.resume()
        let once = ReplyOnce { status in
            reply(status)
            connection.invalidate()
        }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            once.deliver(LowPowerHelperRejection.connectionFailed.rawValue)
        } as? LowPowerHelperXPC
        guard let proxy else {
            once.deliver(LowPowerHelperRejection.connectionFailed.rawValue)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            once.deliver(LowPowerHelperRejection.timedOut.rawValue)
        }
        proxy.setLowPowerMode(enabled) { status in
            once.deliver(status.intValue)
        }
    }
}

/// Serializes the three racing reply sources (helper answer, connection
/// error, watchdog) so the caller's continuation runs exactly once.
private final class ReplyOnce {
    private let lock = NSLock()
    private var delivered = false
    private let action: (Int) -> Void

    init(action: @escaping (Int) -> Void) {
        self.action = action
    }

    func deliver(_ status: Int) {
        lock.lock()
        guard !delivered else {
            lock.unlock()
            return
        }
        delivered = true
        lock.unlock()
        action(status)
    }
}
