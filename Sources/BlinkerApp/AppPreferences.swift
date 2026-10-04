import SwiftUI

/// User-facing interface appearance, persisted across launches.
enum AppAppearance: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var menuLabel: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .light: String(localized: "浅色")
        case .dark: String(localized: "深色")
        }
    }

    /// Scheme to hand to `preferredColorScheme`; `nil` follows the system.
    var resolvedScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// `NSAppearance` for the hand-built settings window's chrome; `nil`
    /// follows the system. Applying it on the NSWindow keeps the titlebar
    /// in sync with the content's `preferredColorScheme` instantly.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Appearance and feature preferences shared by every window.
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    /// Completing or dismissing the guide suppresses automatic presentation on later launches.
    @Published var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding") }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appAppearance") }
    }

    @Published var language: AppLanguage {
        didSet { language.persist(in: defaults) }
    }

    var languageNeedsRestart: Bool {
        language != languageAtLaunch
    }

    /// Optional Windows-like Dock behavior; existing installations keep native clicks until enabled.
    @Published var isDockClickMinimizeEnabled: Bool {
        didSet { defaults.set(isDockClickMinimizeEnabled, forKey: "dockClickMinimizeEnabled") }
    }

    /// Whether dragging windows to screen edges/corners snaps them.
    @Published var isSnapEnabled: Bool {
        didSet { defaults.set(isSnapEnabled, forKey: "isSnapEnabled") }
    }

    /// Whether workspace restore also moves windows back to the desktop
    /// (Space) they were captured on. Core reads the same defaults key so
    /// the HUD restore path follows the toggle too. Default off.
    @Published var isWorkspaceSpaceRestoreEnabled: Bool {
        didSet {
            defaults.set(isWorkspaceSpaceRestoreEnabled, forKey: "workspaceSpaceRestoreEnabled")
        }
    }

    @Published var workspaceExperimentsEnabled: Bool {
        didSet { defaults.set(workspaceExperimentsEnabled, forKey: "workspaceExperimentsEnabled") }
    }

    private let defaults: UserDefaults
    private let languageAtLaunch: AppLanguage

    init(
        defaults: UserDefaults = .standard,
        domainName: String = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    ) {
        self.defaults = defaults
        let language = AppLanguage.read(from: defaults, domainName: domainName)
        self.language = language
        languageAtLaunch = language
        hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
        appearance = AppAppearance(
            rawValue: defaults.string(forKey: "appAppearance") ?? ""
        ) ?? .system
        isDockClickMinimizeEnabled = defaults.bool(forKey: "dockClickMinimizeEnabled")
        isSnapEnabled = defaults.object(forKey: "isSnapEnabled") as? Bool ?? false
        workspaceExperimentsEnabled = defaults.bool(forKey: "workspaceExperimentsEnabled")
        isWorkspaceSpaceRestoreEnabled = defaults.bool(forKey: "workspaceSpaceRestoreEnabled")
    }
}
