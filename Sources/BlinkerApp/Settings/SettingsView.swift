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

    /// The sidebar glyph — a monochrome SF Symbol, the System Settings
    /// convention; it follows the accent color and appearance
    /// automatically.
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

/// The settings window's root, mirroring the system split layout: a flat
/// single-section sidebar with monochrome glyphs (Liquid Glass on
/// macOS 26+), the pane title in the toolbar row, and grouped form cards
/// on the standard window background. Every view observes
/// `AppPreferences`, so language and appearance changes re-render in
/// place.
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
    @State private var showingAppLibrary = false
    /// The selected rule in the rules tab; owned here so the app-library
    /// sheet can auto-select a newly added rule.
    @State private var ruleSelection: AppRule.ID?

    private var selectedSection: SettingsSection { selection ?? .rules }

    var body: some View {
        NavigationSplitView {
            sidebarList
                // The add-app footer is a permanent sidebar affordance —
                // constant height on every tab, no jump when switching.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    sidebarFooter
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
            detailContent
                .toolbar(removing: .sidebarToggle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The pane title lives in the toolbar row — the Tahoe System
        // Settings convention; the detail column starts directly with
        // content.
        .navigationTitle(selectedSection.title)
        .preferredColorScheme(preferences.appearance.resolvedScheme)
        // The hotkey recorder installs an app-local key monitor; if the
        // window goes away mid-recording, that monitor must not survive to
        // swallow (and bind!) some later keystroke.
        .onDisappear {
            hotkeyManager.endRecording()
        }
        .sheet(isPresented: $showingAppLibrary) {
            AppLibraryPicker { app in
                let rule = AppRule(
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.name
                )
                ruleStore.upsert(rule)
                // Jump straight to the new rule's matrix instead of making
                // the user hunt for it in the list.
                selection = .rules
                ruleSelection = rule.id
            }
        }
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            // One flat section — the System Settings convention; no group
            // headers.
            Section {
                ForEach(SettingsSection.allCases) { section in
                    sidebarRow(section)
                }
            }
        }
        // .sidebar renders as the system's Liquid Glass sidebar material
        // on macOS 26+, the classic translucent material before that.
        .listStyle(.sidebar)
    }

    /// The Notes-style bottom of the sidebar: the add-app action lives
    /// where Notes keeps its "new folder" button. `safeAreaInset` pins it
    /// inside the sidebar so the material runs continuously behind it; the
    /// label carries the text so the affordance needs no tooltip.
    private var sidebarFooter: some View {
        HStack {
            Button {
                showingAppLibrary = true
            } label: {
                Label(tr("添加应用", "Add App"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// One sidebar row: monochrome glyph plus title. The tag drives the
    /// List's selection highlight.
    private func sidebarRow(_ section: SettingsSection) -> some View {
        Label(section.title, systemImage: section.symbol)
            .padding(.vertical, 5)
            .tag(section)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .rules:
            RulesTab(
                ruleStore: ruleStore,
                selection: $ruleSelection,
                onAddApp: { showingAppLibrary = true }
            )
        case .windows:
            WindowManagementTab(
                hotkeyManager: hotkeyManager,
                workspaceStore: workspaceStore,
                onSnapEnabledChange: onSnapEnabledChange
            )
        case .hover:
            HoverSettingsTab(
                store: hoverSettingsStore,
                hotkeyManager: hotkeyManager,
                onApply: onApplyHoverSettings
            )
        case .general:
            GeneralTab(appDelegate: appDelegate)
        case .about:
            AboutTab()
        }
    }
}
