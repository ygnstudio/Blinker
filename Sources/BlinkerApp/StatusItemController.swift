import AppKit
import BlinkerCore
import SwiftUI

/// Left click follows the configured action; the context menu retains app controls.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private let coordinator: InterceptionCoordinator
    private let systemStatus: SystemStatusMonitor
    private let audio: SystemAudioController
    private let preferences: MenuBarPreferences
    private var presentation: MenuBarPresentation?
    /// Invoked for the settings menu entry.
    var onOpenSettings: (() -> Void)?
    /// Invoked by status-panel section gears; carries the target status-icon page.
    var onOpenMenuBarPage: ((MenuBarSettingsPage) -> Void)?
    var onPauseAll: ((Int?) -> Void)?
    var onResumeAll: (() -> Void)?
    private var targetApp: NSRunningApplication?
    var onOpenApplications: (() -> Void)?
    var onOpenMenuBarSettings: (() -> Void)?
    var screenEffectsState: (() -> (enabled: Bool, paused: Bool))?
    var onToggleScreenEffects: (() -> Void)?
    var desktopState: (() -> (shown: Bool, available: Bool))?
    var onToggleDesktop: (() -> Void)?

    init(coordinator: InterceptionCoordinator, systemStatus: SystemStatusMonitor,
         audio: SystemAudioController, preferences: MenuBarPreferences? = nil) {
        self.coordinator = coordinator
        self.systemStatus = systemStatus
        self.audio = audio
        self.preferences = preferences ?? .shared
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // The action must fire for secondary clicks too, otherwise the
        // context menu can never be shown.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
        statusItem = item
        presentation = MenuBarPresentation(
            item: item, monitor: systemStatus, audio: audio, preferences: preferences,
            onOpenApplications: { [weak self] in self?.onOpenApplications?() },
            onOpenSettings: { [weak self] in self?.onOpenMenuBarSettings?() },
            onOpenMenuBarPage: { [weak self] page in self?.onOpenMenuBarPage?(page) }
        )
        presentation?.start()
    }

    func stop() {
        presentation?.stop()
    }

    func showSystemPanel() {
        presentation?.showPanel()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondaryClick {
            showContextMenu()
        } else {
            if preferences.configuration.leftClick == .panel {
                showSystemPanel()
            } else {
                onOpenApplications?()
            }
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        presentation?.closePanel()
        let menu = makeMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func makeMenu() -> NSMenu {
        targetApp = NSWorkspace.shared.frontmostApplication
        let menu = NSMenu()

        addStatusRows(to: menu)

        let panelItem = NSMenuItem(title: String(localized: "系统状态…"),
                                   action: #selector(openSystemPanelClicked), keyEquivalent: "")
        panelItem.target = self
        menu.addItem(panelItem)
        addScreenEffectsItem(to: menu)
        addDesktopItem(to: menu)
        addPauseItems(to: menu)
        if coordinator.status == .tapFailed || coordinator.status == .partial {
            let retryItem = NSMenuItem(
                title: String(localized: "重试启动拦截"),
                action: #selector(retryInterceptorClicked),
                keyEquivalent: ""
            )
            retryItem.target = self
            menu.addItem(retryItem)
        }

        let applicationsItem = NSMenuItem(
            title: String(localized: "应用规则…"),
            action: #selector(openApplicationsClicked),
            keyEquivalent: ""
        )
        applicationsItem.target = self
        menu.addItem(applicationsItem)
        let settingsItem = NSMenuItem(
            title: String(localized: "设置…"),
            action: #selector(openSettingsClicked),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: String(localized: "退出 Blinker"),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        return menu
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleDesktop) {
            return desktopState?().available == true
        }
        return true
    }

    private func addDesktopItem(to menu: NSMenu) {
        guard let state = desktopState?() else { return }
        let item = NSMenuItem(title: state.shown ? String(localized: "恢复窗口")
            : String(localized: "显示桌面"),
            action: #selector(toggleDesktop), keyEquivalent: "")
        item.target = self
        item.isEnabled = state.available
        menu.addItem(item)
    }

    @objc private func toggleDesktop() {
        onToggleDesktop?()
    }

    private func addScreenEffectsItem(to menu: NSMenu) {
        guard let state = screenEffectsState?(), state.enabled else { return }
        let title = state.paused ? String(localized: "继续屏幕特效") : String(localized: "暂停屏幕特效")
        let item = NSMenuItem(title: title, action: #selector(toggleScreenEffects), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleScreenEffects() {
        onToggleScreenEffects?()
    }

    private func addStatusRows(to menu: NSMenu) {
        addMenuView(NSHostingView(rootView: InterceptorStatusRow(coordinator: coordinator)), to: menu)
        addMenuView(NSHostingView(rootView: SystemStatusMenuView(monitor: systemStatus)), to: menu)
    }

    private func addMenuView(_ view: NSView, to menu: NSMenu) {
        // Measure localized text, including the longest current power-state label.
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: NSSize(
            width: max(240, ceil(size.width)), height: max(24, ceil(size.height))
        ))
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
        menu.addItem(.separator())
    }

    @objc private func openSystemPanelClicked() {
        showSystemPanel()
    }

    @objc private func retryInterceptorClicked() {
        coordinator.stop()
        coordinator.start()
    }

    private func addPauseItems(to menu: NSMenu) {
        let title = coordinator.isIntercepting ? String(localized: "暂停窗口增强") : String(localized: "恢复窗口增强")
        let toggle = NSMenuItem(title: title, action: #selector(togglePause), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let timed = NSMenuItem(title: String(localized: "暂停 10 分钟"), action: #selector(pauseTenMinutes),
                               keyEquivalent: "")
        timed.target = self
        menu.addItem(timed)
        if let app = targetApp, let bundleID = app.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier {
            let prefix = coordinator.sessionPause.contains(bundleID)
                ? String(localized: "恢复当前应用：") : String(localized: "暂停当前应用：")
            let item = NSMenuItem(title: prefix + (app.localizedName ?? bundleID),
                                  action: #selector(toggleCurrentApp), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    @objc private func togglePause() {
        if coordinator.isIntercepting {
            onPauseAll?(nil)
        } else {
            onResumeAll?()
        }
    }

    @objc private func pauseTenMinutes() {
        onPauseAll?(10)
    }

    @objc private func toggleCurrentApp() {
        guard let bundleID = targetApp?.bundleIdentifier else { return }
        coordinator.toggleAppPause(bundleID)
    }

    func menuDidClose(_: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func openSettingsClicked() {
        onOpenSettings?()
    }

    @objc private func openApplicationsClicked() {
        onOpenApplications?()
    }
}

/// Live status row shown at the top of the menu bar menu.
struct InterceptorStatusRow: View {
    @ObservedObject var coordinator: InterceptionCoordinator

    /// Status color by severity, not a binary on/off: failures (missing
    /// permission, tap failure) read red; transitional and paused states
    /// read orange; only a running interceptor reads green.
    private var statusColor: Color {
        switch coordinator.status {
        case .running: .green
        case .checking, .paused, .partial: .orange
        case .noPermission, .tapFailed: .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(coordinator.status.localizedLabel)
                .font(.callout)
        }
        .accessibilityElement(children: .combine)
    }
}
