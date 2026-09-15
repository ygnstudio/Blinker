import AppKit
import BlinkerCore
import SwiftUI

// MARK: - Rules tab

/// Per-app remapping of the traffic light buttons as a master-detail
/// surface: a compact rule list on the left, the full click-variant matrix
/// for the selected rule on the right — the Notes-style three-column
/// density, one screen for all fifteen slots.
struct RulesTab: View {
    @ObservedObject var ruleStore: RuleStore
    /// The rule whose matrix the inspector shows; owned by the settings
    /// root so the app-library sheet can auto-select a newly added rule.
    @Binding var selection: AppRule.ID?

    private var enabledRules: [AppRule] { ruleStore.rules.filter(\.isEnabled) }
    private var disabledRules: [AppRule] { ruleStore.rules.filter { !$0.isEnabled } }

    /// A deleted selection gracefully falls back to the placeholder
    /// instead of showing a stale rule.
    private var selectedRule: AppRule? {
        ruleStore.rules.first { $0.id == selection }
    }

    var body: some View {
        Group {
            if ruleStore.rules.isEmpty {
                emptyState
            } else {
                listDetail
            }
        }
    }

    // MARK: - List-detail split

    private var listDetail: some View {
        HStack(spacing: 0) {
            ruleList
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
            Divider()
            if let rule = selectedRule {
                RuleInspectorView(rule: rule, onUpdate: { ruleStore.upsert($0) })
            } else {
                placeholder
            }
        }
    }

    private var ruleList: some View {
        List(selection: $selection) {
            // Notes-style grouping: headers separate live groups so disabled
            // rules stay discoverable instead of sinking to the bottom.
            if !enabledRules.isEmpty {
                Section(tr("已启用", "Enabled")) {
                    ForEach(enabledRules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete { removeRules(at: $0, from: enabledRules) }
                }
            }
            if !disabledRules.isEmpty {
                Section(tr("已停用", "Disabled")) {
                    ForEach(disabledRules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete { removeRules(at: $0, from: disabledRules) }
                }
            }
        }
        .listStyle(.inset)
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        RuleListRow(rule: rule)
            .tag(rule.id)
            .contextMenu {
                Button(role: .destructive) {
                    ruleStore.remove(bundleIdentifier: rule.bundleIdentifier)
                } label: {
                    Label(tr("删除规则", "Delete Rule"), systemImage: "trash")
                }
            }
    }

    /// Maps List's delete offsets back onto the section's rules.
    private func removeRules(at offsets: IndexSet, from source: [AppRule]) {
        for index in offsets {
            ruleStore.remove(bundleIdentifier: source[index].bundleIdentifier)
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label(tr("选择一个应用", "Select an App"), systemImage: "sidebar.right")
        } description: {
            Text(tr(
                "在左侧选择一个应用，即可在右侧为它的红绿灯配置各点击方式的动作。",
                "Pick an app on the left to map its traffic lights per click variant."
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        // The system-standard empty state, matching first-party apps; the
        // symbol mirrors the sidebar icon for coherence.
        ContentUnavailableView {
            Label(tr("还没有配置任何应用", "No Apps Configured"), systemImage: "list.bullet.rectangle")
        } description: {
            Text(tr(
                "点击侧栏下方的 ＋ 添加应用，即可单独定义它的红绿灯行为；未添加的应用保持系统默认。",
                "Click the ＋ at the bottom of the sidebar to add an app and remap its"
                    + " traffic lights; everything else keeps system defaults."
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Resolves and caches app icons by bundle identifier. `NSWorkspace` icon
/// resolution hits the disk (bundle lookup + icns read), so list rows must
/// never compute it inline — every render would pay the cost.
enum AppIconStore {
    private static let cache = NSCache<NSString, NSImage>()

    /// The app's icon, falling back to the generic application icon when
    /// the app is no longer installed.
    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let cached = cache.object(forKey: bundleIdentifier as NSString) {
            return cached
        }
        let resolved: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            resolved = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            resolved = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        cache.setObject(resolved, forKey: bundleIdentifier as NSString)
        return resolved
    }
}

/// One compact row of the rule list: app icon, name and a summary of how
/// many slots are customized — the Notes-style title + subtitle density.
private struct RuleListRow: View {
    let rule: AppRule

    /// The app's cached icon (see `AppIconStore`); no per-render disk I/O.
    private var appIcon: NSImage {
        AppIconStore.icon(forBundleIdentifier: rule.bundleIdentifier)
    }

    /// How many of the fifteen slots carry a non-default action.
    private var customizedCount: Int {
        ClickVariant.allCases.reduce(0) { count, variant in
            count + TrafficButton.allCases
                .filter { rule.action(for: $0, variant: variant) != nil }
                .count
        }
    }

    /// Red/yellow/green left-click mappings as a compact "红=退出 · 绿=最大化"
    /// line — the actual mappings at a glance, instead of a bare count.
    /// Falls back to the count when only enhanced variants are customized.
    private var summaryLine: String {
        let segments = [
            mapping(.close, tr("红", "Red")),
            mapping(.minimize, tr("黄", "Yellow")),
            mapping(.zoom, tr("绿", "Green")),
        ].compactMap(\.self)

        if segments.isEmpty {
            return customizedCount == 0
                ? tr("系统默认行为", "System defaults")
                : tr("\(customizedCount) 项自定义", "\(customizedCount) customized")
        }
        return segments.joined(separator: tr(" · ", " · "))
    }

    /// The button's left-click mapping as "红=退出"; `nil` when default.
    private func mapping(_ button: TrafficButton, _ label: String) -> String? {
        guard let action = rule.action(for: button, variant: .left) else { return nil }
        return "\(label)=\(action.localizedLabel)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(summaryLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
