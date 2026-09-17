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
        return controller
    }()

    private lazy var settingsWindowController = SettingsWindowController { [weak self] in
        guard let self else {
            fatalError("AppDelegate deallocated before the settings window was created")
        }
        return SettingsView(
            ruleStore: ruleStore,
            hoverSettingsStore: hoverOverlaySettingsStore,
            onApplyHoverSettings: applyHoverOverlaySettings,
            hotkeyManager: hotkeyManager,
            workspaceStore: workspaceStore,
            onSnapEnabledChange: applySnapEnabled,
            appDelegate: self
        )
    }

    /// Mirrors `interception.status` so SwiftUI views observing the app
    /// delegate keep updating (the coordinator's changes land on the main
    /// thread already).
    @Published private(set) var status: InterceptorStatus = .checking

    /// True while the click-interception stack is running; derived from
    /// `status` so the two can never disagree.
    var isIntercepting: Bool { status == .running }

    private var statusCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_: Notification) {
        // Menu bar app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        statusCancellable = interception.$status.sink { [weak self] in self?.status = $0 }
        statusItemController.install()
        interception.start()
        wireHoverToggleHotkey()
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

    func bringToFront() {
        settingsWindowController.bringToFront()
    }

    /// Pauses or resumes click interception from the settings toggle.
    func toggleInterception() {
        interception.toggle()
    }

    /// Retries starting interception (General tab's tap-failed branch).
    func retryInterception() {
        interception.start()
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
