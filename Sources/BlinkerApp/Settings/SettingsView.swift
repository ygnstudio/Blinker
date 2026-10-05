import BlinkerCore
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, menuBar, effects, hover, browser, windows, shortcuts, permissions

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: String(localized: "通用")
        case .menuBar: String(localized: "状态图标")
        case .effects: String(localized: "屏幕特效")
        case .permissions: String(localized: "隐私与权限")
        case .hover: String(localized: "悬停按钮")
        case .browser: String(localized: "预览与切换")
        case .windows: String(localized: "窗口管理")
        case .shortcuts: String(localized: "快捷键")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .effects: "macbook"
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
    /// Sub-page within the status-icon tab, e.g. deep links from the status panel.
    @Published var menuBarPage: MenuBarSettingsPage = .icon
}

/// Preferences only. App rules are managed in their own window.
struct SettingsView: View {
    @EnvironmentObject private var menuBarStatus: SystemStatusMonitor
    @EnvironmentObject private var systemAudio: SystemAudioController
    @EnvironmentObject private var screenEffects: ScreenEffectController
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
            List(selection: $navigation.selection) {
                Section {
                    destinations([.general, .permissions])
                }
                Section("窗口操作") {
                    destinations([.hover, .browser, .windows, .shortcuts])
                }
                Section("外观与特效") {
                    destinations([.menuBar, .effects])
                }
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

    private func destinations(_ destinations: [SettingsDestination]) -> some View {
        ForEach(destinations) { destination in
            Label {
                Text(destination.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: destination.symbol)
            }
            .tag(destination)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .general {
        case .general: GeneralTab(onShowOnboarding: onShowOnboarding, onShowAbout: onShowAbout)
        case .menuBar: MenuBarSettingsTab(monitor: menuBarStatus, audio: systemAudio, navigation: navigation)
        case .effects: ScreenEffectsSettingsTab(controller: screenEffects)
        case .permissions: PermissionsSettingsTab()
        case .hover: HoverSettingsTab(onApply: onApplyHoverSettings,
                                      onOpenShortcuts: { navigation.selection = .shortcuts })
        case .browser: WindowBrowserSettingsTab()
        case .windows: WindowManagementTab(onSnapEnabledChange: onSnapEnabledChange,
                                           onOpenShortcuts: { navigation.selection = .shortcuts })
        case .shortcuts: ShortcutsSettingsTab(onOpenBrowser: { navigation.selection = .browser })
        }
    }
}
