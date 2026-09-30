import BlinkerCore
import SwiftUI

/// An ordinary list window, with each rule opening in a separate editor.
struct ApplicationRulesView: View {
    @EnvironmentObject var ruleStore: RuleStore
    let onEdit: (AppRule) -> Void
    let onOpenSettings: () -> Void
    @AppStorage("appAppearance") private var appearance = AppAppearance.system
    @State private var searchText = ""
    @State private var selection: AppRule.ID?
    @State private var showingAppLibrary = false
    @State private var ruleToDelete: AppRule?
    @State private var visibleRules: [AppRule] = []

    private var selectedRule: AppRule? {
        visibleRules.first { $0.id == selection }
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
                } else if visibleRules.isEmpty {
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
                    RuleToolsMenu(store: ruleStore)
                }
                ToolbarItem {
                    Button("设置…", systemImage: "gearshape", action: onOpenSettings)
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
        }
        .preferredColorScheme(appearance.resolvedScheme)
        .onChange(of: ruleStore.rules, initial: true) { rebuildList() }
        .onChange(of: searchText) { rebuildList() }
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
            Text("删除后，此应用的按钮恢复系统默认行为，悬停放大跟随全局作用范围。")
        }
    }

    private var ruleList: some View {
        List(visibleRules, selection: $selection) { rule in
            ApplicationRuleRow(rule: rule)
                .tag(rule.id)
                .contextMenu {
                    Button("编辑规则") { onEdit(rule) }
                    Button("删除规则…", role: .destructive) { ruleToDelete = rule }
                }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: AppRule.ID.self) { _ in } primaryAction: { ids in
            if let rule = visibleRules.first(where: { ids.contains($0.id) }) {
                onEdit(rule)
            }
        }
        .onDeleteCommand { ruleToDelete = selectedRule }
        .onKeyPress(.return) {
            editSelection()
            return .handled
        }
    }

    private func rebuildList() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleRules = ruleStore.rules.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        if !visibleRules.contains(where: { $0.id == selection }) {
            selection = nil
        }
    }

    private func editSelection() {
        if let rule = selectedRule {
            onEdit(rule)
        }
    }
}

private struct ApplicationRuleRow: View {
    let rule: AppRule

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconStore.icon(forBundleIdentifier: rule.id))
                .resizable().frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayName).lineLimit(1)
                Text(rule.bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(rule.isEnabled ? String(localized: "按钮规则已启用") : String(localized: "按钮规则已停用"))
                Text(rule.isHoverEnabled ? String(localized: "允许悬停放大") : String(localized: "已关闭悬停放大"))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
