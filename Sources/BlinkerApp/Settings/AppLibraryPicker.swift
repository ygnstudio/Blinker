import AppKit
import SwiftUI

/// One app found in the local application library.
struct InstalledApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    let path: String
    /// Resolved once during the (backgrounded) library scan; a computed
    /// property would re-hit `NSWorkspace` on every list row render.
    let icon: NSImage

    var id: String {
        bundleIdentifier
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
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
                    path: path,
                    icon: NSWorkspace.shared.icon(forFile: path)
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

    @State private var installedApps: [InstalledApp] = []
    @State private var searchText = ""
    /// True until the (backgrounded) library scan finishes; the scan takes
    /// real disk time, and without this flag the empty list briefly reads
    /// as "no results" — an honest loading state instead.
    @State private var isScanning = true

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
                if isScanning {
                    scanningState
                } else if filteredApps.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    appList
                }
            }
            .navigationTitle("应用库")
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: "搜索应用名称或 Bundle ID"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
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
            isScanning = false
        }
    }

    /// The scan's honest loading state: a centered progress indicator, not
    /// a mislabeled empty state.
    private var scanningState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("正在扫描应用库…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
