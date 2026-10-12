import Foundation

/// Contract between Blinker.app and its privileged low-power helper. The
/// daemon runs as root for exactly one reason: writing low power mode via
/// pmset requires it. Its entire command surface is the two argument
/// vectors in LowPowerCommand — nothing else is executable through this
/// channel.
@objc(BlinkerLowPowerHelperXPC)
public protocol LowPowerHelperXPC {
    /// Writes the system-wide low power mode. The reply is 0 on success, a
    /// positive pmset exit code when the write itself failed, or a negative
    /// helper-side rejection (see LowPowerHelperRejection).
    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (NSNumber) -> Void)
}

/// Negative results from the helper or the app's XPC transport.
/// connectionFailed and timedOut are synthesized on the app side: launchd keeps a broken
/// registration's Mach endpoint vended while it throttles respawns, so a
/// dead helper pends forever without a connection error — the watchdog is
/// the only guaranteed signal.
public enum LowPowerHelperRejection: Int {
    /// The command about to run failed the whitelist re-validation.
    case rejectedCommand = -1
    /// pmset could not be launched at all.
    case launchFailed = -2
    /// No reply and no connection error within the watchdog window.
    case timedOut = -3
    /// XPC could not reach the helper; distinct from a helper-reported pmset failure.
    case connectionFailed = -4
}

/// The helper's entire command surface: exactly two argument vectors of
/// /usr/bin/pmset. Both sides share this definition — the app so it knows
/// precisely what will run, the daemon so it can re-validate before every
/// exec and refuse everything else.
public enum LowPowerCommand {
    public static let executable = "/usr/bin/pmset"

    public static func arguments(enabled: Bool) -> [String] {
        ["-a", "lowpowermode", enabled ? "1" : "0"]
    }

    /// Defense in depth on the daemon side: re-validate before every exec.
    public static func isAllowed(executable: String, arguments: [String]) -> Bool {
        executable == Self.executable
            && (arguments == Self.arguments(enabled: true)
                || arguments == Self.arguments(enabled: false))
    }
}

public enum LowPowerHelperNames {
    /// The daemon's launchd label and Mach service name derive from the
    /// app's bundle identifier, so development and release installs keep
    /// separate daemon registrations — mirroring how the packaging script
    /// isolates preferences and permission grants per identity.
    public static func machServiceName(appBundleID: String) -> String {
        "\(appBundleID).LowPowerHelper"
    }

    /// The property list the packaging script generates into
    /// Contents/Library/LaunchDaemons for SMAppService to register.
    public static func plistName(appBundleID: String) -> String {
        "\(machServiceName(appBundleID: appBundleID)).plist"
    }
}

/// How the daemon learns its own Mach service name. launchd starts the
/// daemon with argv[0] set to the BundleProgram string — a path RELATIVE
/// to the app bundle — while the daemon's working directory is `/`, so
/// resolving argv[0] yields /Contents/… and the sibling plist is never
/// found (the daemon exits before listening). `_NSGetExecutablePath`
/// returns the real absolute path regardless of argv[0].
public enum LowPowerHelperLaunch {
    /// Absolute path of the running helper binary; falls back to argv[0]
    /// only if the dyld query itself fails.
    public static func executablePath() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var size = UInt32(buffer.count)
        if _NSGetExecutablePath(&buffer, &size) == 0 {
            return String(cString: buffer)
        }
        return CommandLine.arguments[0]
    }

    /// Reads the launchd label from the property list placed next to the
    /// binary: Contents/Library/LaunchDaemons/<label> and <label>.plist.
    /// Keeping the name in the sibling plist lets one binary serve any app
    /// identity (development and release produce different labels).
    public static func serviceNameFromSiblingPlist(
        executablePath: String,
        loadPlist: (URL) -> NSDictionary? = { NSDictionary(contentsOf: $0) }
    ) -> String? {
        let executableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        guard let plist = loadPlist(executableURL.appendingPathExtension("plist")),
              let label = plist["Label"] as? String,
              !label.isEmpty else { return nil }
        return label
    }
}
