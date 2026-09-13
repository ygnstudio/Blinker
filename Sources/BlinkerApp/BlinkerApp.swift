import BlinkerCore
import SwiftUI

@main
struct BlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var ruleStore: RuleStore

    init() {
        ruleStore = AppDelegate.sharedRuleStore
    }

    var body: some Scene {
        MenuBarExtra("Blinker", systemImage: "circle.circle") {
            InterceptorStatusRow(appDelegate: appDelegate)
            Divider()
            ruleSection
            Divider()
            Button(tr("设置…", "Settings…")) {
                appDelegate.bringToFront()
                openSettings()
            }
            Button(
                appDelegate.isIntercepting
                    ? tr("暂停拦截", "Pause Interception")
                    : tr("恢复拦截", "Resume Interception")
            ) {
                appDelegate.toggleInterception()
            }
            .disabled(!appDelegate.isIntercepting && appDelegate.status == .noPermission)
            Button(tr("重新检查权限", "Re-check Permission")) {
                appDelegate.attemptStartInterceptor()
            }
            .disabled(appDelegate.isIntercepting)
            Divider()
            Button(tr("退出 Blinker", "Quit Blinker")) { NSApp.terminate(nil) }
        }

        Settings {
            SettingsScreen(
                ruleStore: appDelegate.ruleStore,
                hoverSettingsStore: appDelegate.hoverOverlaySettingsStore,
                onApplyHoverSettings: appDelegate.applyHoverOverlaySettings,
                frontWindowPerformer: appDelegate.frontWindowPerformer,
                hotkeyManager: appDelegate.hotkeyManager,
                onSnapEnabledChange: appDelegate.applySnapEnabled
            )
        }
    }

    /// Quick profile switcher: one entry per rule profile, checkmark on the
    /// active one. Switching here also reflects in the settings rules tab.
    @ViewBuilder
    private var ruleSection: some View {
        if ruleStore.profiles.count > 1 {
            ForEach(ruleStore.profiles) { profile in
                if profile.id == ruleStore.activeProfileID {
                    Button {
                        // Already active; no-op but keeps the menu row tappable.
                    } label: {
                        Label(profile.name, systemImage: "checkmark")
                    }
                } else {
                    Button(profile.name) {
                        ruleStore.switchProfile(to: profile.id)
                    }
                }
            }
        }
    }
}
