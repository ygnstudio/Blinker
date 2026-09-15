import Foundation

/// Visual model of the hover enlargement.
public enum HoverOverlayMode: String, Codable, Sendable, Hashable {
    /// Draws enlarged buttons (circle, symbol, dwell ring)
    /// above the native ones.
    case overlay
    /// Invisible enlarged click zones around the native buttons; the
    /// title bar keeps its original look.
    case hotspot
}

/// User-facing configuration for the hover overlay feature.
public struct HoverOverlaySettings: Codable, Hashable, Sendable {
    /// Number of configurable extra-button slots shown to the right of the
    /// traffic lights.
    public static let extraSlotCount = 4

    /// Master switch; when `false` the overlay never appears.
    public var isEnabled: Bool
    /// Enlarged button diameter in points, clamped to 28...48.
    ///
    /// The lower bound keeps the enlarged circle visibly larger than the
    /// native buttons even after the chip's inner padding (8 pt): 28 - 8
    /// = 20 pt is comfortably above a native traffic light.
    public var enlargedSize: CGFloat
    /// Dwell time in milliseconds before a hover click is accepted,
    /// clamped to 0...800. `0` activates immediately. Ignored in hotspot
    /// mode, which always activates immediately.
    public var dwellMilliseconds: Int
    /// When `false`, the overlay only appears for apps that have a rule.
    public var appliesToAllWindows: Bool
    /// Visual model; see `HoverOverlayMode`.
    public var mode: HoverOverlayMode
    /// Extra-button slots to the right of the traffic lights, in display
    /// order. A `nil` slot renders no chip; non-nil slots render a chip that
    /// performs the mapped action on click.
    public var extraButtonActions: [ButtonAction?]

    public init(
        isEnabled: Bool = true,
        enlargedSize: CGFloat = 28,
        dwellMilliseconds: Int = 150,
        appliesToAllWindows: Bool = true,
        mode: HoverOverlayMode = .overlay,
        extraButtonActions: [ButtonAction?] = []
    ) {
        self.isEnabled = isEnabled
        self.enlargedSize = min(max(enlargedSize, 28), 48)
        self.dwellMilliseconds = min(max(dwellMilliseconds, 0), 800)
        self.appliesToAllWindows = appliesToAllWindows
        self.mode = mode
        self.extraButtonActions = Self.normalizedExtraActions(extraButtonActions)
    }

    /// The non-nil extra actions in slot order — the chips actually rendered.
    public var enabledExtraActions: [ButtonAction] {
        extraButtonActions.compactMap { $0 }
    }

    /// Pads or trims the slot list to exactly `extraSlotCount` entries so a
    /// decoded payload can never desync the settings UI or layout.
    private static func normalizedExtraActions(_ actions: [ButtonAction?]) -> [ButtonAction?] {
        var normalized = actions
        if normalized.count > extraSlotCount {
            normalized = Array(normalized.prefix(extraSlotCount))
        }
        while normalized.count < extraSlotCount {
            normalized.append(nil)
        }
        return normalized
    }

    /// Dwell that applies to the active mode: hotspot mode is always
    /// immediate, so a fast click inside the enlarged zone is never eaten.
    public var effectiveDwellMilliseconds: Int {
        mode == .hotspot ? 0 : dwellMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, enlargedSize, dwellMilliseconds, appliesToAllWindows, mode
        case extraButtonActions
    }

    /// Decodes leniently so settings persisted by older versions (without a
    /// `mode`, `maskStyle` or `extraButtonActions` key) still load instead of
    /// resetting to defaults. A persisted `maskStyle` from versions that
    /// sampled the title bar is ignored — the glass tray replaced sampling.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = HoverOverlaySettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled
        enlargedSize = try container
            .decodeIfPresent(CGFloat.self, forKey: .enlargedSize) ?? fallback.enlargedSize
        dwellMilliseconds = try container
            .decodeIfPresent(Int.self, forKey: .dwellMilliseconds) ?? fallback.dwellMilliseconds
        appliesToAllWindows = try container
            .decodeIfPresent(Bool.self, forKey: .appliesToAllWindows) ?? fallback.appliesToAllWindows
        mode = try container.decodeIfPresent(HoverOverlayMode.self, forKey: .mode) ?? fallback.mode
        extraButtonActions = try Self.normalizedExtraActions(
            container.decodeIfPresent([ButtonAction?].self, forKey: .extraButtonActions)
                ?? fallback.extraButtonActions
        )
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
        // One-time migration: surface the window-management chip so the
        // hover button exists without a settings trip. Only fires when the
        // user never configured any extra chip.
        let migrationKey = "com.ygnstudio.blinker.hud-chip-migrated"
        let allSlotsEmpty = storage.extraButtonActions.allSatisfy { $0 == nil }
        if allSlotsEmpty, !defaults.bool(forKey: migrationKey) {
            if storage.extraButtonActions.indices.contains(0) {
                storage.extraButtonActions[0] = .windowManagerPanel
            }
            settings = storage
            defaults.set(true, forKey: migrationKey)
            persist(storage)
        }
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
