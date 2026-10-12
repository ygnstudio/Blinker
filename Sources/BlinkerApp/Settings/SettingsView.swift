import BlinkerCore
import SwiftUI

/// Existing settings pages embedded in the shared workbench window.
struct SettingsView: View {
    @EnvironmentObject private var menuBarStatus: SystemStatusMonitor
    @EnvironmentObject private var systemAudio: SystemAudioController
    @EnvironmentObject private var bluetoothScanner: BluetoothLEScanner
    @EnvironmentObject private var screenEffects: ScreenEffectController
    @EnvironmentObject private var workbench: WorkbenchNavigation
    @Environment(\.eclipsePalette) private var palette
    @EnvironmentObject var hotkeyManager: HotkeyManager
    let onApplyHoverSettings: (HoverOverlaySettings) -> Void
    let onSnapEnabledChange: (Bool) -> Void
    let onShowOnboarding: () -> Void
    let onShowAbout: () -> Void
    let onShowStatusPanel: () -> Void
    let onOpenApplications: () -> Void
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject private var preferences = AppPreferences.shared

    var body: some View {
        settingsLayout
            .preferredColorScheme(preferences.appearance.resolvedScheme)
            .sheet(isPresented: $navigation.showsOnboarding) {
                OnboardingView { openRules in
                    navigation.showsOnboarding = false
                    if openRules {
                        onOpenApplications()
                    }
                }
                .frame(width: 600, height: 580)
            }
            .onChange(of: workbench.section, initial: true) { _, _ in
                alignSelectionWithSection()
                hotkeyManager.endRecording()
            }
            .onDisappear { hotkeyManager.endRecording() }
            .onChange(of: navigation.selection) { _, _ in hotkeyManager.endRecording() }
    }

    private var settingsLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            if pages.count > 1 {
                pageList
                    .frame(width: 168)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(navigation.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(palette.text)
                    Spacer(minLength: 0)
                    if workbench.section == .devices || workbench.section == .system {
                        Button("状态面板", systemImage: "menubar.rectangle", action: onShowStatusPanel)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)

                detail
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .toggleStyle(EclipseToggleStyle())
                    .controlSize(.regular)
            }
        }
        .tint(palette.accent)
    }

    private var pageList: some View {
        EclipseSelectionList(pages, id: \.self, selection: $navigation.sidebarSelection) { page, _ in
            Label {
                Text(title(for: page))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol(for: page))
            }
        }
        .accessibilityLabel("当前分区页面")
    }

    private var pages: [SettingsSidebarSelection] {
        switch workbench.section {
        case .windows:
            [.hover, .browser, .windows, .shortcuts].map(SettingsSidebarSelection.destination)
        case .devices:
            [.icon, .battery, .network, .audio, .bluetooth, .storage, .performance]
                .map(SettingsSidebarSelection.menuBar)
        case .system:
            [.menuBar(.panel), .menuBar(.quickActions), .destination(.effects)]
        case .scenes:
            [.destination(.workspaces)]
        case .settings:
            [.destination(.general), .destination(.permissions)]
        case .apps, .library, .tools:
            []
        }
    }

    private func alignSelectionWithSection() {
        guard let first = pages.first,
              !pages.contains(where: { $0 == navigation.sidebarSelection }) else { return }
        navigation.sidebarSelection = first
    }

    private func title(for page: SettingsSidebarSelection) -> String {
        switch page {
        case let .destination(destination): destination.title
        case let .menuBar(page): page.title
        }
    }

    private func symbol(for page: SettingsSidebarSelection) -> String {
        switch page {
        case let .destination(destination): destination.symbol
        case let .menuBar(page): page.symbol
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .general {
        case .general: GeneralTab(onShowOnboarding: onShowOnboarding, onShowAbout: onShowAbout)
        case .menuBar: MenuBarSettingsTab(monitor: menuBarStatus, audio: systemAudio,
                                          scanner: bluetoothScanner, navigation: navigation)
        case .effects: ScreenEffectsSettingsTab(controller: screenEffects)
        case .permissions: PermissionsSettingsTab(navigation: navigation)
        case .workspaces:
            Form { WorkspaceSettingsSection() }
                .modifier(NativeFormSurface())
        case .hover: HoverSettingsTab(onApply: onApplyHoverSettings,
                                      onOpenShortcuts: { navigation.selection = .shortcuts })
        case .browser: WindowBrowserSettingsTab()
        case .windows: WindowManagementTab(onSnapEnabledChange: onSnapEnabledChange,
                                           onOpenShortcuts: { navigation.selection = .shortcuts })
        case .shortcuts: ShortcutsSettingsTab(onOpenBrowser: { navigation.selection = .browser })
        }
    }
}
