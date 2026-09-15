import AppKit
import BlinkerCore
import Combine
import SwiftUI

/// Assembles the five settings tabs as a toolbar-style `NSTabViewController`,
/// so the tab row lives in the window's titlebar like System Settings rather
/// than floating inside the content area.
///
/// Tab titles are AppKit-side (`NSTabViewItem.label`), so they don't react to
/// the SwiftUI language preference on their own. The controller therefore
/// keeps the child view controllers alive and re-wraps them in fresh tab
/// items whenever the language changes — `@State` inside each tab survives.
final class SettingsTabViewController: NSTabViewController {
    private struct TabSpec {
        let viewController: NSViewController
        let chineseTitle: String
        let englishTitle: String
        let symbol: String
    }

    private var specs: [TabSpec] = []
    private var languageCancellable: AnyCancellable?

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
        specs = [
            rulesSpec(ruleStore: ruleStore, hoverStore: hoverSettingsStore),
            windowManagementSpec(
                hotkeyManager: hotkeyManager,
                workspaceStore: workspaceStore,
                onSnapEnabledChange: onSnapEnabledChange,
                hoverStore: hoverSettingsStore
            ),
            hoverSpec(
                hoverSettingsStore: hoverSettingsStore,
                onApplyHoverSettings: onApplyHoverSettings
            ),
            generalSpec(
                appDelegate: appDelegate,
                hoverStore: hoverSettingsStore,
                onApplyHoverSettings: onApplyHoverSettings
            ),
            aboutSpec(hoverStore: hoverSettingsStore),
        ]
        rebuildTabs()

        languageCancellable = AppPreferences.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildTabs() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func rulesSpec(ruleStore: RuleStore, hoverStore: HoverOverlaySettingsStore) -> TabSpec {
        TabSpec(
            viewController: NSHostingController(
                rootView: SettingsTabContent(store: hoverStore) { RulesTab(ruleStore: ruleStore) }
            ),
            chineseTitle: "规则",
            englishTitle: "Rules",
            symbol: "list.bullet.rectangle"
        )
    }

    private func windowManagementSpec(
        hotkeyManager: HotkeyManager,
        workspaceStore: WorkspaceStore,
        onSnapEnabledChange: @escaping (Bool) -> Void,
        hoverStore: HoverOverlaySettingsStore
    ) -> TabSpec {
        TabSpec(
            viewController: NSHostingController(
                rootView: SettingsTabContent(store: hoverStore) {
                    WindowManagementTab(
                        hotkeyManager: hotkeyManager,
                        workspaceStore: workspaceStore,
                        onSnapEnabledChange: onSnapEnabledChange
                    )
                }
            ),
            chineseTitle: "窗口管理",
            englishTitle: "Windows",
            symbol: "rectangle.split.2x2"
        )
    }

    private func hoverSpec(
        hoverSettingsStore: HoverOverlaySettingsStore,
        onApplyHoverSettings: @escaping (HoverOverlaySettings) -> Void
    ) -> TabSpec {
        TabSpec(
            viewController: NSHostingController(
                rootView: SettingsTabContent(store: hoverSettingsStore) {
                    HoverSettingsTab(
                        store: hoverSettingsStore,
                        onApply: onApplyHoverSettings
                    )
                }
            ),
            chineseTitle: "悬停放大",
            englishTitle: "Hover",
            symbol: "arrow.up.left.and.arrow.down.right"
        )
    }

    private func generalSpec(
        appDelegate: AppDelegate,
        hoverStore: HoverOverlaySettingsStore,
        onApplyHoverSettings: @escaping (HoverOverlaySettings) -> Void
    ) -> TabSpec {
        TabSpec(
            viewController: NSHostingController(
                rootView: SettingsTabContent(store: hoverStore) {
                    GeneralTab(
                        appDelegate: appDelegate,
                        hoverSettingsStore: hoverStore,
                        onApplyHoverSettings: onApplyHoverSettings
                    )
                }
            ),
            chineseTitle: "通用",
            englishTitle: "General",
            symbol: "gearshape"
        )
    }

    private func aboutSpec(hoverStore: HoverOverlaySettingsStore) -> TabSpec {
        TabSpec(
            viewController: NSHostingController(
                rootView: SettingsTabContent(store: hoverStore) { AboutTab() }
            ),
            chineseTitle: "关于",
            englishTitle: "About",
            symbol: "info.circle"
        )
    }

    /// Re-creates the tab items with titles in the current language,
    /// preserving the selected tab.
    private func rebuildTabs() {
        let selectedIndex = selectedTabViewItemIndex
        while let item = tabView.tabViewItems.last {
            tabView.removeTabViewItem(item)
        }
        for spec in specs {
            let item = NSTabViewItem(viewController: spec.viewController)
            item.label = AppPreferences.shared.isEnglish
                ? spec.englishTitle
                : spec.chineseTitle
            let title = item.label
            item.image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: title)
            addTabViewItem(item)
        }
        if selectedIndex >= 0, selectedIndex < tabView.tabViewItems.count {
            tabView.selectTabViewItem(at: selectedIndex)
        }
    }
}

/// Wraps a tab's content with the app-wide appearance override and, on
/// macOS 26+, a Liquid Glass backdrop tinted by the user's preference —
/// the same material as the hover tray and the management HUD.
private struct SettingsTabContent<Content: View>: View {
    let store: HoverOverlaySettingsStore
    @ViewBuilder var content: Content
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        content
            .background { glassBackdrop }
            .preferredColorScheme(preferences.appearance.resolvedScheme)
    }

    @ViewBuilder
    private var glassBackdrop: some View {
        if #available(macOS 26.0, *) {
            let tint = GlassTint.resolved(hex: store.settings.glassTintColorHex)
            let style = tint.map { Glass.regular.tint(Color(nsColor: $0)) } ?? Glass.regular
            Rectangle()
                .glassEffect(style, in: Rectangle())
                .ignoresSafeArea()
        }
    }
}

/// Hides the grouped form/list backgrounds on macOS 26+ so each tab's
/// content sits directly on the window's glass backdrop; before 26 the
/// standard opaque grouped look is kept.
struct HiddenGlassCompatibleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
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
        .modifier(HiddenGlassCompatibleBackground())
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
