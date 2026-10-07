import BlinkerHelperXPC
import Foundation
import OSLog

/// Privileged daemon backing the low-power-mode quick action. launchd runs
/// this binary as root; it listens on a Mach service named after its own
/// launchd label and executes exactly one allowlisted command family
/// (LowPowerCommand). Everything else is rejected before any process
/// launches. Every lifecycle event is logged to the unified log —
/// `log show --predicate 'subsystem == "Blinker.LowPowerHelper"'` — because
/// a launchd daemon has no console of its own.
let log = OSLog(subsystem: "Blinker.LowPowerHelper", category: "daemon")

/// XPC service object. One per connection; stateless by design.
final class LowPowerHelperService: NSObject, LowPowerHelperXPC {
    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (NSNumber) -> Void) {
        let executable = LowPowerCommand.executable
        let arguments = LowPowerCommand.arguments(enabled: enabled)
        // Re-validate even though the arguments were just constructed here:
        // the allowlist check is the daemon's contract, not a courtesy.
        guard LowPowerCommand.isAllowed(executable: executable, arguments: arguments) else {
            os_log(.error, log: log, "rejected command that failed allowlist re-validation")
            reply(NSNumber(value: LowPowerHelperRejection.rejectedCommand.rawValue))
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            os_log(.error, log: log, "failed to launch pmset: %{public}@",
                   error.localizedDescription)
            reply(NSNumber(value: LowPowerHelperRejection.launchFailed.rawValue))
            return
        }
        process.waitUntilExit()
        os_log(.info, log: log, "set low power mode %{public}@ -> pmset exit %d",
               enabled ? "on" : "off", process.terminationStatus)
        reply(NSNumber(value: process.terminationStatus))
    }
}

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: LowPowerHelperXPC.self)
        connection.exportedObject = LowPowerHelperService()
        connection.resume()
        return true
    }
}

let executablePath = LowPowerHelperLaunch.executablePath()
guard let serviceName = LowPowerHelperLaunch.serviceNameFromSiblingPlist(
    executablePath: executablePath
) else {
    os_log(.fault, log: log,
           "no sibling launchd plist next to %{public}@; exiting",
           executablePath)
    FileHandle.standardError.write(Data("low-power helper: sibling launchd plist not found\n".utf8))
    exit(1)
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
os_log(.info, log: log, "listening on %{public}@", serviceName)
RunLoop.main.run()
