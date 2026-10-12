import BlinkerCore
import SwiftUI

struct RuleTriggerPicker: View {
    @Binding var variant: ClickVariant

    var body: some View {
        HStack {
            Text("触发方式").font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            Picker("触发方式", selection: $variant) {
                Text("普通单击").tag(ClickVariant.left)
                Text("右键").tag(ClickVariant.right)
                Text("Option + 单击").tag(ClickVariant.optionLeft)
                Text("Fn + 单击").tag(ClickVariant.globeLeft)
                Text("长按").tag(ClickVariant.longPressLeft)
            }
            .labelsHidden().font(.system(size: 12)).frame(width: 158)
        }
    }
}

/// One shared menu keeps default and per-app actions identical, including explicit no-op.
struct RuleBindingRow: View {
    let button: TrafficButton
    let variant: ClickVariant
    let detail: String
    var allowsInheritance = true
    @Binding var binding: RuleActionBinding

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(RulePreviewPresentation.name(button)).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(EclipseTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Picker(RulePreviewPresentation.name(button), selection: $binding) {
                if allowsInheritance { Text("沿用默认行为").tag(RuleActionBinding.inherit) }
                Text(systemLabel).tag(RuleActionBinding.system)
                ForEach(RuleActionOptions.groups.indices, id: \.self) { index in
                    let group = RuleActionOptions.groups[index]
                    if let title = group.label {
                        Section(title) { options(group.options) }
                    } else { options(group.options) }
                }
            }
            .labelsHidden().font(.system(size: 12)).frame(width: 158)
            .accessibilityIdentifier("workbench.action.\(button.rawValue)")
        }
        .padding(.vertical, 12)
    }

    private var systemLabel: String {
        switch variant {
        case .left: String(localized: "保留系统行为")
        case .longPressLeft: String(localized: "按普通单击处理")
        default: String(localized: "未配置（系统处理）")
        }
    }

    private func options(_ actions: [ButtonAction?]) -> some View {
        ForEach(actions.compactMap { $0 }, id: \.self) { action in
            Text(action.localizedLabel).tag(RuleActionBinding.action(action))
        }
    }
}

struct RulePreviewButtonPicker: View {
    @Environment(\.eclipsePalette) private var palette
    @Binding var selection: TrafficButton

    var body: some View {
        HStack(spacing: 3) {
            tab("关闭", button: .close)
            tab("最小化", button: .minimize)
            tab("绿色", button: .zoom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("预览按钮")
    }

    private func tab(_ title: String, button: TrafficButton) -> some View {
        Button { selection = button } label: {
            Text(title).font(.system(size: 11))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .foregroundStyle(selection == button ? palette.text : palette.secondary)
                .background(selection == button ? palette.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityValue(selection == button ? "已选择" : "")
        .accessibilityAddTraits(selection == button ? .isSelected : [])
    }
}

struct RuleModuleTabs: View {
    @Environment(\.eclipsePalette) private var palette
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            tab("窗口", value: "window")
            tab("悬停", value: "hover")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("规则类别")
    }

    private func tab(_ title: String, value: String) -> some View {
        Button { selection = value } label: {
            Text(title).font(.system(size: 12))
                .foregroundStyle(selection == value ? palette.text : palette.secondary)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(selection == value ? palette.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityValue(selection == value ? "已选择" : "")
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
