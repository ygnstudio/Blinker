import AppKit
import BlinkerCore
import SwiftUI

/// A real rule editor. The adjacent diagram never performs a system action.
struct RuleInspectorView: View {
    @Environment(\.eclipsePalette) private var palette
    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var permissions: PermissionController
    @EnvironmentObject private var interception: InterceptionCoordinator
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    var onInspect: () -> Void = {}
    var isFilteredOut = false
    @AppStorage("eclipse.ruleInspector.preview") private var showsPreview = true
    @AppStorage("eclipse.ruleInspector.module") private var module = "window"
    @AppStorage("eclipse.ruleInspector.variant") private var variant = ClickVariant.left
    @State private var previewButton = TrafficButton.zoom
    @State private var previewResult: String?
    @State private var inspectionID: UUID?
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack {
                RuleModuleTabs(selection: $module)
                Spacer()
                Text(interception.status.localizedLabel)
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
            }
            GeometryReader { geometry in
                ScrollView {
                    if geometry.size.width >= 630 && showsPreview {
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
            footer
        }
        .padding(.top, 4)
        .onChange(of: rule) { _, _ in invalidatePreview() }
        .onChange(of: store.globalDefaults) { _, _ in invalidatePreview() }
        .onChange(of: interception.status) { _, _ in invalidatePreview() }
        .onChange(of: variant) { _, _ in invalidatePreview() }
        .onChange(of: previewButton) { _, _ in invalidatePreview() }
        .onChange(of: module) { _, _ in invalidatePreview() }
        .onDisappear { invalidatePreview() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconStore.icon(forBundleIdentifier: rule.id))
                .resizable().frame(width: 34, height: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName).font(.system(size: 18, weight: .medium)).lineLimit(1)
                    .help(rule.displayName)
                Text(rule.id).font(.caption).foregroundStyle(EclipseTheme.secondary)
                    .textSelection(.enabled).lineLimit(1).help(rule.id)
            }
            Spacer()
            Button {
                showsPreview.toggle()
            } label: {
                Label(showsPreview ? "收起预览" : "显示预览", systemImage: "sidebar.right")
            }
            .buttonStyle(EclipseWorkbenchButtonStyle())
            .accessibilityIdentifier("workbench.previewToggle")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(module == "hover" ? "此应用的悬停设置" : ruleScopeDescription)
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
                Spacer()
                if module == "window" {
                    Button("所有按钮沿用默认", action: inheritAllActions)
                        .buttonStyle(.borderless).font(.caption)
                        .disabled(rule.inheritedSlots == RuleActionSlot.all || store.isReadOnly)
                }
            }
            if module == "hover" {
                Toggle("允许此应用显示悬停按钮", isOn: binding(\.isHoverEnabled))
                Text("悬停与按钮规则独立。最终是否显示还取决于全局开关、作用范围和辅助功能权限。")
                    .font(.callout).foregroundStyle(EclipseTheme.secondary)
                Button("打开悬停测试窗口…") { CompatibilityWindowController.shared.showTestWindow() }
                Text("测试窗口用于检查悬停位置与交互，不代表当前应用规则已执行。")
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
            } else {
                Toggle("启用按钮规则", isOn: binding(\.isEnabled))
                RuleTriggerPicker(variant: $variant)
                VStack(spacing: 0) {
                    ForEach(TrafficButton.allCases, id: \.self) { button in
                        RuleBindingRow(button: button, variant: variant,
                                       detail: RulePreviewPresentation.source(
                                        rule: rule, defaults: store.globalDefaults,
                                        button: button, variant: variant
                                       ), binding: actionBinding(button))
                    }
                }

                Text(variantHelp).font(.caption).foregroundStyle(EclipseTheme.secondary)
                if !permissions.accessibilityGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("可继续编辑；授予辅助功能权限后，窗口规则才能执行。")
                            .font(.system(size: 11))
                        Button("查看权限与诊断", action: onInspect)
                            .buttonStyle(.borderless).font(.system(size: 11))
                    }
                    .padding(.top, 4).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .disabled(store.isReadOnly)
        .toggleStyle(EclipseToggleStyle())
        .controlSize(.regular)
    }

    private var ruleScopeDescription: String {
        store.rules.contains { $0.id == rule.id } ? "应用专属规则" : "未单独配置 · 沿用默认行为"
    }

    private var previewAction: ButtonAction? {
        RulePreviewPresentation.resolvedAction(rule: rule, defaults: store.globalDefaults,
                                               button: previewButton, variant: variant)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("配置预览").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("示意").font(.caption).foregroundStyle(EclipseTheme.secondary)
            }
            if module == "hover" {
                Label(rule.isHoverEnabled ? "此应用允许悬停按钮" : "此应用不显示悬停按钮",
                      systemImage: rule.isHoverEnabled ? "cursorarrow.rays" : "cursorarrow.slash")
                    .font(.callout)
                Text("这是此应用的显示许可。实际显示还取决于全局开关、作用范围和辅助功能权限。")
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
            } else {
                RulePreviewButtonPicker(selection: $previewButton)
                RuleWindowDiagram(action: previewAction, appName: rule.displayName).frame(height: 126)
                Text("\(RulePreviewPresentation.name(previewButton)) · \(variant.localizedLabel)")
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
                Text(RulePreviewPresentation.summary(rule: rule, defaults: store.globalDefaults,
                                                     button: previewButton, variant: variant))
                    .font(.callout)
                VStack(alignment: .leading, spacing: 5) {
                    Text("生效来源").font(.system(size: 11)).foregroundStyle(palette.secondary)
                    Text(RulePreviewPresentation.source(rule: rule, defaults: store.globalDefaults,
                                                        button: previewButton, variant: variant))
                        .font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
                Text("配置示意，不会操作实际窗口。")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
            Button("检查兼容性", action: onInspect)
                .buttonStyle(EclipseWorkbenchButtonStyle(role: .quiet))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFilteredOut {
                Text("当前应用不在筛选结果中，仍可继续编辑。")
                    .font(.caption).foregroundStyle(EclipseTheme.accent)
            }
            if let previewResult {
                Text(previewResult).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("workbench.previewResult")
            }
            HStack(spacing: 12) {
                Text(isChecking ? "检查目标窗口…" : "修改自动保存")
                    .font(.caption).foregroundStyle(EclipseTheme.secondary)
                Spacer()
                Button("撤销修改") { store.undo() }
                    .buttonStyle(EclipseWorkbenchButtonStyle(role: .quiet))
                    .disabled(!store.canUndo || store.isReadOnly)
                Button("检查目标窗口", systemImage: "viewfinder", action: preflight)
                    .buttonStyle(EclipseWorkbenchButtonStyle(role: .primary))
                    .disabled(isChecking || module != "window")
            }
        }
        .padding(.vertical, 10)
    }

    private var variantHelp: String {
        switch variant {
        case .left: "沿用默认会随默认行为更新；系统行为与指定动作只影响此应用。「无操作」会拦截点击。"
        case .longPressLeft: "长按未配置时按普通单击处理。原生按钮要识别长按，也需配置普通单击动作。"
        default: "未配置时，原生按钮交由系统处理，悬浮按钮不执行操作。"
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppRule, Value>) -> Binding<Value> {
        Binding(get: { rule[keyPath: keyPath] }, set: { value in
            var updated = rule
            updated[keyPath: keyPath] = value
            onUpdate(updated)
        })
    }

    private func actionBinding(_ button: TrafficButton) -> Binding<RuleActionBinding> {
        Binding(get: { rule.binding(for: button, variant: variant) }, set: { value in
            previewButton = button
            var updated = rule
            updated.setBinding(value, button: button, variant: variant)
            onUpdate(updated)
        })
    }

    private func inheritAllActions() {
        var updated = rule
        for button in TrafficButton.allCases {
            for trigger in ClickVariant.allCases {
                updated.setBinding(.inherit, button: button, variant: trigger)
            }
        }
        onUpdate(updated)
    }

    private func invalidatePreview() {
        inspectionID = nil
        isChecking = false
        previewResult = nil
    }

    private func preflight() {
        let request = UUID()
        inspectionID = request
        isChecking = true
        previewResult = nil
        let summary = RulePreviewPresentation.summary(rule: rule, defaults: store.globalDefaults,
                                                      button: previewButton, variant: variant)
        WindowCompatibility.inspect(bundleID: rule.id) { report in
            guard inspectionID == request else { return }
            inspectionID = nil
            isChecking = false
            let status: String
            if !report.permissionGranted {
                status = "需要辅助功能权限。"
            } else if !report.windowFound {
                status = "没有找到目标窗口，请先打开该应用的窗口。"
            } else {
                status = "已找到目标窗口；尚未执行任何操作。"
            }
            previewResult = "\(summary) \(status)"
        }
    }
}
