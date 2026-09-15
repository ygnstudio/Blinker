import AppKit
import BlinkerCore
import SwiftUI

/// Assembles the five settings tabs as a toolbar-style `NSTabViewController`,
/// so the tab row lives in the window's titlebar like System Settings rather
/// than floating inside the content area.
final class SettingsTabViewController: NSTabViewController {
    init(
        ruleStore: RuleStore,
        hoverSettingsStore: HoverOverlaySettingsStore,
        onApplyHoverSettings: @escaping (HoverOverlaySettings) -> Void,
        hotkeyManager: HotkeyManager,
        workspaceStore: WorkspaceStore,
        onSnapEnabledChange: @escaping (Bool) -> Void,
        appDelegate: AppDelegate
    ) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        canPropagateSelectedChildViewControllerTitle = false

        addTab(
            SettingsTabContent { RulesTab(ruleStore: ruleStore) },
            title: tr("规则", "Rules"),
            symbol: "list.bullet.rectangle"
        )
        addTab(
            SettingsTabContent {
                WindowManagementTab(
                    hotkeyManager: hotkeyManager,
                    workspaceStore: workspaceStore,
                    onSnapEnabledChange: onSnapEnabledChange
                )
            },
            title: tr("窗口管理", "Windows"),
            symbol: "rectangle.split.2x2"
        )
        addTab(
            SettingsTabContent {
                HoverSettingsTab(
                    store: hoverSettingsStore,
                    onApply: onApplyHoverSettings
                )
            },
            title: tr("悬停放大", "Hover"),
            symbol: "arrow.up.left.and.arrow.down.right"
        )
        addTab(
            SettingsTabContent { GeneralTab(appDelegate: appDelegate) },
            title: tr("通用", "General"),
            symbol: "gearshape"
        )
        addTab(
            SettingsTabContent { AboutTab() },
            title: tr("关于", "About"),
            symbol: "info.circle"
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func addTab<Content: View>(
        _ content: Content,
        title: String,
        symbol: String
    ) {
        let item = NSTabViewItem(
            viewController: NSHostingController(rootView: content)
        )
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }
}

/// Wraps a tab's content with the app-wide appearance override so every tab
/// follows the General tab's light/dark choice.
private struct SettingsTabContent<Content: View>: View {
    @ViewBuilder var content: Content
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        content
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
        case .windowManagerPanel: tr("窗口管理", "Window Manager")
        }
    }
}

/// Localized label for a click variant, shown in the rules matrix.
extension ClickVariant {
    var localizedLabel: String {
        switch self {
        case .left: tr("左键", "Left Click")
        case .right: tr("右键", "Right Click")
        case .optionLeft: "⌥ " + tr("+ 左键", "+ Left Click")
        case .globeLeft: "🌐 " + tr("+ 左键", "+ Left Click")
        case .longPressLeft: tr("长按", "Long Press")
        }
    }
}

// MARK: - Rules tab

/// Per-app remapping of the traffic light buttons.
struct RulesTab: View {
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
/// light, each marked with a dot in the button's own color. A disclosure
/// chevron expands the enhanced click-variant matrix (right click, ⌥/🌐
/// clicks, long press).
private struct RuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    let onRemove: () -> Void
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

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
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

/// A traffic-light action picker: a dot in the button's color followed by
/// the action menu, so each row's three pickers are self-explanatory.
struct ActionPicker: View {
    let dotColor: NSColor
    let options: [ButtonAction?]
    @Binding var selection: ButtonAction?
    /// Label for the `nil` option; traffic rows use "默认", extra-button
    /// rows use "不显示".
    var emptyLabel: String = tr("默认", "Default")
    /// Menu width; fits four CJK characters ("关闭窗口") without ellipsis.
    /// The compact variant matrix uses a narrower value.
    var pickerWidth: CGFloat = 100

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(nsColor: dotColor))
                .frame(width: 9, height: 9)
            Picker(selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, action in
                    Text(Self.label(for: action, emptyLabel: emptyLabel)).tag(action)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .frame(width: pickerWidth)
        }
    }

    private static func label(for action: ButtonAction?, emptyLabel: String) -> String {
        guard let action else { return emptyLabel }
        return action.localizedLabel
    }
}
