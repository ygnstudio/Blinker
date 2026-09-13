import BlinkerCore
import SwiftUI

/// The settings window, organized into tabs: per-app rules, the window
/// management toolkit, hover overlay configuration, general preferences and
/// an about page.
struct SettingsScreen: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var hoverSettingsStore: HoverOverlaySettingsStore
    let onApplyHoverSettings: (HoverOverlaySettings) -> Void
    let frontWindowPerformer: FrontWindowActionPerformer
    @ObservedObject var hotkeyManager: HotkeyManager
    let onSnapEnabledChange: (Bool) -> Void
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        TabView {
            RulesTab(ruleStore: ruleStore)
                .tabItem { Label(tr("规则", "Rules"), systemImage: "list.bullet.rectangle") }
            WindowManagementTab(
                frontWindowPerformer: frontWindowPerformer,
                hotkeyManager: hotkeyManager,
                onSnapEnabledChange: onSnapEnabledChange
            )
            .tabItem { Label(tr("窗口管理", "Windows"), systemImage: "rectangle.split.2x2") }
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

/// Per-app remapping of the traffic light buttons, organized into named
/// scenario profiles ("工作", "个人", …) that switch the whole rule table.
private struct RulesTab: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var showingAppLibrary = false
    @State private var showingNewProfileAlert = false
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var draftProfileName = ""

    var body: some View {
        VStack(spacing: 0) {
            profileBar
            Divider()
            if ruleStore.rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
            Divider()
            footerBar
        }
    }

    // MARK: Profile switcher bar

    private var activeProfileBinding: Binding<UUID?> {
        Binding(
            get: { ruleStore.activeProfileID },
            set: { id in
                if let id {
                    ruleStore.switchProfile(to: id)
                }
            }
        )
    }

    private var profileBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
            Picker(tr("规则集", "Profile"), selection: activeProfileBinding) {
                ForEach(ruleStore.profiles) { profile in
                    Text(profile.name).tag(profile.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            Spacer()
            Menu {
                Button(tr("新建规则集…", "New Profile…")) {
                    draftProfileName = ""
                    showingNewProfileAlert = true
                }
                Button(tr("复制当前规则集", "Duplicate Current")) {
                    ruleStore.duplicateProfile()
                }
                Button(tr("重命名当前规则集…", "Rename Current…")) {
                    draftProfileName = ruleStore.profiles
                        .first { $0.id == ruleStore.activeProfileID }?.name ?? ""
                    showingRenameAlert = true
                }
                Divider()
                Button(
                    tr("删除当前规则集", "Delete Current"),
                    role: .destructive,
                    action: { showingDeleteConfirmation = true }
                )
                .disabled(ruleStore.profiles.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert(
            tr("新建规则集", "New Profile"),
            isPresented: $showingNewProfileAlert
        ) {
            TextField(tr("名称", "Name"), text: $draftProfileName)
            Button(tr("创建", "Create")) {
                let name = draftProfileName.trimmingCharacters(in: .whitespaces)
                ruleStore.createProfile(named: name.isEmpty ? untitledName : name)
            }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(
                tr(
                    "创建一个空的规则集并切换过去，然后按场景配置规则。",
                    "Creates an empty profile and switches to it; configure rules per scenario."
                )
            )
        }
        .alert(
            tr("重命名规则集", "Rename Profile"),
            isPresented: $showingRenameAlert
        ) {
            TextField(tr("名称", "Name"), text: $draftProfileName)
            Button(tr("好", "OK")) {
                if let id = ruleStore.activeProfileID {
                    ruleStore.renameProfile(id: id, to: draftProfileName)
                }
            }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            tr("删除当前规则集？", "Delete Current Profile?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(tr("删除", "Delete"), role: .destructive) {
                if let id = ruleStore.activeProfileID {
                    ruleStore.deleteProfile(id: id)
                }
            }
        } message: {
            Text(
                tr(
                    "该规则集里的所有规则都会被删除，且无法恢复。",
                    "Every rule inside this profile will be removed permanently."
                )
            )
        }
    }

    private var untitledName: String {
        tr("未命名规则集", "Untitled Profile")
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
    /// Menu width; the compact variant matrix uses a narrower value.
    var pickerWidth: CGFloat = 84

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
