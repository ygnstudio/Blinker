import BlinkerCore
import SwiftUI

/// One work surface: choosing an application never navigates away from its editor.
struct ApplicationRulesView: View {
    @EnvironmentObject private var ruleStore: RuleStore
    @EnvironmentObject private var navigation: WorkbenchNavigation
    @Environment(\.eclipsePalette) private var palette
    @Binding var selection: AppRule.ID?
    @Binding var showsDefaults: Bool
    @Binding var searchText: String
    let onInspect: (String) -> Void
    let onOpenSettings: () -> Void
    @Binding var showingAppLibrary: Bool
    @State private var installedApps: [InstalledApp] = []
    @State private var isScanning = true
    @AppStorage("eclipse.rules.onlyConfigured") private var onlyConfigured = false
    @State private var ruleToDelete: AppRule?
    @StateObject private var files = RuleFileActions()
    @FocusState private var searchFocused: Bool

    private var applications: [RuleWorkspaceApplication] {
        RuleWorkspaceCatalog.applications(installed: installedApps, rules: ruleStore.rules)
    }

    private var filtered: [RuleWorkspaceApplication] {
        RuleWorkspaceCatalog.filtered(applications, query: searchText,
                                      onlyConfigured: onlyConfigured && !ruleStore.isReadOnly)
    }

    private var selectedApp: RuleWorkspaceApplication? {
        applications.first { $0.id == selection }
    }

    private var selectedRule: AppRule? {
        guard let selectedApp else { return nil }
        return ruleStore.rules.first { $0.id == selectedApp.id }
            ?? AppRule.inheritingDefaults(bundleIdentifier: selectedApp.id, displayName: selectedApp.name)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            sidebar.frame(width: 200)
            VStack(spacing: 0) {
                if ruleStore.isReadOnly {
                    ContentUnavailableView {
                        Label("配置预览不可用", systemImage: "doc.badge.ellipsis")
                    } description: {
                        Text("当前版本无法读取已保存的规则。请使用兼容版本；原配置仍保留。")
                    }
                } else if showsDefaults {
                    GlobalRulesView()
                } else if let rule = selectedRule {
                    RuleInspectorView(rule: rule, onUpdate: { ruleStore.upsert($0) },
                                      onInspect: { onInspect(rule.id) },
                                      isFilteredOut: !filtered.contains { $0.id == rule.id })
                } else {
                    ContentUnavailableView {
                        Label("选择应用", systemImage: "app.dashed")
                    } description: {
                        Text(isScanning ? "正在读取已安装应用。" : "从应用列表选择，或添加其他位置的应用。")
                    } actions: {
                        Button("添加应用…") { showingAppLibrary = true }
                    }
                }
                if files.state != .idle { RuleFileStatus(files: files) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .foregroundStyle(palette.text)
        .safeAreaInset(edge: .top) {
            if let issue = ruleStore.writeIssue {
                Label(issue.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(palette.surface)
            }
        }
        .onAppear {
            ruleStore.refreshPersistenceStatus()
            focusRequestedSearch()
        }
        .onChange(of: navigation.applicationSearchRequest) { _, _ in focusRequestedSearch() }
        .onChange(of: ruleStore.rules) { _, _ in validateSelection() }
        .onDisappear { files.cancel() }
        .task { await scanApplications() }
        .sheet(isPresented: $showingAppLibrary) {
            AppLibraryPicker { app in
                if !installedApps.contains(where: { $0.id == app.id }) { installedApps.append(app) }
                searchText = ""
                onlyConfigured = false
                selection = app.id
                showsDefaults = false
            }
        }
        .alert("删除应用规则？", isPresented: Binding(
            get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }
        )) {
            Button("取消", role: .cancel) { ruleToDelete = nil }
            Button("删除", role: .destructive) {
                if let ruleToDelete { ruleStore.remove(bundleIdentifier: ruleToDelete.id) }
                ruleToDelete = nil
            }
        } message: {
            Text("此应用的按钮将沿用默认行为，悬停跟随全局设置。删除后可以撤销。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("应用规则").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showingAppLibrary = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(palette.secondary)
                    .help("添加其他位置的应用").accessibilityLabel("添加应用")
                    .keyboardShortcut("n", modifiers: .command).disabled(files.isBusy)
            }
            Button { showsDefaults = true } label: {
                Label("默认行为", systemImage: "macwindow")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(showsDefaults ? palette.selection : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workbench.globalDefaults")
            .accessibilityValue(showsDefaults ? "当前页面" : "")
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary)
                TextField("搜索应用或标识", text: $searchText)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityIdentifier("workbench.appSearch")
            }
            .padding(8).background(palette.hover, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 4) {
                filterButton("全部", configured: false)
                filterButton("已配置", configured: true)
            }
            .accessibilityElement(children: .contain).accessibilityLabel("应用筛选")
            .disabled(ruleStore.isReadOnly)
            if isScanning && applications.isEmpty {
                ProgressView("读取应用…").controlSize(.small).padding(.top, 12)
            }
            EclipseSelectionList(filtered, id: \.id, selection: Binding(
                get: { showsDefaults ? nil : selection },
                set: { selected in
                    guard let selected else { return }
                    selection = selected
                    showsDefaults = false
                }
            )) { app, _ in
                appRow(app)
            } contextMenu: { app in
                Button("检查兼容性") { onInspect(app.id) }
                Button("删除应用规则…", role: .destructive) {
                    ruleToDelete = ruleStore.rules.first { $0.id == app.id }
                }.disabled(!app.hasRule || ruleStore.isReadOnly)
            }
            .overlay {
                if !isScanning && filtered.isEmpty {
                    VStack(spacing: 8) {
                        Text("没有匹配的应用").font(.callout)
                        Button("清除筛选") { searchText = ""; onlyConfigured = false }
                    }.foregroundStyle(palette.secondary)
                }
            }
            HStack {
                Text("\(filtered.count) 个应用").font(.caption).foregroundStyle(palette.secondary)
                Spacer()
                RuleToolsMenu(store: ruleStore, ruleID: showsDefaults ? nil : selectedRule?.id, files: files)
                    .menuStyle(.borderlessButton).fixedSize().help("导入、导出与规则操作")
            }
            Text(ruleStore.isReadOnly ? "规则状态无法读取。" : "未配置的应用沿用默认行为。")
                .font(.caption).foregroundStyle(palette.secondary)
        }
        .padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func filterButton(_ title: String, configured: Bool) -> some View {
        Button { onlyConfigured = configured } label: {
            Text(title).font(.system(size: 11, weight: .medium))
                .foregroundStyle(onlyConfigured == configured ? palette.text : palette.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(onlyConfigured == configured ? palette.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(onlyConfigured == configured ? .isSelected : [])
        .accessibilityValue(onlyConfigured == configured ? "已选中" : "")
    }

    private func appRow(_ app: RuleWorkspaceApplication) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: AppIconStore.icon(forBundleIdentifier: app.id, path: app.path))
                .resizable().frame(width: 25, height: 25).accessibilityHidden(true)
            Text(app.name).font(.system(size: 12)).lineLimit(1).help(app.id)
            Spacer(minLength: 2)
            if app.hasRule && !ruleStore.isReadOnly {
                Image(systemName: "circle.fill").font(.system(size: 5))
                    .foregroundStyle(palette.accent).accessibilityLabel("已配置")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workbench.app.\(app.id)")
    }

    private func focusRequestedSearch() {
        guard let request = navigation.applicationSearchRequest else { return }
        // Let the field attach to the window before transferring keyboard focus.
        DispatchQueue.main.async {
            guard navigation.consumeApplicationSearchRequest(request) else { return }
            searchFocused = true
        }
    }

    private func validateSelection() {
        selection = RuleWorkspaceCatalog.selection(selection, in: applications)
    }

    private func scanApplications() async {
        let worker = Task.detached(priority: .userInitiated) { ApplicationLibrary.installedApps() }
        let apps = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return }
        installedApps = apps
        isScanning = false
        validateSelection()
    }
}
