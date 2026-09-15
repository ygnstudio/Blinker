import SwiftUI

/// User-facing interface language, persisted across launches.
enum AppLanguage: String, CaseIterable, Codable {
    case system
    case simplifiedChinese
    case english

    var menuLabel: String {
        switch self {
        case .system: tr("跟随系统", "Follow System")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

/// User-facing interface appearance, persisted across launches.
enum AppAppearance: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var menuLabel: String {
        switch self {
        case .system: tr("跟随系统", "Follow System")
        case .light: tr("浅色", "Light")
        case .dark: tr("深色", "Dark")
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

/// Language and appearance preferences shared by every window.
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "appLanguage") }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appAppearance") }
    }

    /// Whether dragging windows to screen edges/corners snaps them.
    @Published var isSnapEnabled: Bool {
        didSet { defaults.set(isSnapEnabled, forKey: "isSnapEnabled") }
    }

    private let defaults = UserDefaults.standard

    private init() {
        language = AppLanguage(
            rawValue: defaults.string(forKey: "appLanguage") ?? ""
        ) ?? .system
        appearance = AppAppearance(
            rawValue: defaults.string(forKey: "appAppearance") ?? ""
        ) ?? .system
        isSnapEnabled = defaults.object(forKey: "isSnapEnabled") as? Bool ?? true
    }

    /// `NSAppearance` for the settings window chrome; `nil` follows the
    /// system. Applying it on the window keeps the titlebar and in-titlebar
    /// tab row in sync with the content instantly.
    var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Whether UI text should render in English. `.system` inspects the
    /// user's preferred languages and falls back to Chinese only for zh.
    var isEnglish: Bool {
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "zh"
            return !preferred.hasPrefix("zh")
        case .simplifiedChinese: return false
        case .english: return true
        }
    }
}
