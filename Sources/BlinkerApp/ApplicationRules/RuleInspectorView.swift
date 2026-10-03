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
                Toggle("允许此应用显示悬停按钮", isOn: binding(\.isHoverEnabled))
            } header: {
                Text("启用选项")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("两个开关独立，关闭后保留配置。悬停按钮还受全局开关和作用范围控制。")
                    Text("应用标识：\(rule.bundleIdentifier)")
                        .textSelection(.enabled)
                }
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
                    Section(label) { options(group.options, for: variant) }
                } else {
                    options(group.options, for: variant)
                }
            }
        }
        .accessibilityLabel("\(name)，\(variant.localizedLabel)")
        .help(help(for: variant))
    }

    private func options(_ actions: [ButtonAction?], for variant: ClickVariant) -> some View {
        ForEach(actions, id: \.self) { action in
            Text(action?.localizedLabel ?? (variant == .left
                    ? String(localized: "系统默认") : String(localized: "未配置")))
                .tag(action)
        }
    }

    private func help(for variant: ClickVariant) -> String {
        switch variant {
        case .left:
            String(localized: "系统默认会执行原生按钮动作；选择「无操作」会拦截左键点击。")
        case .longPressLeft:
            String(localized: "未配置时按普通左键处理。要在原生按钮上使用长按，也需配置左键动作。")
        case .right, .optionLeft, .globeLeft:
            String(localized: "未配置时，原生按钮交由系统处理，悬浮按钮不执行操作；「无操作」会拦截该点击。")
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
