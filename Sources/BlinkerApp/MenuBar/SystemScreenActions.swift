import AppKit

/// Launch Services starts the screen saver; pmset sleeps displays. Locking is
/// an isolated private capability until a public equivalent is available.
enum SystemScreenActions {
    static let screenSaverAppURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"
    )

    static var isScreenSaverAvailable: Bool {
        FileManager.default.fileExists(atPath: screenSaverAppURL.path)
    }

    static var isLockScreenAvailable: Bool {
        lockScreen != nil
    }

    /// Launch Services returns completion/error without spawning an `open` process.
    @MainActor
    static func startScreenSaver(
        open: (URL) async throws -> Void = { url in
            let configuration = NSWorkspace.OpenConfiguration()
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    ) async throws {
        try await open(screenSaverAppURL)
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
