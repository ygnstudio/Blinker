import BlinkerCore
import SwiftUI

/// The settings window, organized into tabs: per-app rules, hover overlay
/// configuration, general preferences and an about page.
struct SettingsScreen: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var hoverSettingsStore: HoverOverlaySettingsStore
    let onApplyHoverSettings: (HoverOverlaySettings) -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        TabView {
            RulesTab(ruleStore: ruleStore)
                .tabItem { Label(tr("规则", "Rules"), systemImage: "list.bullet.rectangle") }
            HoverSettingsTab(store: hoverSettingsStore, onApply: onApplyHoverSettings)
                .tabItem {
                    Label(
                        tr("悬停放大", "Hover"),
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                }
            GeneralTab()
                .tabItem { Label(tr("通用", "General"), systemImage: "gearshape") }
            AboutTab()
                .tabItem { Label(tr("关于", "About"), systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
        .preferredColorScheme(preferences.appearance.resolvedScheme)
    }
}

/// Localized label for a remappable action, shared by every picker.
extension ButtonAction {
    var localizedLabel: String {
        switch self {
        case .closeWindow: tr("关闭窗口", "Close Window")
        case .quitApp: tr("退出应用", "Quit App")
        case .minimize: tr("最小化", "Minimize")
        case .hideApp: tr("隐藏应用", "Hide App")
        case .maximize: tr("最大化", "Maximize")
        case .fullscreen: tr("全屏", "Fullscreen")
        case .tileLeft: tr("左半屏", "Tile Left")
        case .tileRight: tr("右半屏", "Tile Right")
        case .tileTop: tr("上半屏", "Tile Top")
        case .tileBottom: tr("下半屏", "Tile Bottom")
        case .tileTopLeft: tr("左上屏", "Tile Top Left")
        case .tileTopRight: tr("右上屏", "Tile Top Right")
        case .tileBottomLeft: tr("左下屏", "Tile Bottom Left")
        case .tileBottomRight: tr("右下屏", "Tile Bottom Right")
        case .centerWindow: tr("窗口居中", "Center")
        case .almostMaximize: tr("准最大化", "Almost Maximize")
        case .moveToNextDisplay: tr("移到下一显示器", "Next Display")
        case .none: tr("无操作", "Do Nothing")
        }
    }
}

// MARK: - Rules tab

/// Per-app remapping of the traffic light buttons.
private struct RulesTab: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var showingAppLibrary = false

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
        List {
            ForEach(ruleStore.rules) { rule in
                RuleRowView(
                    rule: rule,
                    onUpdate: { ruleStore.upsert($0) },
                    onRemove: { ruleStore.remove(bundleIdentifier: rule.bundleIdentifier) }
                )
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "circle.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(tr("还没有配置任何应用", "No apps configured yet"))
                .font(.headline)
            Text(
                tr(
                    "添加应用后，即可单独定义它的红绿灯行为；\n未添加的应用保持系统默认。",
                    "Add an app to remap its traffic lights;\neverything else keeps system defaults."
                )
            )
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
                Label(tr("添加应用", "Add App"), systemImage: "plus")
            }
            .fixedSize()
            Spacer()
            Text(tr("未列出的应用保持系统默认行为", "Apps not listed keep system defaults"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
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
/// light, each marked with a dot in the button's own color.
private struct RuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    let onRemove: () -> Void

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .font(.body)
                Text(rule.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ActionPicker(
                dotColor: .systemRed,
                options: Self.options,
                selection: closeBinding
            )
            ActionPicker(
                dotColor: .systemYellow,
                options: Self.options,
                selection: minimizeBinding
            )
            ActionPicker(
                dotColor: .systemGreen,
                options: Self.options,
                selection: zoomBinding
            )

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)

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
}

/// A traffic-light action picker: a dot in the button's color followed by
/// the action menu, so each row's three pickers are self-explanatory.
private struct ActionPicker: View {
    let dotColor: NSColor
    let options: [ButtonAction?]
    @Binding var selection: ButtonAction?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(nsColor: dotColor))
                .frame(width: 9, height: 9)
            Picker(selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, action in
                    Text(Self.label(for: action)).tag(action)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .frame(width: 84)
        }
    }

    private static func label(for action: ButtonAction?) -> String {
        guard let action else { return tr("默认", "Default") }
        return action.localizedLabel
    }
}

// MARK: - Hover tab

/// Hover overlay configuration: master switch, mode, enlarged size,
/// anti-mistouch dwell and scope, bound to `HoverOverlaySettingsStore`.
private struct HoverSettingsTab: View {
    @ObservedObject var store: HoverOverlaySettingsStore
    let onApply: (HoverOverlaySettings) -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    private var settings: HoverOverlaySettings {
        store.settings
    }

    var body: some View {
        Form {
            Section {
                Toggle(tr("启用悬停放大", "Enable Hover Enlargement"), isOn: isEnabledBinding)
                modePicker
            } header: {
                Text(tr("模式与尺寸", "Mode & Size"))
            } footer: {
                Text(tr(
                    "开启后，鼠标悬停到窗口红绿灯按钮上会临时放大，点击即执行对应动作。",
                    "When enabled, hovering a window's traffic lights enlarges them;"
                        + " clicking performs the mapped action."
                ))
                Text(modeHint)
            }

            Section {
                sizeSlider
                dwellSlider
            } header: {
                Text(tr("放大参数", "Enlargement"))
            }

            Section {
                maskStylePicker
                scopePicker
            } header: {
                Text(tr("遮挡与范围", "Mask & Scope"))
            } footer: {
                Text(maskStyleHint)
            }
        }
        .formStyle(.grouped)
        .disabled(!settings.isEnabled)
    }

    private var modePicker: some View {
        Picker(tr("模式", "Mode"), selection: modeBinding) {
            Text(tr("覆盖放大", "Overlay")).tag(HoverOverlayMode.overlay)
            Text(tr("纯热区", "Hotspot")).tag(HoverOverlayMode.hotspot)
        }
        .pickerStyle(.segmented)
    }

    private var sizeSlider: some View {
        LabeledContent(tr("放大尺寸", "Enlarged Size")) {
            Slider(value: enlargedSizeBinding, in: 28 ... 48, step: 1)
                .frame(width: 200)
            Text("\(Int(settings.enlargedSize)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var dwellSlider: some View {
        LabeledContent(tr("防误触延迟", "Dwell Delay")) {
            Slider(value: dwellBinding, in: 0 ... 800, step: 50)
                .frame(width: 200)
                .disabled(settings.mode == .hotspot)
            Text(dwellLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var maskStylePicker: some View {
        Picker(tr("按钮遮挡", "Button Mask"), selection: maskStyleBinding) {
            Text(tr("液态玻璃", "Liquid Glass")).tag(HoverOverlayMaskStyle.glass)
            Text(tr("真实采样", "Sampled")).tag(HoverOverlayMaskStyle.sampled)
        }
        .disabled(settings.mode == .hotspot)
    }

    private var scopePicker: some View {
        Picker(tr("作用范围", "Scope"), selection: appliesToAllWindowsBinding) {
            Text(tr("全部窗口", "All Windows")).tag(true)
            Text(tr("仅规则应用", "Rule Apps Only")).tag(false)
        }
    }

    private var dwellLabel: String {
        if settings.mode == .hotspot {
            return tr("不适用", "N/A")
        }
        return settings.dwellMilliseconds == 0
            ? tr("立即响应", "Immediate")
            : "\(settings.dwellMilliseconds) ms"
    }

    private var modeHint: String {
        switch settings.mode {
        case .overlay:
            tr(
                "覆盖放大：红绿灯上方绘制液态玻璃质感的放大按钮，带防误触进度环。",
                "Overlay draws Liquid Glass buttons above the traffic lights with a dwell ring."
            )
        case .hotspot:
            tr(
                "纯热区：界面外观完全不变，仅在按钮周围扩大不可见点击区，点击立即响应。",
                "Hotspot keeps the title bar unchanged and only enlarges the invisible click zones."
            )
        }
    }

    private var maskStyleHint: String {
        guard settings.mode == .overlay else {
            return tr("纯热区模式不显示遮罩。", "Hotspot mode shows no mask.")
        }
        switch settings.maskStyle {
        case .glass:
            return tr(
                "液态玻璃：以系统玻璃模糊遮挡原生按钮，无需额外权限。",
                "Liquid Glass covers the native buttons with a system blur; no extra permission."
            )
        case .sampled:
            if TitlebarSampler.hasScreenCapturePermission() {
                return tr(
                    "真实采样：遮挡区域显示窗口标题栏的真实背景，效果完全隐形。",
                    "Sampled shows the real title-bar backdrop — fully invisible."
                )
            }
            return tr(
                "真实采样需要「屏幕录制」权限：授权后自动生效，未授权时回退液态玻璃。",
                "Sampled needs Screen Recording permission; without it the glass mask is used."
            )
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

    private var maskStyleBinding: Binding<HoverOverlayMaskStyle> {
        Binding(
            get: { settings.maskStyle },
            set: { newValue in
                if newValue == .sampled, !TitlebarSampler.hasScreenCapturePermission() {
                    // Only prompt when the user opts in to sampling.
                    TitlebarSampler.requestScreenCapturePermission()
                }
                update { $0.maskStyle = newValue }
            }
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
