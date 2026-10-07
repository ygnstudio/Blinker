import BlinkerHelperXPC
import Foundation
import ServiceManagement

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
/// macOS asks the user to approve once under Login Items. Every system
/// boundary is injectable so the state machine is testable end to end.
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
    private let callHelper: (Bool, @escaping (Int) -> Void) -> Void
    private let openLoginItemsSettings: () -> Void

    init(appBundleID: String = Bundle.main.bundleIdentifier ?? "",
         readSystemOutput: (() throws -> String)? = nil,
         registerDaemon: (() -> DaemonStatus)? = nil,
         callHelper: ((Bool, @escaping (Int) -> Void) -> Void)? = nil,
         openLoginItemsSettings: (() -> Void)? = nil) {
        self.appBundleID = appBundleID
        self.readSystemOutput = readSystemOutput ?? LowPowerController.readPMSetG
        self.registerDaemon = registerDaemon ?? {
            LowPowerController.registerDaemon(
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
        switch registerDaemon() {
        case .requiresApproval:
            issue = .approvalRequired
            openLoginItemsSettings()
            refresh()
            return
        case .unavailable:
            issue = .helperUnavailable
            refresh()
            return
        case .enabled:
            break
        }
        isApplying = true
        callHelper(enabled) { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
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

    /// One connection per write, invalidated after the reply: the daemon is
    /// on-demand under launchd, so holding a connection open would keep it
    /// resident for no benefit.
    static func callHelper(machServiceName: String, enabled: Bool,
                           reply: @escaping (Int) -> Void) {
        let connection = NSXPCConnection(machServiceName: machServiceName,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: LowPowerHelperXPC.self)
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            reply(LowPowerHelperRejection.launchFailed.rawValue)
            connection.invalidate()
        } as? LowPowerHelperXPC
        guard let proxy else {
            reply(LowPowerHelperRejection.launchFailed.rawValue)
            connection.invalidate()
            return
        }
        proxy.setLowPowerMode(enabled) { status in
            reply(status.intValue)
            connection.invalidate()
        }
    }
}
