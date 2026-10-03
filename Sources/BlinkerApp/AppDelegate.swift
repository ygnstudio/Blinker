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
    private var appearanceSubscription: AnyCancellable?
    private lazy var permissions = PermissionController(thumbnails: windowBrowser.thumbnails)
    private lazy var permissionAssistant = PermissionAssistantController(permissions: permissions)
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
        let controller = StatusItemController(coordinator: interception)
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        controller.onPauseAll = { [weak self] minutes in self?.interception.pause(minutes: minutes) }
        controller.onResumeAll = { [weak self] in self?.interception.start() }
        controller.onOpenApplications = { [weak self] in self?.openApplications() }
        return controller
    }()

    private lazy var settingsWindowController =
        AppWindowController(title: String(localized: "通用")) { [weak self] in
            guard let self else {
                fatalError("AppDelegate deallocated before the settings window was created")
            }
            // The single injection point for the settings tree: the stores flow
            // down to the tabs through the environment, while the two behavior
            // callbacks stay explicit.
            return NSHostingController(
                rootView: SettingsView(
                    onApplyHoverSettings: applyHoverOverlaySettings,
                    onSnapEnabledChange: applySnapEnabled,
                    onOpenApplications: openApplications,
                    onShowOnboarding: replayOnboarding,
                    onShowAbout: openAbout,
                    navigation: settingsNavigation
                )
                .environmentObject(hoverOverlaySettingsStore)
                .environmentObject(hotkeyManager)
                .environmentObject(workspaceStore)
                .environmentObject(interception)
                .environmentObject(windowBrowser)
                .environmentObject(permissions)
                .environmentObject(permissionAssistant)
            )
        }

    private lazy var aboutWindowController = AppWindowController(
        title: String(localized: "关于 Blinker"), autosaveName: "BlinkerAbout",
        contentSize: NSSize(width: 560, height: 480), minimumSize: NSSize(width: 480, height: 420)
    ) { [weak self] in
        NSHostingController(rootView: AboutView(onOpenPermissions: { [weak self] in
            self?.settingsNavigation.selection = .permissions
            self?.openSettings()
        }))
    }

    private lazy var applicationsWindowController = AppWindowController(
        title: String(localized: "应用规则"),
        autosaveName: "BlinkerApplications",
        contentSize: NSSize(width: 600, height: 480),
        minimumSize: NSSize(width: 480, height: 360)
    ) { [unowned self] in
        NSHostingController(rootView: ApplicationRulesView(
            onEdit: openRule,
            onOpenSettings: openSettings
        ).environmentObject(ruleStore))
    }

    private var onboardingWindowController: AppWindowController?

    func replayOnboarding() {
        onboardingWindowController?.close()
        showOnboarding()
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

    private var ruleWindows: [AppRule.ID: AppWindowController] = [:]

    func openApplications() {
        applicationsWindowController.show()
    }

    private func openRule(_ rule: AppRule) {
        if ruleWindows[rule.id] == nil {
            ruleWindows[rule.id] = AppWindowController(
                title: rule.displayName,
                autosaveName: "BlinkerRule-" + rule.id,
                contentSize: NSSize(width: 500, height: 600),
                minimumSize: NSSize(width: 420, height: 440)
            ) { [ruleStore] in
                NSHostingController(rootView: ApplicationRuleEditor(ruleStore: ruleStore, ruleID: rule.id))
            }
            ruleWindows[rule.id]?.onClose = { [weak self] in self?.ruleWindows[rule.id] = nil }
        }
        ruleWindows[rule.id]?.show()
    }

    func applicationDidFinishLaunching(_: Notification) {
        observeAppearance()
        // Menu bar app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        statusItemController.install()
        interception.onPauseStateChanged = { [weak self] paused in
            self?.hotkeyManager.setSessionPaused(paused)
            self?.windowBrowser.setPaused(paused)
        }
        interception.start()
        wireHoverToggleHotkey()
        windowBrowser.start()
        if !AppPreferences.shared.hasSeenOnboarding {
            showOnboarding()
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
        openSettings()
        return false
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
        settingsWindowController.show()
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
