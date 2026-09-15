import BlinkerCore
import SwiftUI

/// One entry in the settings sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    case rules
    case windows
    case hover
    case general
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .rules: tr("规则", "Rules")
        case .windows: tr("窗口管理", "Windows")
        case .hover: tr("悬停放大", "Hover")
        case .general: tr("通用", "General")
        case .about: tr("关于", "About")
        }
    }

    /// Monochrome sidebar symbol, matching System Settings' own sidebar —
    /// first-party settings windows use plain glyphs, not icon tiles.
    var symbol: String {
        switch self {
        case .rules: "list.bullet.rectangle"
        case .windows: "rectangle.split.2x2"
        case .hover: "arrow.up.left.and.arrow.down.right"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

/// The settings window's root: a System Settings–style sidebar plus detail
/// column, replacing the old toolbar tab strip. Every view observes
/// `AppPreferences`, so language and appearance changes re-render in
/// place — the AppKit tab-rebuilding hack is gone with the tabs.
struct SettingsView: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var hoverSettingsStore: HoverOverlaySettingsStore
    let onApplyHoverSettings: (HoverOverlaySettings) -> Void
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var workspaceStore: WorkspaceStore
    let onSnapEnabledChange: (Bool) -> Void
    let appDelegate: AppDelegate

    @ObservedObject private var preferences = AppPreferences.shared
    @State private var selection: SettingsSection? = .rules

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
            detailContent
                .navigationTitle((selection ?? .rules).title)
                // System Settings carries no centered toolbar title; the
                // selected sidebar row is the title.
                .toolbar(removing: .title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(preferences.appearance.resolvedScheme)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .rules {
        case .rules:
            RulesTab(ruleStore: ruleStore)
        case .windows:
            WindowManagementTab(
                hotkeyManager: hotkeyManager,
                workspaceStore: workspaceStore,
                onSnapEnabledChange: onSnapEnabledChange
            )
        case .hover:
            HoverSettingsTab(store: hoverSettingsStore, onApply: onApplyHoverSettings)
        case .general:
            GeneralTab(appDelegate: appDelegate)
        case .about:
            AboutTab()
        }
    }
}

