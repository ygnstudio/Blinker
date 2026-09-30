import AppKit
import BlinkerCore
import SwiftUI

/// Left click opens app rules; the context menu also exposes preferences.
final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator: InterceptionCoordinator
    /// Invoked for the settings entries (left click and menu item).
    var onOpenSettings: (() -> Void)?
    var onPauseAll: ((Int?) -> Void)?
    var onResumeAll: (() -> Void)?
    private var targetApp: NSRunningApplication?
    var onOpenApplications: (() -> Void)?

    init(coordinator: InterceptionCoordinator) {
        self.coordinator = coordinator
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "circle.circle",
            accessibilityDescription: "Blinker"
        )
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // The action must fire for secondary clicks too, otherwise the
        // context menu can never be shown.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || (event?.type == .otherMouseUp && event?.modifierFlags.contains(.control) == true)
        if isSecondaryClick {
            showContextMenu()
        } else {
            onOpenApplications?()
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        targetApp = NSWorkspace.shared.frontmostApplication
        let menu = NSMenu()
        menu.delegate = self

        let statusRow = NSMenuItem()
        let hostingView = NSHostingView(rootView: InterceptorStatusRow(coordinator: coordinator))
        // Size to the localized status text (with a floor), so longer
        // labels never clip inside the menu row.
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: max(220, ceil(fittingSize.width)), height: max(24, ceil(fittingSize.height)))
        )
        statusRow.view = hostingView
        menu.addItem(statusRow)
        menu.addItem(.separator())

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

        // The menu only opens on right click via the action handler, so it
        // is attached just for this invocation and detached on close —
        // otherwise it would also swallow the plain left click.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    @objc private func retryInterceptorClicked() {
        coordinator.stop()
        coordinator.start()
    }

    private func addPauseItems(to menu: NSMenu) {
        let title = coordinator.isIntercepting ? String(localized: "暂停全部") : String(localized: "恢复 Blinker")
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
