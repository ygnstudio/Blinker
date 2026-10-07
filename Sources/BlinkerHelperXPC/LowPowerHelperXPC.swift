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

/// Negative reply codes the helper returns before pmset is even launched.
public enum LowPowerHelperRejection: Int {
    /// The command about to run failed the whitelist re-validation.
    case rejectedCommand = -1
    /// pmset could not be launched at all.
    case launchFailed = -2
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
