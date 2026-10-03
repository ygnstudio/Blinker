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
    @State private var isActive = false
    @State private var applicationRequest: UUID?
    @State private var isReadingApplication = false
    @State private var applicationPanel: NSOpenPanel?
    @State private var applicationTask: Task<Void, Never>?

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
            VStack(alignment: .leading, spacing: 10) {
                selectionStatus.frame(height: 18)
                HStack {
                    Button("选择其他应用…", action: chooseApplication)
                        .disabled(applicationRequest != nil)
                    Spacer()
                    Button("取消") {
                        stopChoosingApplication()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("添加") { addSelection() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedApp == nil || applicationRequest != nil)
                }
            }
            .padding()
        }
        .frame(width: 460, height: 520)
        .onAppear { isActive = true }
        .onDisappear {
            isActive = false
            stopChoosingApplication()
        }
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
        OperationProgress(message: String(localized: "正在扫描应用库…"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var selectionStatus: some View {
        if isReadingApplication {
            OperationProgress(message: String(localized: "正在读取应用信息…"))
        } else if applicationRequest != nil {
            Text("请选择要添加的应用…").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("\(filteredApps.count) 个应用").font(.caption).foregroundStyle(.secondary)
                .opacity(isScanning ? 0 : 1)
        }
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
        .disabled(applicationRequest != nil)
        .contextMenu(forSelectionType: InstalledApp.ID.self) { _ in } primaryAction: { identifiers in
            if let app = filteredApps.first(where: { identifiers.contains($0.id) }) {
                select(app)
            }
        }
    }

    private func chooseApplication() {
        guard isActive, applicationRequest == nil else { return }
        let request = UUID()
        applicationRequest = request
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        applicationPanel = panel
        panel.begin { response in
            guard isActive, applicationRequest == request else { return }
            guard response == .OK, let url = panel.url else {
                stopChoosingApplication()
                return
            }
            applicationPanel = nil
            isReadingApplication = true
            applicationTask = Task {
                let worker = Task.detached(priority: .userInitiated) {
                    guard !Task.isCancelled else { return InstalledApp?.none }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    return ApplicationLibrary.application(at: url)
                }
                let app = await withTaskCancellationHandler { await worker.value } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, isActive, applicationRequest == request else { return }
                applicationRequest = nil
                applicationTask = nil
                isReadingApplication = false
                if let app {
                    select(app)
                } else {
                    invalidApplication = true
                }
            }
        }
    }

    private func stopChoosingApplication() {
        applicationRequest = nil
        applicationTask?.cancel()
        applicationTask = nil
        isReadingApplication = false
        let panel = applicationPanel
        applicationPanel = nil
        panel?.cancel(nil)
    }

    private func select(_ app: InstalledApp) {
        guard isActive, applicationRequest == nil else { return }
        isActive = false
        onSelect(app)
        dismiss()
    }

    private func addSelection() {
        guard let app = selectedApp else { return }
        select(app)
    }
}
