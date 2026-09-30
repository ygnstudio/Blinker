import BlinkerCore
import SwiftUI

/// An ordinary list window, with each rule opening in a separate editor.
struct ApplicationRulesView: View {
    @EnvironmentObject var ruleStore: RuleStore
    let onEdit: (AppRule) -> Void
    let onOpenSettings: () -> Void
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var searchText = ""
    @State private var selection: AppRule.ID?
    @State private var showingAppLibrary = false
    @State private var ruleToDelete: AppRule?

    private var rules: [AppRule] {
        ruleStore.rules.filter {
            searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var selectedRule: AppRule? {
        rules.first { $0.id == selection }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ruleStore.rules.isEmpty {
                    ContentUnavailableView {
                        Label("为应用自定义红绿灯", systemImage: "macwindow")
                    } description: {
                        Text("添加一个应用，为它选择关闭、最小化和缩放按钮的动作。")
                    } actions: {
                        Button("添加应用", systemImage: "plus") { showingAppLibrary = true }
                    }
                } else if rules.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ruleList
                }
            }
            .navigationTitle("应用规则")
            .searchable(text: $searchText, prompt: "搜索应用")
            .toolbar {
                ToolbarItem {
                    Button("添加应用", systemImage: "plus") { showingAppLibrary = true }
                        .keyboardShortcut("n", modifiers: .command)
                }
                ToolbarItem {
                    Button("编辑规则", systemImage: "slider.horizontal.3") { editSelection() }
                        .disabled(selectedRule == nil)
                }
                ToolbarItem {
                    Button("设置…", systemImage: "gearshape", action: onOpenSettings)
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
        }
        .preferredColorScheme(preferences.appearance.resolvedScheme)
        .sheet(isPresented: $showingAppLibrary) {
            AppLibraryPicker { app in
                let rule = ruleStore.rules.first { $0.id == app.bundleIdentifier }
                    ?? AppRule(bundleIdentifier: app.bundleIdentifier, displayName: app.name)
                ruleStore.upsert(rule)
                searchText = ""
                selection = rule.id
                // Let the picker dismiss before activating another window.
                DispatchQueue.main.async { onEdit(rule) }
            }
        }
        .alert("删除规则？", isPresented: Binding(
            get: { ruleToDelete != nil },
            set: {
                if !$0 {
                    ruleToDelete = nil
                }
            }
        )) {
            Button("取消", role: .cancel) { ruleToDelete = nil }
            Button("删除", role: .destructive) {
                if let rule = ruleToDelete {
                    ruleStore.remove(bundleIdentifier: rule.id)
                }
                ruleToDelete = nil
            }
        } message: {
            Text("删除后，此应用的红绿灯将恢复系统默认行为。")
        }
    }

    private var ruleList: some View {
        List(rules, selection: $selection) { rule in
            HStack(spacing: 12) {
                Image(nsImage: AppIconStore.icon(forBundleIdentifier: rule.id))
                    .resizable().frame(width: 32, height: 32)
                Text(rule.displayName)
                Spacer()
                Text(rule.isEnabled ? String(localized: "已启用") : String(localized: "已停用"))
                    .foregroundStyle(.secondary)
                Button("编辑…") { onEdit(rule) }
            }
            .padding(.vertical, 6)
            .tag(rule.id)
            .contextMenu {
                Button("编辑规则") { onEdit(rule) }
                Button("删除规则…", role: .destructive) { ruleToDelete = rule }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: AppRule.ID.self) { _ in } primaryAction: { ids in
            if let rule = rules.first(where: { ids.contains($0.id) }) {
                onEdit(rule)
            }
        }
        .onDeleteCommand { ruleToDelete = selectedRule }
        .onKeyPress(.return) {
            editSelection()
            return .handled
        }
    }

    private func editSelection() {
        if let rule = selectedRule {
            onEdit(rule)
        }
    }
}

struct ApplicationRuleEditor: View {
    @ObservedObject var ruleStore: RuleStore
    let ruleID: AppRule.ID
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        Group {
            if let rule = ruleStore.rules.first(where: { $0.id == ruleID }) {
                RuleInspectorView(rule: rule, onUpdate: { ruleStore.upsert($0) })
            } else {
                ContentUnavailableView("规则已删除", systemImage: "macwindow")
            }
        }
        .preferredColorScheme(preferences.appearance.resolvedScheme)
    }
}
