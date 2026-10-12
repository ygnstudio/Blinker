import BlinkerCore
import SwiftUI

/// Global behavior is configuration, not a synthetic application rule.
struct GlobalRulesView: View {
    @Environment(\.eclipsePalette) private var palette
    @EnvironmentObject private var store: RuleStore
    @AppStorage("eclipse.defaults.variant") private var variant = ClickVariant.left
    @AppStorage("eclipse.defaults.preview") private var showsPreview = true
    @State private var previewButton = TrafficButton.zoom

    private var defaults: GlobalButtonRules { store.globalDefaults }

    private var actionCount: Int {
        TrafficButton.allCases.reduce(0) { count, button in
            count + ClickVariant.allCases.filter { defaults.action(for: button, variant: $0) != nil }.count
        }
    }

    private var previewAction: ButtonAction? {
        defaults.action(for: previewButton, variant: variant)
            ?? (variant == .longPressLeft ? defaults.action(for: previewButton, variant: .left) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "macwindow").font(.system(size: 26)).foregroundStyle(EclipseTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("默认行为").font(.system(size: 18, weight: .medium))
                    Text("适用于未配置的应用，以及选择沿用默认的按钮。")
                        .font(.caption).foregroundStyle(EclipseTheme.secondary)
                }
                Spacer(minLength: 8)
                Button(showsPreview ? "收起预览" : "显示预览", systemImage: "sidebar.right") {
                    showsPreview.toggle()
                }.buttonStyle(EclipseWorkbenchButtonStyle())
            }
            GeometryReader { geometry in
                ScrollView {
                    if geometry.size.width >= 680 && showsPreview {
                        HStack(alignment: .top, spacing: 22) {
                            editor.frame(maxWidth: .infinity)
                            preview.frame(width: 228)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            editor
                            if showsPreview { preview.frame(maxWidth: 340) }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            HStack {
                Label("\(actionCount) 项默认动作", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
                Spacer()
                Button("撤销修改") { store.undo() }
                    .buttonStyle(EclipseWorkbenchButtonStyle(role: .quiet))
                    .disabled(!store.canUndo || store.isReadOnly)
                Button("恢复系统行为") { store.updateGlobalDefaults(GlobalButtonRules()) }
                    .buttonStyle(EclipseWorkbenchButtonStyle())
                    .disabled(actionCount == 0 || store.isReadOnly)
            }.padding(.vertical, 10)
        }
        .padding(.top, 4)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            RuleTriggerPicker(variant: $variant)
            VStack(spacing: 0) {
                ForEach(TrafficButton.allCases, id: \.self) { button in
                    RuleBindingRow(button: button, variant: variant,
                                   detail: defaultDescription(button), allowsInheritance: false,
                                   binding: binding(button))
                }
            }

            Label("应用里的指定动作、系统行为和停用设置优先于这里。旧规则保持原样。",
                  systemImage: "info.circle")
                .font(.callout).foregroundStyle(EclipseTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if variant == .longPressLeft {
                Text("长按未配置时按普通单击处理。原生按钮识别长按还需要普通单击有动作。")
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
            }
            Text("修改立即保存，可撤销。预览不会移动、关闭或退出任何应用。")
                .font(.caption).foregroundStyle(EclipseTheme.secondary)
        }
        .disabled(store.isReadOnly)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("默认动作预览").font(.system(size: 12, weight: .semibold))
            RulePreviewButtonPicker(selection: $previewButton)
            RuleWindowDiagram(action: previewAction, appName: "应用窗口").frame(height: 126)
            Text(defaultDescription(previewButton)).font(.callout)
            Text("配置示意，不会操作实际窗口。")
                .font(.caption).foregroundStyle(EclipseTheme.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func defaultDescription(_ button: TrafficButton) -> String {
        if let action = defaults.action(for: button, variant: variant) { return action.localizedLabel }
        if variant == .longPressLeft {
            return "按普通单击处理：\(defaults.action(for: button, variant: .left)?.localizedLabel ?? "系统行为")"
        }
        if variant == .left { return "保留系统按钮行为" }
        return "未配置；原生按钮交由系统，悬浮按钮不执行操作"
    }

    private func binding(_ button: TrafficButton) -> Binding<RuleActionBinding> {
        Binding(get: {
            defaults.action(for: button, variant: variant).map(RuleActionBinding.action) ?? .system
        },
                set: { value in
                    previewButton = button
                    var updated = defaults
                    switch value {
                    case let .action(action): updated.setAction(action, button: button, variant: variant)
                    case .system: updated.setAction(nil, button: button, variant: variant)
                    case .inherit: return
                    }
                    store.updateGlobalDefaults(updated)
                })
    }
}
