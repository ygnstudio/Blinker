import Foundation

/// Finder-side switches for the quick actions block: desktop icons and
/// hidden files. State reads come from the com.apple.finder preference
/// domain; writes go through the defaults CLI and apply by restarting
/// Finder — the same sequence as typing the two commands in Terminal.
/// Finder relaunches instantly under launchd and keeps every window's
/// position, so the restart is cheap but not invisible: the desktop
/// briefly redraws.
enum SystemFinderToggles {
    static let finderDomain = "com.apple.finder"
    static let desktopIconsKey = "CreateDesktop"
    static let hiddenFilesKey = "AppleShowAllFiles"
    static let extensionsKey = "AppleShowAllExtensions"

    /// Desktop icons show unless the key exists and says otherwise; the
    /// factory default is the key's absence.
    static func desktopIconsShown(in store: UserDefaults) -> Bool {
        store.object(forKey: desktopIconsKey) == nil || store.bool(forKey: desktopIconsKey)
    }

    /// Hidden files stay hidden unless the key exists and says otherwise;
    /// an absent key reads as false, which is exactly the default.
    static func hiddenFilesShown(in store: UserDefaults) -> Bool {
        store.bool(forKey: hiddenFilesKey)
    }

    /// Extensions stay hidden unless the key exists and says otherwise,
    /// matching hiddenFilesShown semantics: absent key means false.
    static func extensionsShown(in store: UserDefaults) -> Bool {
        store.bool(forKey: extensionsKey)
    }

    /// Writes one Finder key and restarts Finder so the change applies at
    /// once. The restart only runs after a successful write: a failed
    /// write must not bounce the user's desktop for nothing.
    static func setKey(_ key: String, value: Bool,
                       run: (String, [String]) throws -> Void = runCommand) throws {
        try run("/usr/bin/defaults", ["write", finderDomain, key, "-bool", value ? "true" : "false"])
        try run("/usr/bin/killall", ["Finder"])
    }

    static func runCommand(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Blinker.FinderCommand", code: Int(process.terminationStatus))
        }
    }
}

/// Panel-facing state for the two Finder switches. Reads re-sync on every
/// panel open, so changes made in Terminal or by another app show up; a
/// failed write snaps the toggle back to the system's actual state and
/// raises the failure flag the row reports.
@MainActor
final class FinderTogglesController: ObservableObject {
    @Published private(set) var desktopIconsShown = true
    @Published private(set) var hiddenFilesShown = false
    @Published private(set) var extensionsShown = false
    @Published private(set) var lastWriteFailed = false
    @Published private(set) var isApplying = false

    private let store: UserDefaults
    private let apply: (String, Bool) throws -> Void

    init(store: UserDefaults? = UserDefaults(suiteName: SystemFinderToggles.finderDomain),
         apply: ((String, Bool) throws -> Void)? = nil) {
        self.store = store ?? .standard
        self.apply = apply ?? { key, value in
            try SystemFinderToggles.setKey(key, value: value)
        }
    }

    /// Re-reads the preference domain.
    func refresh() {
        guard !isApplying else { return }
        desktopIconsShown = SystemFinderToggles.desktopIconsShown(in: store)
        hiddenFilesShown = SystemFinderToggles.hiddenFilesShown(in: store)
        extensionsShown = SystemFinderToggles.extensionsShown(in: store)
    }

    func setDesktopIconsShown(_ shown: Bool) {
        applyValue(shown, for: SystemFinderToggles.desktopIconsKey)
    }

    func setHiddenFilesShown(_ shown: Bool) {
        applyValue(shown, for: SystemFinderToggles.hiddenFilesKey)
    }

    func setExtensionsShown(_ shown: Bool) {
        applyValue(shown, for: SystemFinderToggles.extensionsKey)
    }

    private func applyValue(_ value: Bool, for key: String) {
        guard !isApplying else { return }
        lastWriteFailed = false
        isApplying = true
        switch key {
        case SystemFinderToggles.desktopIconsKey: desktopIconsShown = value
        case SystemFinderToggles.hiddenFilesKey: hiddenFilesShown = value
        case SystemFinderToggles.extensionsKey: extensionsShown = value
        default: break
        }
        let apply = apply
        Task.detached(priority: .userInitiated) {
            let failed: Bool
            do {
                try apply(key, value)
                failed = false
            } catch {
                failed = true
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.lastWriteFailed = failed
                self.isApplying = false
                self.refresh()
            }
        }
    }
}
