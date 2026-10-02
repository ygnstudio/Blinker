import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Standard application directories with a file picker for apps installed elsewhere.
struct AppLibraryPicker: View {
    /// Called with the picked app; the sheet closes afterwards.
    let onSelect: (InstalledApp) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var installedApps: [InstalledApp] = []
    @State private var searchText = ""
    @State private var selection: InstalledApp.ID?
    @State private var invalidApplication = false
    @State private var isScanning = true

    private var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return installedApps
        }
        return installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedApp: InstalledApp? {
        filteredApps.first { $0.id == selection }
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
                prompt: "搜索应用"
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("选择其他应用…", action: chooseApplication)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { addSelection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedApp == nil)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
        .task {
            // Scanning several directories hits the disk; keep it off the
            // first render pass so the sheet opens instantly.
            let scan = Task.detached(priority: .userInitiated) {
                ApplicationLibrary.installedApps()
            }
            let apps = await withTaskCancellationHandler {
                await scan.value
            } onCancel: {
                scan.cancel()
            }
            guard !Task.isCancelled else { return }
            installedApps = apps
            isScanning = false
        }
        .alert("无法添加此应用", isPresented: $invalidApplication) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请选择带有有效应用标识的其他 macOS 应用。")
        }
    }

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
        List(filteredApps, selection: $selection) { app in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).lineLimit(1)
                    Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } icon: {
                Image(nsImage: AppIconStore.icon(forBundleIdentifier: app.id, path: app.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            .tag(app.id)
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: InstalledApp.ID.self) { _ in } primaryAction: { identifiers in
            if let app = filteredApps.first(where: { identifiers.contains($0.id) }) {
                select(app)
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let app = ApplicationLibrary.application(at: url) else {
                invalidApplication = true
                return
            }
            select(app)
        }
    }

    private func select(_ app: InstalledApp) {
        onSelect(app)
        dismiss()
    }

    private func addSelection() {
        guard let app = selectedApp else { return }
        select(app)
    }
}
