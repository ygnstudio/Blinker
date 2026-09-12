import Foundation

/// User-facing configuration for the hover overlay feature.
public struct HoverOverlaySettings: Codable, Hashable, Sendable {
    /// Master switch; when `false` the overlay never appears.
    public var isEnabled: Bool
    /// Enlarged button diameter in points, clamped to 18...48.
    public var enlargedSize: CGFloat
    /// Dwell time in milliseconds before a hover click is accepted,
    /// clamped to 0...800. `0` activates immediately.
    public var dwellMilliseconds: Int
    /// When `false`, the overlay only appears for apps that have a rule.
    public var appliesToAllWindows: Bool

    public init(
        isEnabled: Bool = true,
        enlargedSize: CGFloat = 28,
        dwellMilliseconds: Int = 150,
        appliesToAllWindows: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.enlargedSize = min(max(enlargedSize, 18), 48)
        self.dwellMilliseconds = min(max(dwellMilliseconds, 0), 800)
        self.appliesToAllWindows = appliesToAllWindows
    }
}

/// Persists hover overlay settings in `UserDefaults`.
///
/// Thread safety mirrors `RuleStore`: mutations are expected on the main
/// thread (settings UI); `snapshot` is guarded by a lock because the overlay
/// reads it from the event tap thread. The lock only guards the internal
/// `storage` value — the `@Published` property is assigned *outside* the lock,
/// so Combine subscribers reading `settings` synchronously can never deadlock.
public final class HoverOverlaySettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    /// Internal source of truth; every access is guarded by `lock`.
    private var storage: HoverOverlaySettings

    /// Published for SwiftUI observation; read on the main thread only.
    @Published public private(set) var settings: HoverOverlaySettings

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.ygnstudio.blinker.hover-overlay-settings"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        storage = Self.load(defaults: defaults, key: storageKey)
        settings = storage
    }

    /// Thread-safe copy of the current settings.
    public var snapshot: HoverOverlaySettings {
        lock.withLock { storage }
    }

    public func update(_ newSettings: HoverOverlaySettings) {
        assert(Thread.isMainThread, "HoverOverlaySettingsStore mutations must happen on the main thread")
        lock.withLock {
            storage = newSettings
        }
        settings = newSettings
        persist(newSettings)
    }

    private func persist(_ current: HoverOverlaySettings) {
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> HoverOverlaySettings {
        guard let data = defaults.data(forKey: key) else { return HoverOverlaySettings() }
        return (try? JSONDecoder().decode(HoverOverlaySettings.self, from: data)) ?? HoverOverlaySettings()
    }
}
