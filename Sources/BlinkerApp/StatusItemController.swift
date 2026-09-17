import AppKit
import SwiftUI

/// The menu bar icon and its context menu. The app's front door: a plain
/// left click opens the settings window; the context menu (right click)
/// only carries the live status row, settings and quit — interception
/// pause lives in the settings' General tab instead of the menu.
final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator: InterceptionCoordinator
    /// Invoked for the settings entries (left click and menu item).
    var onOpenSettings: (() -> Void)?

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
            onOpenSettings?()
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
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

        if coordinator.status == .tapFailed {
            let retryItem = NSMenuItem(
                title: String(localized: "重试启动拦截"),
                action: #selector(retryInterceptorClicked),
                keyEquivalent: ""
            )
            retryItem.target = self
            menu.addItem(retryItem)
        }

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
        coordinator.start()
    }

    func menuDidClose(_: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func openSettingsClicked() {
        onOpenSettings?()
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
        case .checking, .paused: .orange
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
