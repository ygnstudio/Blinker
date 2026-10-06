import AppKit
import Foundation

/// Dark-mode switch for the quick actions block. Reading needs no grant:
/// the global domain carries `AppleInterfaceStyle` = "Dark" and stays
/// absent in Light mode. Writing goes through the System Events appearance
/// suite — the documented channel — which asks for Automation consent once,
/// targeting System Events rather than the Finder.
enum SystemAppearanceToggle {
    /// true when the system appearance is Dark; an absent key means Light.
    static let isDarkMode: () -> Bool = {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// An explicit set rather than a toggle, so retries stay idempotent.
    static func script(darkMode: Bool) -> String {
        "tell application \"System Events\" to tell appearance preferences "
            + "to set dark mode to \(darkMode)"
    }

    enum Failure: Equatable, Sendable {
        /// errAEEventNotPermitted — the user declined (or has not yet been
        /// asked) the System Events Automation consent.
        case automationDenied
        /// The script ran but System Events reported an error; the
        /// system-localized message is shown as is.
        case failed(String)
    }

    /// Maps `executeAndReturnError` output. A nil dictionary means success;
    /// callers pass it through only when the execution failed.
    static func failure(from errorInfo: [AnyHashable: Any]?) -> Failure? {
        guard let errorInfo else { return nil }
        if (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
            return .automationDenied
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String
        return .failed(message ?? String(localized: "切换深色模式失败"))
    }
}

/// Panel-side state for the dark-mode row. The script runs detached so a
/// pending consent prompt never stalls the panel; on failure the switch
/// reverts to the system's real mode. External changes (Control Center,
/// auto appearance schedules) sync in through the theme-changed
/// notification while the panel lives.
@MainActor
final class AppearanceToggleController: ObservableObject {
    @Published private(set) var isDarkMode: Bool
    @Published private(set) var isApplying = false
    @Published private(set) var failure: SystemAppearanceToggle.Failure?

    private let readDarkMode: () -> Bool
    private let runScript: (String) -> [AnyHashable: Any]?
    /// Optional so the registration closure may capture self during init.
    private var themeObserver: NSObjectProtocol?

    init(readDarkMode: @escaping () -> Bool = SystemAppearanceToggle.isDarkMode,
         runScript: @escaping (String) -> [AnyHashable: Any]? = AppearanceToggleController.execute) {
        self.readDarkMode = readDarkMode
        self.runScript = runScript
        isDarkMode = readDarkMode()
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
    }

    /// Re-reads the preference domain; called on panel appear and whenever
    /// the system theme changes outside Blinker.
    func refresh() {
        isDarkMode = readDarkMode()
    }

    /// Optimistic flip: the switch follows at once, a failure reverts it
    /// through `refresh`. Re-entrancy is dropped while a script is in
    /// flight so a slow consent prompt cannot stack writes.
    func setDarkMode(_ darkMode: Bool) {
        guard !isApplying else { return }
        failure = nil
        isDarkMode = darkMode
        isApplying = true
        let script = SystemAppearanceToggle.script(darkMode: darkMode)
        let run = runScript
        Task.detached {
            let outcome = SystemAppearanceToggle.failure(from: run(script))
            await MainActor.run { [weak self] in
                guard let self else { return }
                isApplying = false
                if let outcome {
                    failure = outcome
                    refresh()
                }
            }
        }
    }

    /// The default script channel. `nonisolated` so the detached task never
    /// hops back to the main actor for the blocking call itself.
    nonisolated static func execute(_ source: String) -> [AnyHashable: Any]? {
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        return errorInfo as? [AnyHashable: Any]
    }
}
