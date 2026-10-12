import Foundation

struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let name: String
    let path: String

    var id: String {
        bundleIdentifier
    }
}

/// Filesystem metadata only; icons are resolved for visible rows on the main actor.
enum ApplicationLibrary {
    private static let directories = [
        "/Applications",
        "/Applications/Utilities",
        NSString(string: "~/Applications").expandingTildeInPath,
        "/System/Applications",
        "/System/Applications/Utilities",
    ]

    static func installedApps() -> [InstalledApp] {
        installedApps(in: directories.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    static func installedApps(in directories: [URL]) -> [InstalledApp] {
        var apps: [String: InstalledApp] = [:]
        for root in directories {
            guard !Task.isCancelled else { return [] }
            // Safari's /Applications link carries the Finder hidden flag.
            // Keep these application entries; only omit dot-prefixed metadata.
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: []
            ) else { continue }
            for url in urls.sorted(by: { $0.path < $1.path }) {
                guard !Task.isCancelled else { return [] }
                guard !url.lastPathComponent.hasPrefix(".") else { continue }
                if let app = application(at: url), apps[app.id] == nil {
                    apps[app.id] = app
                }
            }
        }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func application(at url: URL) -> InstalledApp? {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let resolved = url.resolvingSymlinksInPath()
        guard let bundle = Bundle(url: resolved),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
              identifier != Bundle.main.bundleIdentifier else { return nil }
        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? resolved.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleIdentifier: identifier, name: name, path: resolved.path)
    }
}
