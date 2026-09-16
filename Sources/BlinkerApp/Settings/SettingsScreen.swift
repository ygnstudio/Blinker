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
    /// Opens the app-library sheet from the empty state's secondary button,
    /// mirroring the sidebar's add-app affordance.
    let onAddApp: () -> Void

    private var enabledRules: [AppRule] {
        ruleStore.rules.filter(\.isEnabled)
    }

    private var disabledRules: [AppRule] {
        ruleStore.rules.filter { !$0.isEnabled }
    }

    /// A deleted selection gracefully falls back to the placeholder
    /// instead of showing a stale rule.
    private var selectedRule: AppRule? {
        ruleStore.rules.first { $0.id == selection }
    }

    var body: some View {
        if ruleStore.rules.isEmpty {
            emptyState
        } else {
            listDetail
        }
    }

    // MARK: - List-detail split

    private var listDetail: some View {
        HStack(spacing: 0) {
            ruleList
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260, maxHeight: .infinity)
                // The Liquid Glass sidebar's floating shadow spills a wide
                // band into the detail column — 12pt only cleared the
                // header text; the selected-row highlight still ran under
                // it. 24pt clears the whole list. The top inset keeps the
                // "已启用" section header below the toolbar edge (the inset
                // list has no top content inset of its own, unlike Form).
                .padding(.leading, 24)
                .padding(.top, 12)
            // No divider between the columns: the inset list's own edge and
            // the grouped-form cards already read as two distinct surfaces.
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
            //
            // macOS quirk (learned the hard way): on the inset list,
            // `.listRowSeparator(.hidden)` is ignored on Section *header*
            // rows — the table view draws their separator no matter what —
            // so the header closure left a lone line under "已启用".
            // The group titles are therefore plain rows inside the section:
            // a regular row's separator hides fine, and an untagged row
            // never joins the selection set, so grouping semantics, the
            // delete gestures, and the selected-row highlight all survive.
            if !enabledRules.isEmpty {
                Section {
                    groupHeader(String(localized: "已启用"))
                    ForEach(enabledRules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete { removeRules(at: $0, from: enabledRules) }
                }
            }
            if !disabledRules.isEmpty {
                Section {
                    groupHeader(String(localized: "已停用"))
                    ForEach(disabledRules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete { removeRules(at: $0, from: disabledRules) }
                }
            }
        }
        .listStyle(.inset)
        // The trio legend stays pinned to the list's foot, mirroring the
        // sidebar footer's constant-height pattern.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            trioLegend
        }
    }

    /// The key to the rule rows' light-status trio: filled = at least one
    /// action configured on that light, hollow = fully system default.
    private var trioLegend: some View {
        HStack(spacing: 14) {
            trio(filled: true)
            Text(String(localized: "已重定义"))
            trio(filled: false)
            Text(String(localized: "系统默认"))
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "圆点图例：实心为已重定义，空心为系统默认"))
    }

    private func trio(filled: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(TrafficButton.allCases, id: \.self) { button in
                Circle()
                    .strokeBorder(
                        Color(nsColor: OverlayChipDrawing.vividColor(for: button)).opacity(0.6),
                        lineWidth: 1
                    )
                    .background(
                        Circle().fill(
                            filled
                                ? Color(nsColor: OverlayChipDrawing.vividColor(for: button))
                                : .clear
                        )
                    )
                    .frame(width: 6, height: 6)
            }
        }
    }

    /// A group title rendered as an ordinary, untagged list row (see the
    /// rule list's comment for why it cannot be a Section header).
    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .listRowSeparator(.hidden)
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        RuleListRow(rule: rule)
            .tag(rule.id)
            // Separator-free list: section headers alone carry the grouping.
            .listRowSeparator(.hidden)
            .contextMenu {
                Button(role: .destructive) {
                    ruleStore.remove(bundleIdentifier: rule.bundleIdentifier)
                } label: {
                    Label("删除规则", systemImage: "trash")
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
            Label("选择一个应用", systemImage: "sidebar.right")
        } description: {
            Text("在左侧选择一个应用，即可在右侧为它的红绿灯配置各点击方式的动作。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        // The system-standard empty state, matching first-party apps; the
        // symbol mirrors the sidebar icon for coherence. The secondary
        // action mirrors the sidebar's add button so the empty tab does
        // not dead-end below the fold.
        ContentUnavailableView {
            Label("还没有配置任何应用", systemImage: "list.bullet.rectangle")
        } description: {
            Text("点击下方按钮或侧栏中的「添加应用」，即可单独定义它的红绿灯行为；未添加的应用保持系统默认。")
        } actions: {
            Button(action: onAddApp) {
                Label("从应用库添加", systemImage: "plus")
            }
            .buttonStyle(.bordered)
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
    /// the app is no longer installed. The fallback is deliberately *not*
    /// cached: if the app gets installed later, the next lookup resolves
    /// the real icon within the same session instead of showing the
    /// placeholder until relaunch.
    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let cached = cache.object(forKey: bundleIdentifier as NSString) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let resolved = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(resolved, forKey: bundleIdentifier as NSString)
        return resolved
    }
}

/// One compact single-line row of the rule list: app icon, name and the
/// three-light status trio — a filled dot marks a light carrying at least
/// one custom action, a hollow ring a fully default light. The trio makes
/// each rule's configuration depth scannable without opening it.
private struct RuleListRow: View {
    let rule: AppRule

    /// The app's cached icon (see `AppIconStore`); no per-render disk I/O.
    private var appIcon: NSImage {
        AppIconStore.icon(forBundleIdentifier: rule.bundleIdentifier)
    }

    /// Per light: whether any of the five click variants carries an action.
    private var remappedLights: [TrafficButton: Bool] {
        var states: [TrafficButton: Bool] = [:]
        for button in TrafficButton.allCases {
            let variants = [ClickVariant.left] + ClickVariant.extraSlots
            states[button] = variants.contains { rule.action(for: button, variant: $0) != nil }
        }
        return states
    }

    /// The trio's spoken summary, e.g. "已重定义：红灯、绿灯".
    private var trioAccessibilityLabel: String {
        let remapped = TrafficButton.allCases
            .filter { remappedLights[$0] == true }
            .map { lightName($0) }
        if remapped.isEmpty {
            return String(localized: "三灯均为系统默认")
        }
        return String(localized: "已重定义：") + remapped.joined(separator: String(localized: "、"))
    }

    private func lightName(_ button: TrafficButton) -> String {
        switch button {
        case .close: String(localized: "红灯")
        case .minimize: String(localized: "黄灯")
        case .zoom: String(localized: "绿灯")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(rule.displayName)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(TrafficButton.allCases, id: \.self) { button in
                    let color = Color(nsColor: OverlayChipDrawing.vividColor(for: button))
                    let isRemapped = remappedLights[button] == true
                    Circle()
                        .strokeBorder(isRemapped ? .clear : color.opacity(0.6), lineWidth: 1)
                        .background(Circle().fill(isRemapped ? color : .clear))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(trioAccessibilityLabel)
        }
        .padding(.vertical, 2)
    }
}
