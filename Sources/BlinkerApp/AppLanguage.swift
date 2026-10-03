import Foundation

/// App-specific language overrides use the same preference read by Foundation,
/// AppKit and the Core resource bundle on the next launch.
enum AppLanguage: String, CaseIterable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var menuLabel: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    static func read(from defaults: UserDefaults, domainName: String) -> Self {
        // Reading stringArray(forKey:) would include the global language order
        // and mistake the system preference for an explicit app override.
        guard let languages = defaults.persistentDomain(forName: domainName)?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        switch Locale(identifier: first).language.languageCode?.identifier {
        case "zh": return .chinese
        case "en": return .english
        default: return .system
        }
    }

    func persist(in defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
