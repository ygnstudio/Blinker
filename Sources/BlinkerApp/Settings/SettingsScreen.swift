import BlinkerCore
import SwiftUI

/// The settings window, organized into tabs: per-app rules, hover overlay
/// configuration and an about page.
struct SettingsScreen: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var hoverSettingsStore: HoverOverlaySettingsStore
    let onApplyHoverSettings: (HoverOverlaySettings) -> Void

    var body: some View {
        TabView {
            RulesTab(ruleStore: ruleStore)
                .tabItem { Label("规则", systemImage: "list.bullet.rectangle") }
            HoverSettingsTab(store: hoverSettingsStore, onApply: onApplyHoverSettings)
                .tabItem { Label("悬停放大", systemImage: "arrow.up.left.and.arrow.down.right") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 440)
    }
}

// MARK: - Rules tab

/// Per-app remapping of the traffic light buttons.
private struct RulesTab: View {
    @ObservedObject var ruleStore: RuleStore
    @State private var showingAppLibrary = false

    var body: some View {
        VStack(spacing: 12) {
            if ruleStore.rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
            footerBar
                .liquidGlassCard()
        }
        .padding(12)
    }

    private var ruleList: some View {
        List {
            ForEach(ruleStore.rules) { rule in
                RuleRowView(
                    rule: rule,
                    onUpdate: { ruleStore.upsert($0) },
                    onRemove: { ruleStore.remove(bundleIdentifier: rule.bundleIdentifier) }
                )
            }
        }
        .listStyle(.inset)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "circle.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("还没有配置任何应用")
                .font(.headline)
            Text("添加应用后，即可单独定义它的红绿灯行为；\n未添加的应用保持系统默认。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footerBar: some View {
        HStack {
            Button {
                showingAppLibrary = true
            } label: {
                Label("添加应用", systemImage: "plus")
            }
            .fixedSize()
            Spacer()
            Text("未列出的应用保持系统默认行为")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

/// One row of the rule table: app name plus the two action pickers.
private struct RuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    let onRemove: () -> Void

    static let closeOptions: [ButtonAction?] = [
        nil, .closeWindow, .quitApp, .minimize, .hideApp, ButtonAction.none,
    ]
    static let zoomOptions: [ButtonAction?] = [
        nil, .maximize, .fullscreen, .tileLeft, .tileRight, ButtonAction.none,
    ]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .font(.body)
                Text(rule.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("红灯", selection: closeBinding) {
                ForEach(Array(Self.closeOptions.enumerated()), id: \.offset) { _, action in
                    Text(Self.label(for: action)).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            Picker("绿灯", selection: zoomBinding) {
                ForEach(Array(Self.zoomOptions.enumerated()), id: \.offset) { _, action in
                    Text(Self.label(for: action)).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            Toggle("", isOn: enabledBinding)
                .labelsHidden()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var closeBinding: Binding<ButtonAction?> {
        Binding(
            get: { rule.closeAction },
            set: { newValue in
                var updated = rule
                updated.closeAction = newValue
                onUpdate(updated)
            }
        )
    }

    private var minimizeBinding: Binding<ButtonAction?> {
        Binding(
            get: { rule.minimizeAction },
            set: { newValue in
                var updated = rule
                updated.minimizeAction = newValue
                onUpdate(updated)
            }
        )
    }

    private var zoomBinding: Binding<ButtonAction?> {
        Binding(
            get: { rule.zoomAction },
            set: { newValue in
                var updated = rule
                updated.zoomAction = newValue
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

    private static func label(for action: ButtonAction?) -> String {
        guard let action else { return "默认" }
        switch action {
        case .closeWindow: return "关闭窗口"
        case .quitApp: return "退出应用"
        case .minimize: return "最小化"
        case .hideApp: return "隐藏应用"
        case .maximize: return "最大化"
        case .fullscreen: return "全屏"
        case .tileLeft: return "左半屏"
        case .tileRight: return "右半屏"
        case .none: return "无操作"
        }
    }
}

// MARK: - Hover tab

/// Hover overlay configuration: master switch, mode, enlarged size,
/// anti-mistouch dwell and scope, bound to `HoverOverlaySettingsStore`.
private struct HoverSettingsTab: View {
    @ObservedObject var store: HoverOverlaySettingsStore
    let onApply: (HoverOverlaySettings) -> Void

    private var settings: HoverOverlaySettings {
        store.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("启用悬停放大", isOn: isEnabledBinding)
            Text("开启后，鼠标悬停到窗口红绿灯按钮上会临时放大，点击即执行对应动作。")
                .font(.caption)
                .foregroundStyle(.secondary)

            modeRow
            Text(modeHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            sizeRow
            dwellRow
            scopeRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .liquidGlassCard()
        .padding(12)
    }

    private var modeRow: some View {
        HStack(spacing: 8) {
            Text("模式")
                .frame(width: 76, alignment: .leading)
            Picker("模式", selection: modeBinding) {
                Text("覆盖放大").tag(HoverOverlayMode.overlay)
                Text("纯热区").tag(HoverOverlayMode.hotspot)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(!settings.isEnabled)
            Spacer()
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 8) {
            Text("放大尺寸")
                .frame(width: 76, alignment: .leading)
            Slider(value: enlargedSizeBinding, in: 28 ... 48, step: 1)
                .disabled(!settings.isEnabled)
            Text("\(Int(settings.enlargedSize)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var dwellRow: some View {
        HStack(spacing: 8) {
            Text("防误触延迟")
                .frame(width: 76, alignment: .leading)
            Slider(value: dwellBinding, in: 0 ... 800, step: 50)
                .disabled(!settings.isEnabled || settings.mode == .hotspot)
            Text(dwellLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var scopeRow: some View {
        HStack(spacing: 8) {
            Text("作用范围")
                .frame(width: 76, alignment: .leading)
            Picker("作用范围", selection: appliesToAllWindowsBinding) {
                Text("全部窗口").tag(true)
                Text("仅规则应用").tag(false)
            }
            .labelsHidden()
            .frame(width: 140)
            Spacer()
        }
    }

    private var dwellLabel: String {
        if settings.mode == .hotspot {
            return "不适用"
        }
        return settings.dwellMilliseconds == 0 ? "立即响应" : "\(settings.dwellMilliseconds) 毫秒"
    }

    private var modeHint: String {
        switch settings.mode {
        case .overlay:
            "覆盖放大：红绿灯上方绘制液态玻璃质感的放大按钮，带防误触进度环。"
        case .hotspot:
            "纯热区：界面外观完全不变，仅在按钮周围扩大不可见点击区，点击立即响应。"
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in update { $0.isEnabled = newValue } }
        )
    }

    private var modeBinding: Binding<HoverOverlayMode> {
        Binding(
            get: { settings.mode },
            set: { newValue in update { $0.mode = newValue } }
        )
    }

    private var enlargedSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.enlargedSize) },
            set: { newValue in update { $0.enlargedSize = CGFloat(newValue) } }
        )
    }

    private var dwellBinding: Binding<Double> {
        Binding(
            get: { Double(settings.dwellMilliseconds) },
            set: { newValue in update { $0.dwellMilliseconds = Int(newValue) } }
        )
    }

    private var appliesToAllWindowsBinding: Binding<Bool> {
        Binding(
            get: { settings.appliesToAllWindows },
            set: { newValue in update { $0.appliesToAllWindows = newValue } }
        )
    }

    private func update(_ mutate: (inout HoverOverlaySettings) -> Void) {
        var updated = settings
        mutate(&updated)
        onApply(updated)
    }
}
