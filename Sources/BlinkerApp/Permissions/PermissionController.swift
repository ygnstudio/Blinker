import AppKit
import BlinkerCore
import Combine

enum AppPermission: String, CaseIterable, Identifiable {
    case accessibility
    case screenRecording

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .accessibility: String(localized: "辅助功能")
        case .screenRecording: String(localized: "屏幕录制")
        }
    }

    fileprivate var settingsPane: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
    }
}

/// Shared by settings and onboarding; checks never prompt or revoke permission.
@MainActor
final class PermissionController: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var screenRecordingGranted: Bool
    @Published private(set) var settingsOpenFailed = false
    let appURL: URL?

    private let thumbnails: WindowThumbnailStore
    private let accessibilityCheck: () -> Bool
    private let accessibilityRequest: () -> Void
    private let screenRecordingRequest: () -> Void
    private let settingsOpener: (AppPermission) -> Bool
    private var requestedPermissions: Set<AppPermission> = []
    private var subscriptions: Set<AnyCancellable> = []

    convenience init(thumbnails: WindowThumbnailStore) {
        self.init(
            thumbnails: thumbnails,
            accessibilityCheck: { AccessibilityPermission.isTrusted },
            accessibilityRequest: AccessibilityPermission.prompt,
            screenRecordingRequest: { thumbnails.requestPermission() },
            settingsOpener: Self.openSystemSettings
        )
    }

    init(thumbnails: WindowThumbnailStore, accessibilityCheck: @escaping () -> Bool,
         accessibilityRequest: @escaping () -> Void, screenRecordingRequest: @escaping () -> Void,
         settingsOpener: @escaping (AppPermission) -> Bool) {
        self.thumbnails = thumbnails
        self.accessibilityCheck = accessibilityCheck
        self.accessibilityRequest = accessibilityRequest
        self.screenRecordingRequest = screenRecordingRequest
        self.settingsOpener = settingsOpener
        accessibilityGranted = accessibilityCheck()
        screenRecordingGranted = thumbnails.permissionGranted
        appURL = RunningApplicationBundle.url

        // This store is MainActor-isolated; use its existing capture permission state.
        thumbnails.$permissionGranted.removeDuplicates().sink { [weak self] granted in
            self?.screenRecordingGranted = granted
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    func isGranted(_ permission: AppPermission) -> Bool {
        switch permission {
        case .accessibility: accessibilityGranted
        case .screenRecording: screenRecordingGranted
        }
    }

    func refresh() {
        accessibilityGranted = accessibilityCheck()
        thumbnails.checkPermission()
    }

    /// Call only from an explicit user action. Repeated requests open the settings pane.
    func request(for permission: AppPermission) {
        refresh()
        if !isGranted(permission), requestedPermissions.insert(permission).inserted {
            switch permission {
            case .accessibility: accessibilityRequest()
            case .screenRecording: screenRecordingRequest()
            }
        }
        refresh()
        openSettings(for: permission)
    }

    /// Also used for reauthorization guidance; never resets or changes TCC grants.
    @discardableResult
    func openSettings(for permission: AppPermission) -> Bool {
        let opened = settingsOpener(permission)
        settingsOpenFailed = !opened
        return opened
    }

    private static func openSystemSettings(for permission: AppPermission) -> Bool {
        let address = "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)"
        if let url = URL(string: address), NSWorkspace.shared.open(url) {
            return true
        }
        guard let settingsURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ) else { return false }
        return NSWorkspace.shared.open(settingsURL)
    }

    @discardableResult
    func revealApp() -> Bool {
        guard let appURL else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
        return true
    }
}

/// Never substitutes a guessed installation path or a bare executable for the running app.
enum RunningApplicationBundle {
    static var url: URL? {
        let url = Bundle.main.bundleURL.standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true,
              let executable = Bundle.main.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return url
    }
}
