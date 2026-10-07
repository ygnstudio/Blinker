import BlinkerHelperXPC
import Foundation
import OSLog
import ServiceManagement

private let lowPowerLog = OSLog(subsystem: "Blinker", category: "LowPower")

/// Parses `pmset -g`, which needs no privilege. The line we want sits among
/// the system-wide power settings as `lowpowermode        0`; `pmset -a`
/// writes every power-source section, so the first match is authoritative.
enum LowPowerStatusParser {
    static func parse(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("lowpowermode") else { continue }
            let value = trimmed.dropFirst("lowpowermode".count)
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("1") { return true }
            if value.hasPrefix("0") { return false }
        }
        return nil
    }
}

/// Panel-facing state for the low-power-mode switch. Reads are free
/// (`pmset -g`); writes go through the privileged helper daemon, which
/// macOS asks the user to approve once under Login Items. A write that
/// never reaches the daemon rebuilds the registration once before giving
/// up, since replacing the app in place strands launchd's bundle reference.
/// Every system boundary is injectable so the state machine is testable
/// end to end.
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

    private let appBundleID: String
    private let readSystemOutput: () throws -> String
    private let registerDaemon: () -> DaemonStatus
    private let unregisterDaemon: () -> Void
    private let callHelper: (Bool, @escaping (Int) -> Void) -> Void
    private let openLoginItemsSettings: () -> Void

    init(appBundleID: String = Bundle.main.bundleIdentifier ?? "",
         readSystemOutput: (() throws -> String)? = nil,
         registerDaemon: (() -> DaemonStatus)? = nil,
         unregisterDaemon: (() -> Void)? = nil,
         callHelper: ((Bool, @escaping (Int) -> Void) -> Void)? = nil,
         openLoginItemsSettings: (() -> Void)? = nil) {
        self.appBundleID = appBundleID
        self.readSystemOutput = readSystemOutput ?? LowPowerController.readPMSetG
        self.registerDaemon = registerDaemon ?? {
            LowPowerController.registerDaemon(
                plistName: LowPowerHelperNames.plistName(appBundleID: appBundleID)
            )
        }
        self.unregisterDaemon = unregisterDaemon ?? {
            LowPowerController.unregisterDaemon(
                plistName: LowPowerHelperNames.plistName(appBundleID: appBundleID)
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
    }

    /// Re-reads the system state. A silent failure keeps the last known
    /// value: the switch is a convenience, never a source of truth.
    func refresh() {
        guard let output = try? readSystemOutput(),
              let enabled = LowPowerStatusParser.parse(output) else { return }
        isOn = enabled
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
                let unreachable = status == LowPowerHelperRejection.launchFailed.rawValue
                    || status == LowPowerHelperRejection.timedOut.rawValue
                if unreachable && allowRepair {
                    os_log(.info, log: lowPowerLog,
                           "helper unreachable; rebuilding the daemon registration")
                    self.unregisterDaemon()
                    self.runWrite(enabled, allowRepair: false)
                    return
                }
                self.isApplying = false
                if status != 0 { self.issue = .writeFailed }
                // Whether the write landed or failed, the row mirrors the
                // system's actual state — never the intent.
                self.refresh()
            }
        }
    }

    // MARK: - System boundaries

    static func readPMSetG() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

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

    static func unregisterDaemon(plistName: String) {
        SMAppService.daemon(plistName: plistName).unregister { _ in }
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
            once.deliver(LowPowerHelperRejection.launchFailed.rawValue)
        } as? LowPowerHelperXPC
        guard let proxy else {
            once.deliver(LowPowerHelperRejection.launchFailed.rawValue)
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
