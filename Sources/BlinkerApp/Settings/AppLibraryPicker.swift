import AppKit
import SwiftUI

/// One app found in the local application library.
struct InstalledApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    let path: String

    var id: String {
        bundleIdentifier
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

/// Scans the standard application directories for installed apps.
enum ApplicationLibrary {
    /// Directories scanned, in preference order (first hit per bundle id wins).
    private static let directories = [
        "/Applications",
        "/Applications/Utilities",
        NSString(string: "~/Applications").expandingTildeInPath,
        "/System/Applications",
        "/System/Applications/Utilities",
    ]

    /// All installed apps visible to the user, sorted by name.
    static func installedApps() -> [InstalledApp] {
        var byBundleIdentifier: [String: InstalledApp] = [:]
        let fileManager = FileManager.default
        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
                continue
            }
            for entry in contents.sorted() where entry.hasSuffix(".app") {
                let path = directory + "/" + entry
                guard let bundle = Bundle(url: URL(fileURLWithPath: path)) else { continue }
                guard
                    let bundleIdentifier = bundle.bundleIdentifier,
                    bundleIdentifier != Bundle.main.bundleIdentifier
                else { continue }
                guard byBundleIdentifier[bundleIdentifier] == nil else { continue }
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (entry as NSString).deletingPathExtension
                byBundleIdentifier[bundleIdentifier] = InstalledApp(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    path: path
                )
            }
        }
        return byBundleIdentifier.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Sheet for picking an app from the local application library — every
/// installed app, not just the running ones — with live search filtering.
struct AppLibraryPicker: View {
    /// Called with the picked app; the sheet closes afterwards.
    let onSelect: (InstalledApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = AppPreferences.shared

    @State private var installedApps: [InstalledApp] = []
    @State private var searchText = ""

    private var filteredApps: [InstalledApp] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredApps.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    appList
                }
            }
            .navigationTitle(tr("应用库", "App Library"))
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: tr("搜索应用名称或 Bundle ID", "Search apps or bundle IDs")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("取消", "Cancel")) { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 520)
        .task {
            // Scanning several directories hits the disk; keep it off the
            // first render pass so the sheet opens instantly.
            installedApps = await Task.detached(priority: .userInitiated) {
                ApplicationLibrary.installedApps()
            }.value
        }
    }

    private var appList: some View {
        List(filteredApps) { app in
            Button {
                onSelect(app)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .font(.body)
                        Text(app.bundleIdentifier)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
    }
}
