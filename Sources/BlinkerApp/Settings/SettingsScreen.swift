import AppKit
import BlinkerCore
import SwiftUI

// MARK: - Rules tab

/// Per-app remapping of the traffic light buttons.
struct RulesTab: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var showingAppLibrary = false
    /// The currently selected rule row; drives the footer's minus button.
    @State private var selection: AppRule.ID?

    private var selectedRule: AppRule? {
        ruleStore.rules.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if ruleStore.rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
            Divider()
            footerBar
        }
    }

    private var ruleList: some View {
        List(selection: $selection) {
            ForEach(ruleStore.rules) { rule in
                RuleRowView(
                    rule: rule,
                    onUpdate: { ruleStore.upsert($0) }
                )
                .tag(rule.id)
            }
        }
        // Plain inset list with separators — no alternating stripes, which
        // would paint the empty area below the rows.
        .listStyle(.inset)
    }

    private var emptyState: some View {
        // The system-standard empty state, matching first-party apps.
        ContentUnavailableView {
            Label(tr("还没有配置任何应用", "No Apps Configured"), systemImage: "circle.circle")
        } description: {
            Text(tr(
                "添加应用后，即可单独定义它的红绿灯行为；未添加的应用保持系统默认。",
                "Add an app to remap its traffic lights; everything else keeps system defaults."
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The system-settings-style footer bar: small plus/minus buttons at the
    /// leading edge (like the Login Items list) with the hint caption after
    /// them.
    private var footerBar: some View {
        HStack(spacing: 12) {
            Button {
                showingAppLibrary = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(tr("添加应用", "Add App"))
            .accessibilityLabel(tr("添加应用", "Add App"))

            Button {
                if let selectedRule {
                    ruleStore.remove(bundleIdentifier: selectedRule.bundleIdentifier)
                    selection = nil
                }
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedRule == nil)
            .help(tr("删除选中的应用", "Remove the selected app"))
            .accessibilityLabel(tr("删除选中的应用", "Remove the selected app"))

            Spacer()

            Text(tr("未列出的应用保持系统默认行为", "Apps not listed keep system defaults"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showingAppLibrary) {
            AppLibraryPicker { app in
                ruleStore.upsert(AppRule(
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.name
                ))
            }
        }
    }
}

/// One row of the rule table: app name plus one action picker per traffic
/// light, each marked with a dot in the button's own color. A disclosure
/// chevron expands the enhanced click-variant matrix (right click, ⌥/🌐
/// clicks, long press).
private struct RuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    @State private var isExpanded = false

    /// The app's icon resolved from its bundle identifier on disk; falls
    /// back to the generic application icon when the app is missing (e.g.
    /// uninstalled since the rule was created).
    private var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// Every action is available on every button; the default entry keeps
    /// the system behavior. Menus render grouped window ops first.
    static let options: [ButtonAction?] = [
        nil,
        .closeWindow,
        .quitApp,
        .minimize,
        .hideApp,
        .maximize,
        .almostMaximize,
        .fullscreen,
        .tileLeft,
        .tileRight,
        .tileTop,
        .tileBottom,
        .tileTopLeft,
        .tileTopRight,
        .tileBottomLeft,
        .tileBottomRight,
        .centerWindow,
        .moveToNextDisplay,
        ButtonAction.none,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                disclosureButton

                HStack(spacing: 8) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(rule.displayName)
                        .font(.body)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ActionPicker(
                    dotColor: .systemRed,
                    options: Self.options,
                    selection: binding(button: .close, variant: .left)
                )
                ActionPicker(
                    dotColor: .systemYellow,
                    options: Self.options,
                    selection: binding(button: .minimize, variant: .left)
                )
                ActionPicker(
                    dotColor: .systemGreen,
                    options: Self.options,
                    selection: binding(button: .zoom, variant: .left)
                )

                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            }
            .padding(.vertical, 2)

            if isExpanded {
                variantMatrix
            }
        }
    }

    /// The enhanced click-variant slots: one row per variant, three compact
    /// pickers per row (red / yellow / green).
    private var variantMatrix: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ClickVariant.extraSlots, id: \.rawValue) { variant in
                HStack(spacing: 12) {
                    Text(variant.localizedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .trailing)
                    ActionPicker(
                        dotColor: .systemRed,
                        options: Self.options,
                        selection: binding(button: .close, variant: variant),
                        pickerWidth: 62
                    )
                    .controlSize(.small)
                    ActionPicker(
                        dotColor: .systemYellow,
                        options: Self.options,
                        selection: binding(button: .minimize, variant: variant),
                        pickerWidth: 62
                    )
                    .controlSize(.small)
                    ActionPicker(
                        dotColor: .systemGreen,
                        options: Self.options,
                        selection: binding(button: .zoom, variant: variant),
                        pickerWidth: 62
                    )
                    .controlSize(.small)
                }
            }
            Text(tr(
                "留空保持默认；配置长按后，该按钮的普通点击也会由 Blinker 接管。",
                "Leave empty for defaults; with a long press set, "
                    + "plain clicks on that button are handled by Blinker too."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 88)
        }
        .padding(.leading, 4)
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .buttonStyle(.borderless)
        .help(tr("更多点击方式", "More click variants"))
        .accessibilityLabel(tr("更多点击方式", "More click variants"))
        .accessibilityValue(isExpanded ? tr("已展开", "Expanded") : tr("已折叠", "Collapsed"))
    }

    private func binding(button: TrafficButton, variant: ClickVariant) -> Binding<ButtonAction?> {
        Binding(
            get: { rule.action(for: button, variant: variant) },
            set: { newValue in
                var updated = rule
                updated.setAction(newValue, button: button, variant: variant)
                onUpdate(updated)
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { newValue in
                var updated = rule
                updated.isEnabled = newValue
                onUpdate(updated)
            }
        )
    }
}
