import BlinkerHelperXPC
import Foundation

/// Privileged daemon backing the low-power-mode quick action. launchd runs
/// this binary as root; it listens on a Mach service named after its own
/// launchd label and executes exactly one whitelisted command family
/// (LowPowerCommand). Everything else is rejected before any process
/// launches.

/// XPC service object. One per connection; stateless by design.
final class LowPowerHelperService: NSObject, LowPowerHelperXPC {
    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (NSNumber) -> Void) {
        let executable = LowPowerCommand.executable
        let arguments = LowPowerCommand.arguments(enabled: enabled)
        // Re-validate even though the arguments were just constructed here:
        // the whitelist check is the daemon's contract, not a courtesy.
        guard LowPowerCommand.isAllowed(executable: executable, arguments: arguments) else {
            reply(NSNumber(value: LowPowerHelperRejection.rejectedCommand.rawValue))
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            reply(NSNumber(value: LowPowerHelperRejection.launchFailed.rawValue))
            return
        }
        process.waitUntilExit()
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

/// The daemon learns its own Mach service name from the launchd property
/// list the packaging script places next to the binary:
/// Contents/Library/LaunchDaemons/<label> and <label>.plist. Reading the
/// sibling plist keeps one binary valid for any app identity (development
/// and release bundle identifiers produce different labels).
func serviceNameFromSiblingPlist(
    executablePath: String = CommandLine.arguments[0],
    loadPlist: (URL) -> NSDictionary? = { NSDictionary(contentsOf: $0) }
) -> String? {
    let executableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
    guard let plist = loadPlist(executableURL.appendingPathExtension("plist")),
          let label = plist["Label"] as? String,
          !label.isEmpty else { return nil }
    return label
}

guard let serviceName = serviceNameFromSiblingPlist() else {
    FileHandle.standardError.write(Data("low-power helper: sibling launchd plist not found\n".utf8))
    exit(1)
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
