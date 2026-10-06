import Foundation

/// One-shot screen actions for the quick actions block: start the screen
/// saver, sleep the displays, lock the screen. The first two shell out to
/// system tools; locking resolves SACLockScreenImmediate from the private
/// login framework at runtime — the same dlopen bridge SkyLightSpaces
/// uses. When a macOS release drops the symbol, `isLockScreenAvailable`
/// reports false and the panel hides the row instead of offering a button
/// that does nothing. (Probed on macOS 26: ScreenSaverEngine.app lives
/// on, the CGSession menu-extra helper is gone, SACLockScreenImmediate
/// still resolves.)
enum SystemScreenActions {
    static let screenSaverAppURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")

    static var isScreenSaverAvailable: Bool {
        FileManager.default.fileExists(atPath: screenSaverAppURL.path)
    }

    static var isLockScreenAvailable: Bool {
        lockScreen != nil
    }

    /// Starts the screen saver for the current session. `open` returns as
    /// soon as the launch is handed off, so the panel never stalls.
    static func startScreenSaver(
        run: (String, [String]) throws -> Void = SystemFinderToggles.runCommand
    ) throws {
        try run("/usr/bin/open", [screenSaverAppURL.path])
    }

    /// Sleeps every display immediately; the Mac itself keeps running.
    static func sleepDisplays(
        run: (String, [String]) throws -> Void = SystemFinderToggles.runCommand
    ) throws {
        try run("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// Locks the screen, returning to the login window with the session
    /// intact. No-op when the symbol is unavailable.
    static func lockScreenNow() {
        lockScreen?()
    }

    private typealias LockScreen = @convention(c) () -> Void

    private static let lockScreen: LockScreen? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: LockScreen.self)
    }()
}
