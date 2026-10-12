import AppKit
import BlinkerCore
import Combine
import os
import SwiftUI

/// Composition root: owns the long-lived stores and helpers, wires the
/// three collaborators (status item, settings window, interception
/// coordinator) together, and mirrors the interception status for the
/// SwiftUI views that observe it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let feedback = ActionFeedbackController.shared
    private let windowBrowser = WindowBrowserController()
    private let settingsNavigation = SettingsNavigation()
    private let rulesNavigation = RulesNavigation()
    private let workbenchNavigation = WorkbenchNavigation()
    private lazy var applicationMenu = ApplicationMenu(delegate: self)
    private var appearanceSubscription: AnyCancellable?
    private lazy var permissions = PermissionController(thumbnails: windowBrowser.thumbnails)
    private lazy var permissionAssistant = PermissionAssistantController(permissions: permissions)
    let menuBarStatus = SystemStatusMonitor()
    let systemAudio = SystemAudioController()
    let bluetoothScanner = BluetoothLEScanner()
    private lazy var screenEffects = ScreenEffectController()
    private lazy var desktopActions = DesktopActionsCoordinator(
        preferences: .shared,
        permissions: permissions
    )
    let ruleStore = RuleStore()
    let hoverOverlaySettingsStore = HoverOverlaySettingsStore()
    /// Named window-layout workspaces for the window-management tab.
    let workspaceStore = WorkspaceStore()

    /// Executes window actions on the frontmost window; shared by the
    /// window-management tab and the global hotkeys.
    private(set) lazy var frontWindowPerformer = FrontWindowActionPerformer(
        performer: DefaultWindowActionPerformer.shared
    )

    /// Global hotkeys; independent of click interception, always available.
    private(set) lazy var hotkeyManager = HotkeyManager(frontWindowPerformer: frontWindowPerformer)

    private lazy var interception = InterceptionCoordinator(
        ruleStore: ruleStore,
        hoverOverlaySettingsStore: hoverOverlaySettingsStore,
        workspaceStore: workspaceStore
    )

    private lazy var statusItemController: StatusItemController = {
        let controller = StatusItemController(
            coordinator: interception,
            systemStatus: menuBarStatus,
            audio: systemAudio,
            bluetoothScanner: bluetoothScanner, desktopActions: desktopActions
        )
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        controller.onPauseAll = { [weak self] minutes in self?.interception.pause(minutes: minutes) }
        controller.onResumeAll = { [weak self] in self?.interception.start() }
        controller.onOpenApplications = { [weak self] in self?.openApplications() }
        controller.onOpenMenuBarSettings = { [weak self] in
            self?.settingsNavigation.selection = .menuBar
            self?.applicationWindows.showSettings()
        }
        controller.onOpenMenuBarPage = { [weak self] page in
            self?.settingsNavigation.selection = .menuBar
            self?.settingsNavigation.menuBarPage = page
            self?.applicationWindows.showSettings()
        }
        controller.screenEffectsState = { [weak self] in
            (self?.screenEffects.preferences.configuration.isEnabled == true,
             self?.screenEffects.isPaused == true)
        }
        controller.onToggleScreenEffects = { [weak self] in
            guard let self else { return }
            if screenEffects.isPaused {
                screenEffects.resume()
            } else {
                screenEffects.pause()
            }
        }
        controller.desktopState = { [weak self] in
            guard let self else { return (false, false) }
            return (desktopActions.desktop.isDesktopShown,
                    !desktopActions.isPaused && !desktopActions.desktop.isBusy)
        }
        controller.onToggleDesktop = { [weak self] in self?.desktopActions.toggleDesktop() }
        controller.onKeyboardCleaningPermissionNeeded = { [weak self] in
            guard let self else { return }
            permissions.refresh()
            // Accessibility is the core grant and usually present; guide to
            // whichever half of the keyboard-lock pair is missing.
            permissionAssistant.show(for: permissions.accessibilityGranted
                ? .inputMonitoring : .accessibility)
        }
        return controller
    }()

    private lazy var applicationWindows = NativeApplicationWindows(
        settings: AnyView(makeSettingsContent()), rules: AnyView(makeRulesContent()),
        navigation: workbenchNavigation, settingsNavigation: settingsNavigation,
        onShowStatusPanel: { [weak self] in self?.statusItemController.showSystemPanel() }
    )

    private func makeSettingsContent() -> some View {
        SettingsView(
            onApplyHoverSettings: applyHoverOverlaySettings,
            onSnapEnabledChange: applySnapEnabled,
            onShowOnboarding: replayOnboarding,
            onShowAbout: openAbout,
            onShowStatusPanel: { [weak self] in self?.statusItemController.showSystemPanel() },
            onOpenApplications: openApplications,
            navigation: settingsNavigation
        )
        .environmentObject(ruleStore)
        .environmentObject(hoverOverlaySettingsStore)
        .environmentObject(hotkeyManager)
        .environmentObject(workspaceStore)
        .environmentObject(interception)
        .environmentObject(windowBrowser)
        .environmentObject(permissions)
        .environmentObject(permissionAssistant)
        .environmentObject(menuBarStatus)
        .environmentObject(systemAudio)
        .environmentObject(bluetoothScanner)
        .environmentObject(screenEffects)
        .environmentObject(desktopActions)
    }

    private func makeRulesContent() -> some View {
        RulesWindowContent(
            navigation: rulesNavigation,
            onInspect: { [weak self] appID in
                self?.settingsNavigation.openDiagnostics(appID)
                self?.applicationWindows.showSettings()
            },
            onOpenSettings: openSettings
        )
        .environmentObject(ruleStore)
        .environmentObject(permissions)
        .environmentObject(interception)
    }

    private lazy var aboutWindowController = AppWindowController(
        title: String(localized: "关于 Blinker"), autosaveName: "BlinkerAbout",
        contentSize: NSSize(width: 560, height: 480), minimumSize: NSSize(width: 480, height: 420)
    ) { [weak self] in
        NSHostingController(rootView: AboutView(onOpenPermissions: { [weak self] in
            self?.settingsNavigation.selection = .permissions
            self?.applicationWindows.showSettings()
        }))
    }

    private var onboardingWindowController: AppWindowController?

    func replayOnboarding() {
        settingsNavigation.showsOnboarding = true
        applicationWindows.showSettings()
    }

    func showOnboarding() {
        if onboardingWindowController == nil {
            let controller = AppWindowController(
                title: String(localized: "欢迎使用 Blinker"), autosaveName: "BlinkerOnboarding",
                contentSize: NSSize(width: 600, height: 580), minimumSize: NSSize(width: 600, height: 520)
            ) { [weak self] in
                guard let self else { return NSViewController() }
                let guide = OnboardingView { [weak self] openRules in
                    self?.onboardingWindowController?.close()
                    if openRules {
                        self?.openApplications()
                    }
                }
                return NSHostingController(rootView: guide
                    .environmentObject(permissions)
                    .environmentObject(permissionAssistant))
            }
            controller.onClose = { [weak self] in
                AppPreferences.shared.hasSeenOnboarding = true
                // Drop the view and its step state so replay starts from the welcome page.
                self?.onboardingWindowController = nil
            }
            onboardingWindowController = controller
        }
        onboardingWindowController?.show()
    }

    func openApplications() {
        applicationWindows.showRules()
    }

    func addApplication() {
        openApplications()
        rulesNavigation.showsAppLibrary = true
    }

    func openDiagnostics() {
        settingsNavigation.openDiagnostics()
        applicationWindows.showSettings()
    }

    func applicationWillFinishLaunching(_: Notification) {
        applicationWindows.install()
    }

    func applicationDidFinishLaunching(_: Notification) {
        let launchDestination = LaunchPresentationPolicy.currentDestination(
            hasSeenOnboarding: AppPreferences.shared.hasSeenOnboarding
        )
        applicationMenu.install()
        observeAppearance()
        CompatibilityWindowController.shared.onShowDiagnostics = { [weak self] appID in
            self?.settingsNavigation.openDiagnostics(appID)
            self?.applicationWindows.showSettings()
        }
        // Background services keep their existing menu-bar/Dock placement preference.
        // Present the workspace only for a user-initiated launch after setup.
        NSApp.setActivationPolicy(.accessory)
        statusItemController.install()
        screenEffects.start()
        desktopActions.onWillToggle = { [weak self] in self?.windowBrowser.dismiss() }
        desktopActions.start()
        hotkeyManager.onToggleDesktop = { [weak self] in self?.desktopActions.toggleDesktop() }
        interception.onPauseStateChanged = { [weak self] paused in
            self?.hotkeyManager.setSessionPaused(paused)
            self?.windowBrowser.setPaused(paused)
            self?.desktopActions.setPaused(paused)
        }
        interception.start()
        wireHoverToggleHotkey()
        windowBrowser.start()
        switch launchDestination {
        case .onboarding:
            showOnboarding()
        case .workbench:
            applicationWindows.showRules()
        case .background:
            break
        }
    }

    /// Also covers panels created outside AppWindowController; nil restores system inheritance.
    private func observeAppearance() {
        let preferences = AppPreferences.shared
        NSApp.appearance = preferences.appearance.nsAppearance
        appearanceSubscription = preferences.$appearance
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { appearance in NSApp.appearance = appearance.nsAppearance }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        applicationWindows.showCurrent()
        return false
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        statusItemController.makeMenu()
    }

    /// A menu bar app outlives every window it opens — cleaning overlays,
    /// settings, onboarding. Never let the last close take the process down.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_: Notification) {
        statusItemController.stop()
        screenEffects.stop()
        desktopActions.stop()
    }

    /// The ⌃⌥H global hotkey (configurable) flips hover enlargement without
    /// a trip to the settings window.
    private func wireHoverToggleHotkey() {
        hotkeyManager.onToggleHoverOverlay = { [weak self] in
            guard let self else { return }
            var settings = hoverOverlaySettingsStore.snapshot
            settings.isEnabled.toggle()
            applyHoverOverlaySettings(settings)
        }
    }

    // MARK: - Forwarding (settings UI + menu bar)

    func openSettings() {
        applicationWindows.showSettings()
    }

    func openAbout() {
        aboutWindowController.show()
    }

    /// Persists the drag-to-snap toggle and applies it to the live snapper.
    func applySnapEnabled(_ enabled: Bool) {
        interception.applySnapEnabled(enabled)
    }

    /// Persists hover overlay settings and pushes them to the live overlay
    /// controller (when running) so visible panels refresh immediately.
    func applyHoverOverlaySettings(_ settings: HoverOverlaySettings) {
        interception.applyHoverOverlaySettings(settings)
    }
}
