import BlinkerCore
import SwiftUI

/// The settings window: per-app remapping of the red and green buttons.
struct SettingsScreen: View {
    @ObservedObject var ruleStore: RuleStore

    var body: some View {
        VStack(spacing: 0) {
            if ruleStore.rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 380)
    }

    // MARK: - Sections

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

    private var footer: some View {
        HStack {
            Menu {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Button(app.name) {
                        ruleStore.upsert(AppRule(
                            bundleIdentifier: app.bundleIdentifier,
                            displayName: app.name
                        ))
                    }
                }
            } label: {
                Label("添加应用", systemImage: "plus")
            }
            .disabled(runningApps.isEmpty)
            Spacer()
            Text("未列出的应用保持系统默认行为")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private struct RunningApp: Identifiable {
        var id: String { bundleIdentifier }
        let bundleIdentifier: String
        let name: String
    }

    private var runningApps: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { app in
                guard
                    let bundleIdentifier = app.bundleIdentifier,
                    bundleIdentifier != Bundle.main.bundleIdentifier
                else { return nil }
                return RunningApp(
                    bundleIdentifier: bundleIdentifier,
                    name: app.localizedName ?? bundleIdentifier
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// One row of the rule table: app name plus the two action pickers.
private struct RuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    let onRemove: () -> Void

    static let closeOptions: [ButtonAction?] = [
        nil, .closeWindow, .quitApp, .minimize, .hideApp, ButtonAction.none
    ]
    static let zoomOptions: [ButtonAction?] = [
        nil, .maximize, .fullscreen, .tileLeft, .tileRight, ButtonAction.none
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
