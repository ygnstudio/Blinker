import Combine
import Foundation

final class WindowBrowserPreferences: ObservableObject {
    @Published var switcherEnabled: Bool {
        didSet { save(switcherEnabled, "switcher") }
    }

    @Published var dockEnabled: Bool {
        didSet { save(dockEnabled, "dock") }
    }

    @Published var thumbnailsEnabled: Bool {
        didSet { save(thumbnailsEnabled, "thumbnails") }
    }

    @Published var includeMinimized: Bool {
        didSet { save(includeMinimized, "minimized") }
    }

    @Published var currentDisplayOnly: Bool {
        didSet { save(currentDisplayOnly, "display") }
    }

    @Published var dockAppearanceMilliseconds: Double {
        didSet {
            defaults.set(dockAppearanceMilliseconds, forKey: Self.key("dockAppearanceMilliseconds"))
            runtimeChanges.send()
        }
    }

    @Published var dockDismissalMilliseconds: Double {
        didSet {
            defaults.set(dockDismissalMilliseconds, forKey: Self.key("dockDismissalMilliseconds"))
            runtimeChanges.send()
        }
    }

    @Published var includeTabs: Bool {
        didSet { save(includeTabs, "tabs") }
    }

    @Published var previewScale: Double {
        didSet { defaults.set(previewScale, forKey: Self.key("previewScale")) }
    }

    let runtimeChanges = PassthroughSubject<Void, Never>()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        includeTabs = defaults.object(forKey: Self.key("tabs")) as? Bool ?? true
        switcherEnabled = defaults.object(forKey: Self.key("switcher")) as? Bool ?? true
        dockEnabled = defaults.object(forKey: Self.key("dock")) as? Bool ?? true
        thumbnailsEnabled = defaults.object(forKey: Self.key("thumbnails")) as? Bool ?? true
        includeMinimized = defaults.object(forKey: Self.key("minimized")) as? Bool ?? true
        currentDisplayOnly = defaults.bool(forKey: Self.key("display"))
        let savedScale = defaults.object(forKey: Self.key("previewScale")) as? Double ?? 1
        previewScale = savedScale.isFinite ? min(1.5, max(0.5, savedScale)) : 1
        dockAppearanceMilliseconds = Self.delay(defaults, "dockAppearanceMilliseconds",
                                                fallback: 150, minimum: 0)
        dockDismissalMilliseconds = Self.delay(defaults, "dockDismissalMilliseconds",
                                               fallback: 200, minimum: 100)
    }

    private static func delay(_ defaults: UserDefaults, _ name: String, fallback: Double,
                              minimum: Double) -> Double {
        guard let value = defaults.object(forKey: key(name)) as? Double, value.isFinite else {
            return fallback
        }
        return min(1000, max(minimum, value))
    }

    private static func key(_ name: String) -> String {
        "com.ygnstudio.blinker.browser." + name
    }

    private func save(_ value: Bool, _ name: String) {
        defaults.set(value, forKey: Self.key(name))
        runtimeChanges.send()
    }
}
