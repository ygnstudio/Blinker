import BlinkerCore
import SwiftUI

/// Standard form controls keep selection, focus, and menus consistent with macOS.
struct RuleInspectorView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void

    var body: some View {
        Form {
            Section {
                Toggle("启用按钮规则", isOn: binding(\.isEnabled))
            } footer: {
                Text(rule.isEnabled
                    ? String(localized: "更改立即生效。未配置的按钮保持系统默认行为。")
                    : String(localized: "规则已停用。配置会保留，启用后生效。"))
            }
            Section {
                Toggle("启用此应用的悬停放大", isOn: binding(\.isHoverEnabled))
            } footer: {
                Text("独立于按钮规则；还需在设置中开启悬停放大。")
            }
            ForEach(TrafficButton.allCases, id: \.self) { button in
                TrafficButtonEditor(
                    button: button,
                    rule: rule,
                    onUpdate: onUpdate
                )
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppRule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { newValue in
                var updated = rule
                updated[keyPath: keyPath] = newValue
                onUpdate(updated)
            }
        )
    }
}

private struct TrafficButtonEditor: View {
    let button: TrafficButton
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    @State private var showsMore = false

    private var name: String {
        switch button {
        case .close: String(localized: "关闭按钮")
        case .minimize: String(localized: "最小化按钮")
        case .zoom: String(localized: "缩放按钮")
        }
    }

    private var color: Color {
        switch button {
        case .close: .red
        case .minimize: .yellow
        case .zoom: .green
        }
    }

    private var hasExtraActions: Bool {
        ClickVariant.extraSlots.contains { rule.action(for: button, variant: $0) != nil }
    }

    var body: some View {
        Section {
            actionPicker(for: .left)
            DisclosureGroup("更多点击方式", isExpanded: $showsMore) {
                ForEach(ClickVariant.extraSlots, id: \.rawValue) { variant in
                    actionPicker(for: variant)
                }
            }
        } header: {
            Label {
                Text(name)
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { showsMore = hasExtraActions }
        .onChange(of: hasExtraActions) {
            if hasExtraActions {
                showsMore = true
            }
        }
    }

    private func actionPicker(for variant: ClickVariant) -> some View {
        Picker(variant.localizedLabel, selection: binding(for: variant)) {
            ForEach(RuleActionOptions.groups.indices, id: \.self) { index in
                let group = RuleActionOptions.groups[index]
                if let label = group.label {
                    Section(label) { options(group.options) }
                } else {
                    options(group.options)
                }
            }
        }
        .accessibilityLabel("\(name)，\(variant.localizedLabel)")
    }

    private func options(_ actions: [ButtonAction?]) -> some View {
        ForEach(actions, id: \.self) { action in
            Text(action?.localizedLabel ?? String(localized: "系统默认"))
                .tag(action)
        }
    }

    private func binding(for variant: ClickVariant) -> Binding<ButtonAction?> {
        Binding(
            get: { rule.action(for: button, variant: variant) },
            set: { newValue in
                var updated = rule
                updated.setAction(newValue, button: button, variant: variant)
                onUpdate(updated)
            }
        )
    }
}
