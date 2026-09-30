import AppKit
import BlinkerCore
import Combine
import os
import SwiftUI

/// Composition root: owns the long-lived stores and helpers, wires the
/// three collaborators (status item, settings window, interception
/// coordinator) together, and mirrors the interception status for the
/// SwiftUI views that observe it.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let ruleStore = RuleStore()
    let hoverOverlaySettingsStore = HoverOverlaySettingsStore()
    /// Named window-layout workspaces for the window-management tab.
    let workspaceStore = WorkspaceStore()

    /// Executes window actions on the frontmost window; shared by the
    /// window-management tab and the global hotkeys.
    private(set) lazy var frontWindowPerformer = FrontWindowActionPerformer(
        performer: DefaultWindowActionPerformer()
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
        controller.onOpenApplications = { [weak self] in self?.openApplications() }
        return controller
    }()

    private lazy var settingsWindowController = SettingsWindowController { [weak self] in
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
                onOpenApplications: openApplications
            )
            .environmentObject(ruleStore)
            .environmentObject(hoverOverlaySettingsStore)
            .environmentObject(hotkeyManager)
            .environmentObject(workspaceStore)
            .environmentObject(interception)
        )
    }

    private lazy var applicationsWindowController = SettingsWindowController(
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

    private var ruleWindows: [AppRule.ID: SettingsWindowController] = [:]

    func openApplications() {
        applicationsWindowController.show()
    }

    private func openRule(_ rule: AppRule) {
        if ruleWindows[rule.id] == nil {
            ruleWindows[rule.id] = SettingsWindowController(
                title: rule.displayName,
                autosaveName: "BlinkerRule-" + rule.id,
                contentSize: NSSize(width: 500, height: 600),
                minimumSize: NSSize(width: 420, height: 440)
            ) { [ruleStore] in
                NSHostingController(rootView: ApplicationRuleEditor(ruleStore: ruleStore, ruleID: rule.id))
            }
        }
        ruleWindows[rule.id]?.show()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Menu bar app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        statusItemController.install()
        interception.start()
        wireHoverToggleHotkey()
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
