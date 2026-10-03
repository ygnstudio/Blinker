import BlinkerCore
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, hover, browser, windows, shortcuts, permissions

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: String(localized: "通用")
        case .permissions: String(localized: "隐私与权限")
        case .hover: String(localized: "悬停按钮")
        case .browser: String(localized: "预览与切换")
        case .windows: String(localized: "窗口布局")
        case .shortcuts: String(localized: "快捷键")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .permissions: "hand.raised"
        case .hover: "arrow.up.left.and.arrow.down.right"
        case .browser: "macwindow.on.rectangle"
        case .windows: "rectangle.split.2x2"
        case .shortcuts: "keyboard"
        }
    }
}

/// Shared routing lets About and contextual links reveal the same settings window.
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsDestination? = .general
}

/// Preferences only. App rules are managed in their own window.
struct SettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    let onApplyHoverSettings: (HoverOverlaySettings) -> Void
    let onSnapEnabledChange: (Bool) -> Void
    let onOpenApplications: () -> Void
    let onShowOnboarding: () -> Void
    let onShowAbout: () -> Void
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsDestination.allCases, selection: $navigation.selection) { destination in
                Label {
                    Text(destination.title)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: destination.symbol)
                }
                .tag(destination)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle((navigation.selection ?? .general).title)
                .toolbar {
                    ToolbarItem {
                        Button("应用规则", systemImage: "macwindow.on.rectangle", action: onOpenApplications)
                            .labelStyle(.titleAndIcon)
                    }
                }
        }
        .preferredColorScheme(preferences.appearance.resolvedScheme)
        .onDisappear { hotkeyManager.endRecording() }
        .onChange(of: navigation.selection) { _, _ in hotkeyManager.endRecording() }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .general {
        case .general: GeneralTab(onShowOnboarding: onShowOnboarding, onShowAbout: onShowAbout)
        case .permissions: PermissionsSettingsTab()
        case .hover: HoverSettingsTab(onApply: onApplyHoverSettings,
                                      onOpenShortcuts: { navigation.selection = .shortcuts })
        case .browser: WindowBrowserSettingsTab()
        case .windows: WindowManagementTab(onSnapEnabledChange: onSnapEnabledChange)
        case .shortcuts: ShortcutsSettingsTab(onOpenBrowser: { navigation.selection = .browser })
        }
    }
}
