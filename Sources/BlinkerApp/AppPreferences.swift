import SwiftUI

/// User-facing interface appearance, persisted across launches. The
/// interface language follows the system (String Catalog), so no language
/// preference lives here.
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
}

/// Appearance and feature preferences shared by every window.
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appAppearance") }
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

    private let defaults = UserDefaults.standard

    private init() {
        appearance = AppAppearance(
            rawValue: defaults.string(forKey: "appAppearance") ?? ""
        ) ?? .system
        isSnapEnabled = defaults.object(forKey: "isSnapEnabled") as? Bool ?? true
        isWorkspaceSpaceRestoreEnabled = defaults.bool(forKey: "workspaceSpaceRestoreEnabled")
    }
}
