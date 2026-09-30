import BlinkerCore
import SwiftUI

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, hover, windows, about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: String(localized: "通用")
        case .hover: String(localized: "悬停放大")
        case .windows: String(localized: "窗口管理")
        case .about: String(localized: "关于")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .hover: "arrow.up.left.and.arrow.down.right"
        case .windows: "rectangle.split.2x2"
        case .about: "info.circle"
        }
    }
}

/// Preferences only. App rules are managed in their own window.
struct SettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    let onApplyHoverSettings: (HoverOverlaySettings) -> Void
    let onSnapEnabledChange: (Bool) -> Void
    let onOpenApplications: () -> Void
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var selection: SettingsDestination? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsDestination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle((selection ?? .general).title)
                .toolbar {
                    ToolbarItem {
                        Button("应用规则", systemImage: "macwindow.on.rectangle", action: onOpenApplications)
                    }
                }
        }
        .preferredColorScheme(preferences.appearance.resolvedScheme)
        .onDisappear { hotkeyManager.endRecording() }
        .onChange(of: selection) { _, _ in hotkeyManager.endRecording() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general: GeneralTab()
        case .hover: HoverSettingsTab(onApply: onApplyHoverSettings)
        case .windows: WindowManagementTab(onSnapEnabledChange: onSnapEnabledChange)
        case .about: AboutTab()
        }
    }
}
